from datetime import datetime

from pydantic import BaseModel


class CallInvitationResponse(BaseModel):
    id: str
    conversation_id: str
    caller_name: str
    caller_role: str | None
    reason: str
    initiator: str
    status: str
    expires_at: datetime
    created_at: datetime
