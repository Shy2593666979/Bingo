"""Extract deduplicated long-term facts from completed group messages."""

import asyncio
import json

from sqlmodel import select

from bingo.agent.model_client import ModelMessage
from bingo.db.models.groups import (
    ChatGroup,
    GroupMemory,
    GroupMessage,
)


class GroupMemoryExtractor:
    def __init__(self, service):
        self.service = service

    async def remember(self, group_id):
        try:
            async with self.service.database.session_factory() as session:
                history = (
                    await session.exec(
                        select(GroupMessage)
                        .where(
                            GroupMessage.group_id == group_id, GroupMessage.status == "completed"
                        )
                        .order_by(GroupMessage.seq.desc())
                        .limit(20)
                    )
                ).all()
            if not history:
                return
            async with asyncio.timeout(15):
                raw = await self.service.model.complete(
                    [
                        ModelMessage(
                            role="system",
                            content="只从群聊公开记录中提取最多3条值得长期记住的明确事实。不得猜测。只输出JSON字符串数组，没有则输出[]。",
                        ),
                        ModelMessage(
                            role="user",
                            content="\n".join(
                                f"{m.sender_name}: {m.content}" for m in reversed(history)
                            ),
                        ),
                    ]
                )
            facts = json.loads(raw[raw.find("[") : raw.rfind("]") + 1])
            if not isinstance(facts, list):
                return
            async with self.service.database.session_factory() as session:
                if (
                    await session.get(ChatGroup, group_id) is None
                    or await session.get(GroupMessage, history[0].id) is None
                ):
                    return
                for fact in facts[:3]:
                    if not isinstance(fact, str) or not fact.strip():
                        continue
                    fact = fact.strip()[:300]
                    old = (
                        await session.exec(
                            select(GroupMemory.id).where(
                                GroupMemory.group_id == group_id, GroupMemory.content == fact
                            )
                        )
                    ).first()
                    if not old:
                        session.add(
                            GroupMemory(
                                group_id=group_id, content=fact, source_message_id=history[0].id
                            )
                        )
                await session.commit()
        except Exception:
            return
