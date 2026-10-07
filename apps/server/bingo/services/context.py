from dataclasses import dataclass, field
from typing import Any

from bingo.config import Settings


@dataclass
class ServiceContext:
    settings: Settings
    database: Any
    runtime: Any
    chat_runs: Any
    voice_cloning: Any
    engagement: Any
    location: Any = None
    maps: Any = None
    chat_speech: Any = None
    public_base_url: str = ""
    client_address: str = "unknown"
    password_reset_attempts: dict = field(default_factory=dict)


@dataclass
class BinaryAsset:
    data: bytes
    media_type: str
    headers: dict[str, str] = field(default_factory=dict)
