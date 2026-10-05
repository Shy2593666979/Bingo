from bingo.agent.model_client import ModelMessage
from bingo.db.models import Memory, Message
from bingo.prompts import SYSTEM_PROMPT
from bingo.schemas.maps import LocationInput
from bingo.utils.time import format_current_time


def build_context(
    messages: list[Message],
    memories: list[Memory],
    *,
    username: str,
    assistant_name: str,
    personality: str,
    role: str,
    timezone: str,
    role_prompt: str = "",
    current_location: str = "",
) -> list[ModelMessage]:
    system_prompt = SYSTEM_PROMPT.format(
        assistant_name=assistant_name,
        username=username,
        personality=personality,
        role=role,
        role_prompt=role_prompt or "按照当前角色自然互动。",
        current_time=format_current_time(timezone),
        timezone=timezone,
        current_location=current_location or "暂未获取",
        user_memories=_format_memories(memories, "user"),
        role_memories=_format_memories(memories, "role"),
        relationship_memories=_format_memories(memories, "user_role"),
    )
    history = [
        ModelMessage(
            role=message.role,
            content=(
                f"{message.content}\n[上一轮回答在此处被用户中断]"
                if message.role == "assistant" and message.status == "interrupted"
                else LocationInput.model_validate(message.location).model_content(message.content)
                if message.message_type == "location" and message.location
                else message.content
            ),
        )
        for message in messages
        if message.status != "streaming" and message.message_type in {"chat", "location"}
    ]
    return [ModelMessage(role="system", content=system_prompt), *history]


def _format_memories(memories: list[Memory], scope: str) -> str:
    text = "\n".join(
        f"- [{memory.category}] {memory.content}" for memory in memories if memory.scope == scope
    )
    return text or "- 暂无"
