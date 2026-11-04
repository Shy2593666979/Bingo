"""Schedule idle-group topics without owning a separate run lifecycle."""

import asyncio
from datetime import timedelta

from sqlmodel import select

from bingo.db.models import User
from bingo.db.models.groups import (
    ChatGroup,
)
from bingo.db.time import beijing_now
from bingo.schemas.group_chat import GroupSend


class GroupProactiveTopics:
    def __init__(self, service):
        self.service = service

    async def proactive_loop(self):
        while True:
            await asyncio.sleep(60)
            now = beijing_now()
            if now.hour >= 23 or now.hour < 8:
                continue
            try:
                async with self.service.database.session_factory() as session:
                    groups = (
                        await session.exec(
                            select(ChatGroup).where(
                                ChatGroup.proactive_enabled.is_(True),
                                ChatGroup.archived.is_(False),
                                ChatGroup.muted.is_(False),
                                ChatGroup.last_activity_at < now - timedelta(hours=2),
                            )
                        )
                    ).all()
                for group in groups:
                    if group.last_proactive_at and group.last_proactive_at > now - timedelta(
                        hours=8
                    ):
                        continue
                    async with self.service.database.session_factory() as session:
                        user = await session.get(User, group.owner_id)
                        current = await session.get(ChatGroup, group.id)
                        if (
                            not user
                            or not current
                            or current.archived
                            or not current.proactive_enabled
                            or current.muted
                        ):
                            continue
                        current.last_proactive_at = now
                        await session.commit()
                    await self.service.begin(
                        group.id,
                        user,
                        GroupSend(
                            client_message_id=f"proactive-{now.isoformat()}",
                            content="自然接住大家之前的交流，选择贴近生活的话题；没有新内容就保持安静。",
                        ),
                        system=True,
                    )
            except Exception:
                continue
