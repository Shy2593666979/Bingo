from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Any

from sqlmodel.ext.asyncio.session import AsyncSession

from bingo.db.models import User


@dataclass(frozen=True, slots=True)
class ToolContext:
    session: AsyncSession
    user: User
    timezone: str
    conversation_id: str | None = None


@dataclass(frozen=True, slots=True)
class ToolResult:
    content: str
    client_event: dict[str, Any] | None = None


class BaseTool(ABC):
    name: str
    description: str
    parameters: dict[str, Any]

    @abstractmethod
    async def run(self, context: ToolContext, **arguments: Any) -> ToolResult:
        """Execute the tool and return model-readable output."""

    def definition(self) -> dict[str, Any]:
        return {
            "type": "function",
            "function": {
                "name": self.name,
                "description": self.description,
                "parameters": self.parameters,
            },
        }
