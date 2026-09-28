from pathlib import Path

from bingo.config import get_settings


def test_loads_nested_yaml_configuration(tmp_path: Path) -> None:
    config_path = tmp_path / "config.yaml"
    config_path.write_text(
        """
app:
  environment: test
model:
  provider: openai_compat
  api_key: test-key
  model: test-model
vision:
  model: test-vision-model
asr:
  realtime:
    model: test-streaming-model
redis:
  url: redis://localhost:6379/4
logging:
  level: DEBUG
  directory: ./custom-logs
  retention_days: 7
""".strip(),
        encoding="utf-8",
    )

    settings = get_settings(config_path)

    assert settings.app.environment == "test"
    assert settings.model.model == "test-model"
    assert settings.vision.model == "test-vision-model"
    assert settings.asr.realtime.model == "test-streaming-model"
    assert settings.redis.url == "redis://localhost:6379/4"
    assert settings.logging.level == "DEBUG"
    assert settings.logging.directory == "./custom-logs"
    assert settings.logging.retention_days == 7
