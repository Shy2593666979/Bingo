"""Run validity, cancellation, execution and terminal state transitions."""

import asyncio
import json

from sqlmodel import select, update

from bingo.db.models.groups import (
    ChatGroup,
    GroupMessage,
    GroupRun,
)

from .shared import (
    TERMINAL,
    StaleRun,
    event,
    message_json,
)


class GroupRunCoordinator:
    def __init__(self, service):
        self.service = service

    async def guard(self, session, run):
        owner = (
            await session.exec(
                update(ChatGroup)
                .where(
                    ChatGroup.id == run.group_id,
                    ChatGroup.active_run_version == run.version,
                    ChatGroup.archived.is_(False),
                )
                .values(active_run_version=run.version)
                .returning(ChatGroup.owner_id)
            )
        ).first()
        if owner is None or run.status in TERMINAL:
            raise StaleRun()

    async def cancel_in_session(self, session, group_id, advance=True):
        # Invalidation, partial states and events share the archive/new-run transaction.
        if advance:
            await session.exec(
                update(ChatGroup)
                .where(ChatGroup.id == group_id)
                .values(active_run_version=ChatGroup.active_run_version + 1)
            )
        runs = (
            await session.exec(
                select(GroupRun).where(
                    GroupRun.group_id == group_id, GroupRun.status.in_(["pending", "running"])
                )
            )
        ).all()
        for run in runs:
            partial = (
                await session.exec(
                    select(GroupMessage).where(
                        GroupMessage.run_id == run.id,
                        GroupMessage.status.in_(["pending", "streaming"]),
                    )
                )
            ).all()
            for message in partial:
                message.status = "interrupted"
                await event(session, run, "message_end", message=message_json(message))
            run.status = "cancelled"
            await event(session, run, "run_cancelled")
        return runs

    async def cancel_tasks(self, group_id):
        async with self.service.database.session_factory() as session:
            ids = (
                await session.exec(select(GroupRun.id).where(GroupRun.group_id == group_id))
            ).all()
        for id in ids:
            task = self.service.tasks.get(id)
            if task:
                task.cancel()

    async def check_run(self, run_id):
        async with self.service.database.session_factory() as session:
            run = await session.get(GroupRun, run_id)
            group = await session.get(ChatGroup, run.group_id) if run else None
            if (
                not run
                or not group
                or group.archived
                or group.active_run_version != run.version
                or run.status in TERMINAL
            ):
                raise StaleRun()

    async def finish(self, run_id, status, error=None):
        async with self.service.database.session_factory() as session:
            run = await session.get(GroupRun, run_id)
            if not run or run.status in TERMINAL:
                return
            if status in {"completed", "failed"}:
                try:
                    await self.guard(session, run)
                except StaleRun:
                    return
            run.status, run.error = status, error
            await session.exec(
                update(GroupMessage)
                .where(GroupMessage.run_id == run_id, GroupMessage.status == "streaming")
                .values(status="interrupted")
            )
            await event(
                session,
                run,
                "run_done"
                if status == "completed"
                else "run_cancelled"
                if status == "cancelled"
                else "run_error",
                message=error,
            )
            await session.commit()

    async def execute(self, run_id):
        try:
            async with asyncio.timeout(self.service.settings.max_run_duration_seconds):
                async with self.service.database.session_factory() as session:
                    run = await session.get(GroupRun, run_id)
                    await self.guard(session, run)
                    run.status = "running"
                    group = await session.get(ChatGroup, run.group_id)
                    group_id, allow_followup = group.id, group.allow_ai_to_ai
                    request = json.loads(run.request_json)
                    await session.commit()
                if run.runtime_mode == "independent_agents":
                    await self.service.scheduling.independent(run_id)
                    await self.finish(run_id, "completed")
                    await self.service.memory.remember(group_id)
                    return
                speakers = (
                    json.loads(run.force_targets_json)
                    or list(dict.fromkeys(request["mentions"]))
                    or await self.service.scheduling.plan(group_id)
                )
                count, last = 0, None
                for role_id in speakers[:10]:
                    if await self.service.speaking.speak(run_id, role_id):
                        count += 1
                        last = role_id
                if allow_followup and count:
                    for _ in range(2):
                        if count >= 10:
                            break
                        followups = await self.service.scheduling.plan(
                            group_id, exclude=last, followup=True
                        )
                        if not followups:
                            break
                        if await self.service.speaking.speak(run_id, followups[0]):
                            count += 1
                            last = followups[0]
                await self.finish(run_id, "completed")
                await self.service.memory.remember(group_id)
        except StaleRun:
            await self.finish(run_id, "cancelled")
        except asyncio.CancelledError:
            await self.finish(run_id, "cancelled")
        except Exception:
            await self.finish(run_id, "failed", "这轮回复没有完成，你可以继续发消息")
