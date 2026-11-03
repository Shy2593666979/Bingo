from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from dataclasses import dataclass
from typing import Any, Protocol
from urllib.parse import urlparse

import httpx
from openai import AsyncOpenAI

from bingo.config import Settings
from bingo.utils.stickers.content import model_sticker_text


@dataclass(frozen=True, slots=True)
class ModelToolCall:
    call_id: str
    name: str
    arguments: str


@dataclass(frozen=True, slots=True)
class ModelMessage:
    role: str
    content: str = ""
    image_data_urls: tuple[str, ...] = ()
    tool_calls: tuple[ModelToolCall, ...] = ()
    tool_call_id: str | None = None

    def __post_init__(self):
        object.__setattr__(self, "content", model_sticker_text(self.content))


@dataclass(frozen=True, slots=True)
class ModelTextDelta:
    content: str


@dataclass(frozen=True, slots=True)
class ModelToolCalls:
    calls: tuple[ModelToolCall, ...]


ModelStreamEvent = ModelTextDelta | ModelToolCalls


class ModelClient(Protocol):
    async def complete(self, messages: list[ModelMessage]) -> str: ...

    def stream(
        self,
        messages: list[ModelMessage],
        tools: list[dict[str, Any]] | None = None,
    ) -> AsyncIterator[ModelStreamEvent]: ...


class EchoModelClient:
    async def complete(self, messages: list[ModelMessage]) -> str:
        latest = next(
            (message.content for message in reversed(messages) if message.role == "user"),
            "",
        )
        has_images = any(message.image_data_urls for message in messages)
        prefix = "Image received" if has_images else "You said"
        return f"{prefix}: {latest}"

    async def stream(
        self,
        messages: list[ModelMessage],
        tools: list[dict[str, Any]] | None = None,
    ) -> AsyncIterator[ModelStreamEvent]:
        yield ModelTextDelta(await self.complete(messages))


