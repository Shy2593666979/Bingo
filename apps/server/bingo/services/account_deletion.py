import asyncio
from uuid import UUID

from sqlalchemy import delete, update
from sqlmodel import select
from sqlmodel.ext.asyncio.session import AsyncSession

from bingo.db.models import (
    AuthSession,
    CallInvitation,
    Conversation,
    DeviceAction,
    Memory,
    MemoryCheckpoint,
    Message,
    MorningGreeting,
    ProactiveMessage,
    PushDevice,
    PushOutbox,
    Role,
    RolePreference,
    User,
    UserCompanion,
    VoiceJob,
)
from bingo.db.models.stickers import UserSticker
from bingo.db.models.welcome import WelcomeJob
from bingo.services.chat import IMAGE_DIRECTORY
from bingo.services.community import delete_user_community_data
from bingo.services.context import ServiceContext
from bingo.services.group_chat import delete_user_groups
from bingo.services.stickers import file_path as sticker_file_path


async def delete_account(user: User, session: AsyncSession, context: ServiceContext) -> None:
    user_id = user.id
    conversation_ids = list(
        (await session.exec(select(Conversation.id).where(Conversation.user_id == user_id))).all()
    )
    jobs = list((await session.exec(select(VoiceJob).where(VoiceJob.user_id == user_id))).all())
    job_ids = [job.id for job in jobs]
    await session.rollback()
    await context.chat_runs.cancel_user(user_id)
    if context.companion_welcome is not None:
        await context.companion_welcome.cancel_user(user_id)
    if context.group_chat is not None:
        await context.group_chat.cancel_user(user_id)
    if context.chat_speech is not None:
        for owner, run_id in list(context.chat_speech.tasks):
            if owner == user_id:
                await context.chat_speech.stop(owner, run_id)
    await context.voice_cloning.cancel_jobs(job_ids)
    conversation_ids = list(
        (await session.exec(select(Conversation.id).where(Conversation.user_id == user_id))).all()
    )
    if context.engagement is not None:
        await context.engagement.forget_user(user_id, conversation_ids)
    if context.location is not None:
        await context.location.clear(user_id)

    roles = list((await session.exec(select(Role).where(Role.owner_id == user_id))).all())
    role_ids = [role.id for role in roles]
    images = list(
        (
            await session.exec(
                select(Message.image_id).where(
                    Message.conversation_id.in_(conversation_ids), Message.image_id.is_not(None)
                )
            )
        ).all()
    )
    stickers = list(
        (await session.exec(select(UserSticker.id).where(UserSticker.user_id == user_id))).all()
    )
    await session.exec(delete(UserSticker).where(UserSticker.user_id == user_id))
    jobs = list((await session.exec(select(VoiceJob).where(VoiceJob.user_id == user_id))).all())
    voices = {role.owned_voice for role in roles if role.owned_voice}
    voices.update(job.voice for job in jobs if job.kind in {"clone", "delete"} and job.voice)
    prefixes = {
        "u" + job.id.replace("-", "")[:9]
        for job in jobs
        if job.kind == "clone" and job.status != "ready"
    }
    prefixes.update(job.voice for job in jobs if job.kind == "delete_prefix" and job.voice)
    preview_tasks = [
        context.voice_cloning.preview_tasks[voice]
        for voice in voices
        if voice in context.voice_cloning.preview_tasks
    ]
    for task in preview_tasks:
        task.cancel()
    await asyncio.gather(*preview_tasks, return_exceptions=True)
    cleanups = [
        VoiceJob(user_id="deleted", role_id="deleted", kind=kind, voice=value)
        for kind, values in (("delete", voices), ("delete_prefix", prefixes))
        for value in values
    ]
    for voice in voices:
        context.voice_cloning.preview_cache.pop(voice, None)
    for cleanup in cleanups:
        session.add(cleanup)
    for model in (
        PushOutbox,
        PushDevice,
        MorningGreeting,
        CallInvitation,
        ProactiveMessage,
        MemoryCheckpoint,
        Memory,
        DeviceAction,
        AuthSession,
        RolePreference,
        UserCompanion,
        VoiceJob,
        WelcomeJob,
    ):
        await session.exec(delete(model).where(model.user_id == user_id))
    await delete_user_community_data(session, user_id)
    await delete_user_groups(session, user_id)
    await session.exec(delete(Message).where(Message.conversation_id.in_(conversation_ids)))
    await session.exec(delete(Conversation).where(Conversation.user_id == user_id))
    await session.exec(delete(User).where(User.id == user_id))
    await session.exec(
        update(Role)
        .where(Role.voice_source_id.in_(role_ids))
        .values(voice="", voice_source_id=None)
    )
    await session.exec(delete(RolePreference).where(RolePreference.role_id.in_(role_ids)))
    await session.exec(delete(Role).where(Role.owner_id == user_id))
    await session.commit()
    for identifier in stickers:
        try:
            sticker_file_path(identifier).unlink(missing_ok=True)
        except OSError:
            pass
    for image_id in images:
        try:
            identifier = str(UUID(image_id))
            (IMAGE_DIRECTORY / f"{identifier}.jpg").unlink(missing_ok=True)
        except (ValueError, OSError):
            pass
    for cleanup in cleanups:
        context.voice_cloning.schedule(cleanup.id)
