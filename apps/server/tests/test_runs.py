import asyncio
from collections.abc import AsyncIterator
from pathlib import Path

import pytest

from bingo.agent.model_client import ModelMessage, ModelStreamEvent, ModelTextDelta
from bingo.agent.runtime import AgentRuntime
from bingo.db.models import User
from bingo.db.repositories import ConversationRepository
from bingo.db.session import Database
from bingo.tools.registry import ToolRegistry


class InterruptibleModel:
    def __init__(self) -> None:
        self.first_segment_sent = asyncio.Event()
        self.second_context: list[ModelMessage] = []
        self._calls = 0

    async def complete(self, messages: list[ModelMessage]) -> str:
        return "unused"

    async def stream(
        self,
        messages: list[ModelMessage],
        tools: list[dict] | None = None,
    ) -> AsyncIterator[ModelStreamEvent]:
        self._calls += 1
        if self._calls == 1:
            yield ModelTextDelta("已经说出第一句。")
            self.first_segment_sent.set()
            await asyncio.Event().wait()
            return
        self.second_context = messages
        yield ModelTextDelta("结合补充后的完整回答。")


@pytest.mark.asyncio
async def test_new_run_interrupts_and_preserves_partial_reply(tmp_path: Path) -> None:
    database = Database(f"sqlite+aiosqlite:///{tmp_path / 'runs.db'}")
    await database.initialize()
    model = InterruptibleModel()
    runtime = AgentRuntime(
        model,
        ToolRegistry(),
        assistant_name="Bingo",
        persona="可靠",
        timezone="Asia/Shanghai",
    )
    async with database.session_factory() as setup_session:
        user = User(
            phone="13800138088",
            password_hash="hash",
            username="测试用户",
            assistant_name="Bingo",
            personality="温柔体贴",
            role="同事",
            onboarding_complete=True,
        )
        setup_session.add(user)
        await setup_session.commit()
        await setup_session.refresh(user)

    async def collect(run_id: str, content: str, supersedes: str | None = None):
        handle = await runtime.begin_run(user.id, run_id, supersedes)
        async with database.session_factory() as session:
            return [
                event
                async for event in runtime.stream_segments(
                    session,
                    user,
                    content,
                    run_handle=handle,
                )
            ]

    try:
        first_task = asyncio.create_task(collect("run-a", "第一个问题"))
        await asyncio.wait_for(model.first_segment_sent.wait(), timeout=2)
        second_task = asyncio.create_task(collect("run-b", "补充问题", "run-a"))
        first_events, second_events = await asyncio.wait_for(
            asyncio.gather(first_task, second_task),
            timeout=3,
        )

        assert [event["type"] for event in first_events] == [
            "start",
            "segment",
            "interrupted",
        ]
        assert second_events[-1]["type"] == "done"

        async with database.session_factory() as session:
            messages = await ConversationRepository(session, user.id).list_messages(
                second_events[0]["conversation_id"]
            )
        assert [(message.role, message.status) for message in messages] == [
            ("user", "completed"),
            ("assistant", "interrupted"),
            ("user", "completed"),
            ("assistant", "completed"),
        ]
        context = "\n".join(message.content for message in model.second_context)
        assert "第一个问题" in context
        assert "已经说出第一句。\n[上一轮回答在此处被用户中断]" in context
        assert "补充问题" in context
    finally:
        await database.dispose()