class AgentModelClient:
    """OpenAI SDK adapter for Responses and Chat Completions APIs."""

    def __init__(self, settings: Settings) -> None:
        if not settings.model.api_key:
            raise ValueError("model.api_key is required for the openai_compat provider")
        self._client_options = {
            "api_key": settings.model.api_key,
            "base_url": settings.model.base_url.rstrip("/"),
            "timeout": settings.model.timeout_seconds,
            "max_retries": 0,
        }
        self._model = settings.model.model
        self._api_mode = settings.model.api_mode
        self._trust_env = settings.model.trust_env
        self._reuse_connections = settings.model.reuse_connections
        self._clients = {}
        self._max_output_tokens = settings.model.max_output_tokens
        self._text_extra_body = (
            {"thinking": {"type": settings.model.thinking}} if settings.model.thinking else None
        )
        vision = settings.vision
        uses_dedicated_vision_model = bool(vision.model)
        vision_api_key = vision.api_key if uses_dedicated_vision_model else settings.model.api_key
        if uses_dedicated_vision_model and not vision_api_key:
            raise ValueError("vision.api_key is required when vision.model is configured")
        self._vision_client_options = {
            "api_key": vision_api_key,
            "base_url": (
                vision.base_url if uses_dedicated_vision_model else settings.model.base_url
            ).rstrip("/"),
            "timeout": vision.timeout_seconds or settings.model.timeout_seconds,
            "max_retries": 0,
        }
        self._vision_model = vision.model or settings.model.model
        self._vision_api_mode = (
            vision.api_mode if uses_dedicated_vision_model else settings.model.api_mode
        )
        self._vision_extra_body = (
            {"enable_thinking": vision.enable_thinking} if uses_dedicated_vision_model else None
        )

    def _route(self, messages: list[ModelMessage]) -> tuple[dict[str, Any], str, str, dict | None]:
        if any(message.image_data_urls for message in messages):
            return (
                self._vision_client_options,
                self._vision_model,
                self._vision_api_mode,
                self._vision_extra_body,
            )
        return self._client_options, self._model, self._api_mode, self._text_extra_body

    def _new_client(self, options):
        if self._trust_env:
            return AsyncOpenAI(**options)
        return AsyncOpenAI(
            **options, http_client=httpx.AsyncClient(trust_env=False, timeout=options["timeout"])
        )

    @asynccontextmanager
    async def _client_session(self, options):
        if not self._reuse_connections:
            async with self._new_client(options) as client:
                yield client
            return
        key = id(options)
        if key not in self._clients:
            self._clients[key] = self._new_client(options)
        yield self._clients[key]

    async def aclose(self):
        clients = list(self._clients.values())
        self._clients.clear()
        for client in clients:
            await client.close()

    async def complete(self, messages: list[ModelMessage]) -> str:
        client_options, model, api_mode, extra_body = self._route(messages)
        async with self._client_session(client_options) as client:
            if api_mode == "responses":
                response = await client.responses.create(
                    model=model,
                    input=_responses_input(messages),
                    store=False,
                    extra_body=extra_body,
                    **(
                        {"max_output_tokens": self._max_output_tokens}
                        if self._max_output_tokens
                        else {}
                    ),
                )
                return response.output_text or ""

            response = await client.chat.completions.create(
                model=model,
                messages=_chat_messages(messages),
                extra_body=extra_body,
            )
            return response.choices[0].message.content or ""

    async def stream(
        self,
        messages: list[ModelMessage],
        tools: list[dict[str, Any]] | None = None,
    ) -> AsyncIterator[ModelStreamEvent]:
        client_options, model, api_mode, extra_body = self._route(messages)
        async with self._client_session(client_options) as client:
            if api_mode == "responses":
                async for event in self._stream_responses(
                    client, messages, tools, model=model, extra_body=extra_body
                ):
                    yield event
                return

            async for event in self._stream_chat_completions(
                client, messages, tools, model=model, extra_body=extra_body
            ):
                yield event

    async def _stream_responses(
        self,
        client: AsyncOpenAI,
        messages: list[ModelMessage],
        tools: list[dict[str, Any]] | None,
        *,
        model: str,
        extra_body: dict[str, Any] | None,
    ) -> AsyncIterator[ModelStreamEvent]:
        request: dict[str, Any] = {
            "model": model,
            "input": _responses_input(messages),
            "store": False,
            "stream": True,
        }
        if tools:
            request["tools"] = [_responses_tool(tool) for tool in tools]
            request["tool_choice"] = "auto"
        if extra_body:
            request["extra_body"] = extra_body
        if self._max_output_tokens:
            request["max_output_tokens"] = self._max_output_tokens
        stream = await client.responses.create(**request)
        calls: dict[int, ModelToolCall] = {}
        async for event in stream:
            if event.type == "response.output_text.delta" and event.delta:
                yield ModelTextDelta(event.delta)
            elif event.type == "response.output_item.done":
                item = event.item
                if item.type == "function_call":
                    calls[event.output_index] = ModelToolCall(
                        call_id=item.call_id,
                        name=item.name,
                        arguments=item.arguments or "{}",
                    )
        if calls:
            yield ModelToolCalls(tuple(calls[index] for index in sorted(calls)))

    async def _stream_chat_completions(
        self,
        client: AsyncOpenAI,
        messages: list[ModelMessage],
        tools: list[dict[str, Any]] | None,
        *,
        model: str,
        extra_body: dict[str, Any] | None,
    ) -> AsyncIterator[ModelStreamEvent]:
        request: dict[str, Any] = {
            "model": model,
            "messages": _chat_messages(messages),
            "stream": True,
        }
        if tools:
            request["tools"] = tools
            request["tool_choice"] = "auto"
        if extra_body:
            request["extra_body"] = extra_body
        stream = await client.chat.completions.create(**request)
        call_buffers: dict[int, dict[str, str]] = {}
        async for chunk in stream:
            if not chunk.choices:
                continue
            delta = chunk.choices[0].delta
            if delta.content:
                yield ModelTextDelta(delta.content)
            for tool_delta in delta.tool_calls or []:
                buffer = call_buffers.setdefault(
                    tool_delta.index,
                    {"call_id": "", "name": "", "arguments": ""},
                )
                if tool_delta.id:
                    buffer["call_id"] += tool_delta.id
                if tool_delta.function:
                    buffer["name"] += tool_delta.function.name or ""
                    buffer["arguments"] += tool_delta.function.arguments or ""
        if call_buffers:
            yield ModelToolCalls(
                tuple(ModelToolCall(**call_buffers[index]) for index in sorted(call_buffers))
            )


