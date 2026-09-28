import os
from functools import lru_cache
from pathlib import Path
from typing import Literal

import yaml
from pydantic import BaseModel, Field

CONFIG_DIRECTORY = Path(__file__).resolve().parents[1] / "config"
DEFAULT_CONFIG_PATH = CONFIG_DIRECTORY / "config.yaml"
EXAMPLE_CONFIG_PATH = CONFIG_DIRECTORY / "config.example.yaml"


class AppSettings(BaseModel):
    name: str = "Bingo"
    environment: Literal["development", "test", "production"] = "development"
    timezone: Literal["Asia/Shanghai"] = "Asia/Shanghai"


class ServerSettings(BaseModel):
    host: str = "0.0.0.0"
    port: int = 8000
    api_prefix: str = "/api/v1"
    cors_origins: list[str] = Field(default_factory=lambda: ["*"])


class DatabaseSettings(BaseModel):
    url: str = "sqlite+aiosqlite:///./data/bingo.db"


class AgentSettings(BaseModel):
    assistant_name: str = "Bingo"
    assistant_persona: str = "简洁、可靠、主动，但不替用户编造事实或声称完成未执行的操作。"


class ModelSettings(BaseModel):
    provider: Literal["echo", "openai_compat"] = "echo"
    api_mode: Literal["responses", "chat_completions"] = "chat_completions"
    base_url: str = "https://api.openai.com/v1"
    api_key: str = ""
    model: str = "gpt-4.1-mini"
    timeout_seconds: float = 60.0


class VisionSettings(BaseModel):
    """Optional image model overrides; blank model means use the main model."""

    model: str = ""
    api_mode: Literal["responses", "chat_completions"] | None = None
    base_url: str = ""
    api_key: str = ""
    timeout_seconds: float | None = None
    enable_thinking: bool = False


class FileAsrSettings(BaseModel):
    base_url: str = (
        "https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation"
    )
    model: str = "qwen3-asr-flash"
    language: str = "zh"
    timeout_seconds: float = 60.0


class RealtimeAsrSettings(BaseModel):
    url: str = "wss://llm-82csv4ok6e6xu5cp.cn-beijing.maas.aliyuncs.com/api-ws/v1/inference"
    model: str = "qwen-audio-3.0-asr-flash-streaming"
    format: Literal["pcm"] = "pcm"
    sample_rate: Literal[8000, 16000] = 16000
    timeout_seconds: float = 10.0


class AsrSettings(BaseModel):
    api_key: str = ""
    file: FileAsrSettings = Field(default_factory=FileAsrSettings)
    realtime: RealtimeAsrSettings = Field(default_factory=RealtimeAsrSettings)


class RealtimeCallSettings(BaseModel):
    api_key: str = ""
    url: str = ""
    model: str = "qwen-audio-3.1-realtime-plus"
    voice: str = "longanqian_v3.1"
    turn_detection: Literal["server_vad", "smart_turn"] = "smart_turn"
    max_history_turns: int = Field(default=20, ge=1, le=50)
    timeout_seconds: float = 15.0


class RedisSettings(BaseModel):
    url: str | None = None


class EngagementSettings(BaseModel):
    worker_poll_seconds: float = 2.0
    follow_up_delays_seconds: tuple[int, int, int] = (3600, 10800, 36000)
    recommendation_delay_seconds: int = 18000


class GetuiSettings(BaseModel):
    base_url: str = "https://restapi.getui.com"
    app_id: str = ""
    app_key: str = ""
    master_secret: str = ""


class AndroidPushSettings(BaseModel):
    channel_id: str = "bingo_companion"
    channel_name: str = "Bingo 陪伴消息"


class PushSettings(BaseModel):
    provider: Literal["disabled", "getui"] = "disabled"
    worker_poll_seconds: float = 2.0
    android: AndroidPushSettings = Field(default_factory=AndroidPushSettings)
    getui: GetuiSettings = Field(default_factory=GetuiSettings)


class LoggingSettings(BaseModel):
    level: Literal["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"] = "INFO"
    console: bool = True
    directory: str = "./logs"
    application_file: str | None = "bingo.log"
    access_file: str | None = "access.log"
    rotation: Literal["daily"] = "daily"
    retention_days: int = Field(default=14, ge=1)


class Settings(BaseModel):
    app: AppSettings = Field(default_factory=AppSettings)
    server: ServerSettings = Field(default_factory=ServerSettings)
    database: DatabaseSettings = Field(default_factory=DatabaseSettings)
    agent: AgentSettings = Field(default_factory=AgentSettings)
    model: ModelSettings = Field(default_factory=ModelSettings)
    vision: VisionSettings = Field(default_factory=VisionSettings)
    asr: AsrSettings = Field(default_factory=AsrSettings)
    realtime_call: RealtimeCallSettings = Field(default_factory=RealtimeCallSettings)
    redis: RedisSettings = Field(default_factory=RedisSettings)
    engagement: EngagementSettings = Field(default_factory=EngagementSettings)
    push: PushSettings = Field(default_factory=PushSettings)
    logging: LoggingSettings = Field(default_factory=LoggingSettings)


@lru_cache
def get_settings(config_path: str | Path | None = None) -> Settings:
    configured_path = config_path or os.getenv("BINGO_CONFIG_FILE")
    path = Path(configured_path or DEFAULT_CONFIG_PATH).resolve()
    if configured_path is None and not path.is_file():
        path = EXAMPLE_CONFIG_PATH
    if not path.is_file():
        raise FileNotFoundError(
            f"Configuration file not found: {path}. Copy config.example.yaml to config.yaml."
        )
    with path.open(encoding="utf-8") as stream:
        values = yaml.safe_load(stream) or {}
    if not isinstance(values, dict):
        raise ValueError(f"Configuration root must be a mapping: {path}")
    return Settings.model_validate(values)
