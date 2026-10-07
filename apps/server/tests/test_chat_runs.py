import asyncio
from collections.abc import AsyncIterator
from pathlib import Path

import pytest

from bingo.agent.model_client import ModelMessage, ModelStreamEvent, ModelTextDelta
from bingo.agent.runtime import AgentRuntime
from bingo.db.models import User
from bingo.db.repositories import ConversationRepository
from bingo.db.session import Database
from bingo.services.chat_runs import ChatRunService
from bingo.tools.registry import ToolRegistry


class DisconnectableModel:
    def __init__(self) -> None:
        self.first_part_sent = asyncio.Event()
        self.finish = asyncio.Event()

    async def complete(self, messages: list[ModelMessage]) -> str:
        return "unused"

    async def stream(
        self,
        messages: list[ModelMessage],
        tools: list[dict] | None = None,
    ) -> AsyncIterator[ModelStreamEvent]:
        yield ModelTextDelta("第一句。\n")
        self.first_part_sent.set()
        await self.finish.wait()
        yield ModelTextDelta("第二句。")


@pytest.mark.asyncio
async def test_chat_run_continues_after_stream_subscriber_disconnects(tmp_path: Path) -> None:
    database = Database(f"sqlite+aiosqlite:///{tmp_path / 'background-run.db'}")
    await database.initialize()
    model = DisconnectableModel()
    runtime = AgentRuntime(
        model,
        ToolRegistry(),
        assistant_name="Bingo",
        persona="可靠",
        timezone="Asia/Shanghai",
    )
    service = ChatRunService(database.session_factory, runtime)
    async with database.session_factory() as session:
        user = User(
            phone="13800138088",
            password_hash="hash",
            username="测试用户",
            assistant_name="Bingo",
            personality="温柔体贴",
            role="同事",
            onboarding_complete=True,
        )
        session.add(user)
        await session.commit()
        await session.refresh(user)
        user_id = user.id

    try:
        subscription = await service.subscribe(
            user_id=user_id,
            run_id="background-run",
            supersedes_run_id=None,
            content="请回复两句话",
            conversation_id=None,
        )
        events = subscription.events().__aiter__()
        start = await asyncio.wait_for(anext(events), timeout=2)
        first_segment = await asyncio.wait_for(anext(events), timeout=2)
        assert start["type"] == "start"
        assert first_segment == {"type": "segment", "content": "第一句。"}

        await subscription.close()
        model.finish.set()

        async def completed_messages():
            for _ in range(40):
                async with database.session_factory() as session:
                    messages = await ConversationRepository(session, user_id).list_messages(
                        start["conversation_id"]
                    )
                if any(message.role == "assistant" for message in messages):
                    return messages
                await asyncio.sleep(0.05)
            raise AssertionError("background chat run did not finish")

        messages = await completed_messages()
        assert [(message.role, message.content) for message in messages] == [
            ("user", "请回复两句话"),
            ("assistant", "第一句。\n第二句。"),
        ]
    finally:
        await service.close()
        await database.dispose()
