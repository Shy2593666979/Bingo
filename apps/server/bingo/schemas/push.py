from pydantic import BaseModel, Field


class PushDeviceRegistration(BaseModel):
    installation_id: str = Field(min_length=8, max_length=100)
    provider: str = Field(pattern="^(getui)$")
    client_id: str = Field(min_length=8, max_length=255)
    manufacturer: str | None = Field(default=None, max_length=80)
    model: str | None = Field(default=None, max_length=120)
    app_version: str | None = Field(default=None, max_length=40)
    role_avatar_notifications: bool = False


class PushDeviceResponse(BaseModel):
    id: str
    installation_id: str
    provider: str
    manufacturer: str | None
    model: str | None
    active: bool