def _chat_messages(messages: list[ModelMessage]) -> list[dict[str, Any]]:
    output: list[dict[str, Any]] = []
    for message in messages:
        if message.role == "tool":
            output.append(
                {
                    "role": "tool",
                    "tool_call_id": message.tool_call_id,
                    "content": message.content,
                }
            )
            continue
        content: str | list[dict[str, Any]] = message.content
        if message.image_data_urls:
            content = [
                *([{"type": "text", "text": message.content}] if message.content else []),
                *(
                    {
                        "type": "image_url",
                        "image_url": {"url": image_data_url, "detail": "low"},
                    }
                    for image_data_url in message.image_data_urls
                ),
            ]
        item: dict[str, Any] = {"role": message.role, "content": content}
        if message.tool_calls:
            item["tool_calls"] = [
                {
                    "id": call.call_id,
                    "type": "function",
                    "function": {"name": call.name, "arguments": call.arguments},
                }
                for call in message.tool_calls
            ]
        output.append(item)
    return output


def _responses_input(messages: list[ModelMessage]) -> list[dict[str, Any]]:
    output: list[dict[str, Any]] = []
    for message in messages:
        if message.role == "tool":
            output.append(
                {
                    "type": "function_call_output",
                    "call_id": message.tool_call_id,
                    "output": message.content,
                }
            )
            continue
        if message.content or message.image_data_urls:
            content: str | list[dict[str, Any]] = message.content
            if message.image_data_urls:
                content = [
                    *([{"type": "input_text", "text": message.content}] if message.content else []),
                    *(
                        {"type": "input_image", "image_url": image_data_url, "detail": "low"}
                        for image_data_url in message.image_data_urls
                    ),
                ]
            output.append({"role": message.role, "content": content})
        output.extend(
            {
                "type": "function_call",
                "call_id": call.call_id,
                "name": call.name,
                "arguments": call.arguments,
            }
            for call in message.tool_calls
        )
    return output


def _responses_tool(tool: dict[str, Any]) -> dict[str, Any]:
    function = tool["function"]
    return {
        "type": "function",
        "name": function["name"],
        "description": function["description"],
        "parameters": function["parameters"],
    }


def create_model_client(settings: Settings) -> ModelClient:
    if settings.model.provider == "openai_compat":
        return AgentModelClient(settings)
    return EchoModelClient()


def create_group_model_client(settings: Settings) -> ModelClient:
    host = urlparse(settings.model.base_url).hostname or ""
    if (
        settings.social_agent_runtime.low_latency_chat
        and settings.model.provider == "openai_compat"
        and settings.model.api_mode == "responses"
        and host.endswith(".volces.com")
    ):
        # Regional Ark chat does not need hidden deep reasoning or a system proxy.
        # Keep the single-chat/model configuration intact.
        settings = settings.model_copy(deep=True)
        settings.model.thinking = "disabled"
        settings.model.max_output_tokens = settings.model.max_output_tokens or 1024
        settings.model.reuse_connections = True
        if settings.social_agent_runtime.direct_ark_connection:
            settings.model.trust_env = False
    return create_model_client(settings)
