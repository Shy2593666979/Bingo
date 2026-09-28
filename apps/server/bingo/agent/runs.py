import asyncio
from dataclasses import dataclass, field


@dataclass(slots=True)
class AgentRunHandle:
    run_id: str
    user_id: str
    predecessor: "AgentRunHandle | None" = None
    cancelled: asyncio.Event = field(default_factory=asyncio.Event)
    finished: asyncio.Event = field(default_factory=asyncio.Event)

    async def wait_for_turn(self) -> None:
        if self.predecessor is not None:
            await self.predecessor.finished.wait()


class AgentRunCoordinator:
    def __init__(self) -> None:
        self._lock = asyncio.Lock()
        self._active: dict[str, AgentRunHandle] = {}
        self._cancelled_run_ids: set[str] = set()

    async def begin(
        self,
        user_id: str,
        run_id: str,
        supersedes_run_id: str | None,
    ) -> AgentRunHandle:
        async with self._lock:
            predecessor = self._active.get(user_id)
            if supersedes_run_id is not None:
                self._cancelled_run_ids.add(supersedes_run_id)
            was_preempted = run_id in self._cancelled_run_ids
            if (
                predecessor is not None
                and predecessor.run_id != run_id
                and (supersedes_run_id is None or predecessor.run_id == supersedes_run_id)
            ):
                predecessor.cancelled.set()
            handle = AgentRunHandle(
                run_id,
                user_id,
                predecessor=None if was_preempted else predecessor,
            )
            if was_preempted:
                handle.cancelled.set()
            else:
                self._active[user_id] = handle
            return handle

    async def finish(self, handle: AgentRunHandle) -> None:
        handle.finished.set()
        async with self._lock:
            self._cancelled_run_ids.discard(handle.run_id)
            if self._active.get(handle.user_id) is handle:
                self._active.pop(handle.user_id, None)
