"""Independent participation decisions; scheduling and publishing remain server owned."""

import asyncio
import json
from dataclasses import dataclass, field

from pydantic import AliasChoices, BaseModel, Field, ValidationError

from bingo.agent.model_client import ModelMessage


class ReplyIntent(BaseModel):
    action: str = "silent"
    mention_all: bool = Field(
        default=False, validation_alias=AliasChoices("mention_all", "mentionAll")
    )
    reply_to_message_id: str | None = Field(
        default=None, validation_alias=AliasChoices("reply_to_message_id", "replyToMessageId")
    )
    mention_targets: list[dict] = Field(
        default_factory=list,
        max_length=9,
        validation_alias=AliasChoices("mention_targets", "mentionTargets", "mentions"),
    )
    desired_delay_ms: int = Field(
        default=0,
        ge=0,
        le=3000,
        validation_alias=AliasChoices("desired_delay_ms", "desiredDelayMs"),
    )


def parse_intent(raw):
    if not isinstance(raw, str) or len(raw) > 12000:
        return None
    decoder = json.JSONDecoder()
    for index, char in enumerate(raw):
        if char != "{":
            continue
        try:
            value, _ = decoder.raw_decode(raw[index:])
            intent = ReplyIntent.model_validate(value)
            if intent.action not in {"speak", "silent"}:
                return None
            return intent
        except (ValueError, TypeError, ValidationError):
            continue
    return None


@dataclass
class GroupScheduler:
    """A bounded activity ledger, never a writer of character opinions."""

    assessed: set = field(default_factory=set)
    published: list = field(default_factory=list)

    def first_assessment(self, message_id, role_id):
        key = (message_id, role_id)
        if key in self.assessed:
            return False
        self.assessed.add(key)
        return True


class ReplyHeader:
    """Read optional reply metadata and body from one provider stream.

    Plain text is accepted for older providers. JSON metadata never reaches the UI.
    """

    def __init__(self):
        self.buffer = ""
        self.ready = False
        self.intent = None

    def feed(self, text):
        if self.ready:
            return text
        self.buffer += text
        raw = self.buffer.lstrip()
        if not raw:
            return ""
        if raw.startswith("`"):
            if "\n" not in raw:
                if len(raw) > 20:
                    raise ValueError("Invalid reply header")
                return ""
            raw = raw.split("\n", 1)[1].lstrip()
        if not raw:
            return ""
        if raw[0] != "{":
            self.ready = True
            self.buffer = ""
            return raw
        try:
            value, end = json.JSONDecoder().raw_decode(raw)
        except ValueError:
            if len(raw) > 2048:
                raise ValueError("Reply header too long") from None
            return ""
        try:
            self.intent = ReplyIntent.model_validate(value).model_copy(
                update={"action": "speak", "desired_delay_ms": 0}
            )
        except (ValueError, TypeError):
            self.intent = ReplyIntent(action="speak")
        body = raw[end:].lstrip()
        if body.startswith("`"):
            if body in {"`", "``"}:
                return ""
            body = body.removeprefix("```").lstrip()
        if not body:
            return ""
        self.ready = True
        self.buffer = ""
        return body


class SocialAgentRuntime:
    def __init__(self, *, settings, complete, claim_decision, context_for_run, validate_intent):
        self.settings = settings
        self.complete = complete
        self.claim_decision = claim_decision
        self.context_for_run = context_for_run
        self.validate_intent = validate_intent
        self.semaphore = asyncio.Semaphore(settings.decision_concurrency)

    async def decide(self, run_id, role_id, required=False, trigger_id=None):
        async with self.semaphore:
            if not await self.claim_decision(run_id):
                return ReplyIntent(action="speak") if required else None
            context = await self.context_for_run(run_id, role_id)
            if context is None:
                return None
            _, messages = context
            policy = (
                "你正在为你自己决定是否参与当前群聊。只输出一个JSON对象，不写正文。"
                '格式：{"action":"speak或silent","replyToMessageId":null,'
                '"mentionTargets":[{"type":"role或user","id":"上下文中的真实ID"}],"desiredDelayMs":0}。'
                '也可增加"mentionAll":true并在正文使用@全部搭子或@全体搭子，目标为除自己外的所有AI搭子。'
                "普通消息可沉默，不机械附和；仅引用同群已完成且提供了ID的消息。引用与@分开决定。"
                "需要直接询问真人时可以@该真人，必须使用提供的user ID；不要代替真人回答。"
            )
            if required:
                policy += (
                    "真人明确@了你，这是强回应请求，action必须为speak；你只决定可选引用和提及。"
                )
            if trigger_id:
                policy += f"本次触发消息的messageId是{trigger_id}，请优先考虑是否需要回应这条消息。"
            try:
                async with asyncio.timeout(self.settings.decision_timeout_seconds):
                    raw = await self.complete(
                        [*messages, ModelMessage(role="system", content=policy)]
                    )
                intent = parse_intent(raw)
                if required and (intent is None or intent.action == "silent"):
                    return ReplyIntent(action="speak")
                if intent is None or intent.action == "silent":
                    return None
                return await self.validate_intent(run_id, role_id, intent)
            except asyncio.CancelledError:
                raise
            except Exception:
                # Bad optional metadata must not suppress an explicitly requested response.
                return ReplyIntent(action="speak") if required else None
