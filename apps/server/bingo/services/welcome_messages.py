"""Publish welcome bubbles independently of whether a client opens the chat."""

from uuid import NAMESPACE_URL, uuid5

from sqlmodel import select

from bingo.db.models import Conversation, Message, Role
from bingo.db.models.welcome import WelcomeJob
from bingo.db.time import beijing_now
from bingo.utils.segments import split_complete_segments


def welcome_run_id(job):
    return f"welcome-segment-{job.id}"


async def interrupt_welcome_messages(session, job):
    rows = (
        await session.exec(
            select(Message).where(
                Message.conversation_id == job.conversation_id,
                Message.run_id.in_((f"welcome-{job.id}", welcome_run_id(job))),
                Message.status == "streaming",
            )
        )
    ).all()
    for message in rows:
        message.status = "interrupted"


async def publish_private_welcome(database, identifier, content, sleep):
    segments, _ = split_complete_segments(content, final=True)
    if not segments:
        return
    async with database.session_factory() as session:
        job = await session.get(WelcomeJob, identifier)
        if not job or job.status != "running":
            return
        first = await session.get(Message, job.message_id)
        if not first:
            return
        # A previous release may already have delivered the whole greeting.
        if first.status == "completed" and first.run_id != welcome_run_id(job):
            return
        spoken = (
            await session.exec(
                select(Message.id)
                .where(Message.conversation_id == job.conversation_id, Message.role == "user")
                .limit(1)
            )
        ).first()
        if spoken:
            await interrupt_welcome_messages(session, job)
            await session.commit()
            return
        ids = [job.message_id] + [
            str(uuid5(NAMESPACE_URL, f"bingo-welcome:{identifier}:{index}"))
            for index in range(1, len(segments))
        ]
        for message_id in ids:
            message = await session.get(Message, message_id)
            if message is None:
                message = Message(
                    id=message_id,
                    conversation_id=job.conversation_id,
                    user_id=job.user_id,
                    role="assistant",
                    content="",
                    role_id=job.role_id,
                    assistant_role=first.assistant_role,
                    status="streaming",
                )
                session.add(message)
            message.run_id = welcome_run_id(job)
            if not message.content:
                message.status = "streaming"
        await session.commit()
    for index, (message_id, segment) in enumerate(zip(ids, segments, strict=True)):
        async with database.session_factory() as session:
            message = await session.get(Message, message_id)
            if message is None or message.status == "completed":
                continue
        if index:
            await sleep(min(3.0, max(1.0, 0.6 + len(segments[index - 1]) * 0.04)))
        async with database.session_factory() as session:
            job = await session.get(WelcomeJob, identifier)
            if not job or job.status != "running":
                return
            conversation = await session.get(Conversation, job.conversation_id)
            role = await session.get(Role, job.role_id)
            spoken = (
                await session.exec(
                    select(Message.id)
                    .where(Message.conversation_id == job.conversation_id, Message.role == "user")
                    .limit(1)
                )
            ).first()
            if not conversation or not role or role.deleted or not role.enabled or spoken:
                await interrupt_welcome_messages(session, job)
                await session.commit()
                return
            message = await session.get(Message, message_id)
            if message is None:
                return
            message.content, message.status = segment, "completed"
            message.created_at = beijing_now()
            await session.commit()
