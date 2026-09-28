from datetime import datetime

from pydantic import BaseModel


class ProactiveMessageResponse(BaseModel):
    id: str
    conversation_id: str
    message_id: str
    content: str
    stage: int
    created_at: datetime
    assistant_role: str | None = None


class RecommendationsResponse(BaseModel):
    items: list[str]
