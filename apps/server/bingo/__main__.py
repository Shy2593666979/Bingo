import uvicorn

from bingo.config import get_settings
from bingo.services.logging import configure_logging


def main() -> None:
    settings = get_settings()
    configure_logging(settings.logging)
    reload_enabled = settings.app.environment == "development"
    uvicorn.run(
        "bingo.main:create_app",
        factory=True,
        host=settings.server.host,
        port=settings.server.port,
        reload=reload_enabled,
        reload_excludes=["*.log", "*.db", "*.db-shm", "*.db-wal"]
        if reload_enabled
        else None,
        access_log=False,
        log_config=None,
    )


if __name__ == "__main__":
    main()
