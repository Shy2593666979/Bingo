import ast
from pathlib import Path


def test_api_does_not_query_database_and_business_services_do_not_import_api():
    root = Path(__file__).parents[1] / "bingo"
    for path in (root / "api").rglob("*.py"):
        source = path.read_text(encoding="utf-8")
        assert "bingo.db.repositories" not in source, path
        assert "session.exec(" not in source, path
        assert "session.commit(" not in source, path
        assert "session.get(" not in source, path
        assert "session.add(" not in source, path
        assert "session.delete(" not in source, path
        if path.name != "dependencies.py":
            assert "session_factory(" not in source, path
    transport_adapters = {"asr.py", "realtime_call.py"}
    for path in (root / "services").rglob("*.py"):
        if path.relative_to(root / "services").as_posix() in transport_adapters:
            continue
        for node in ast.walk(ast.parse(path.read_text(encoding="utf-8"))):
            if isinstance(node, ast.ImportFrom):
                assert not (node.module or "").startswith(("bingo.api", "fastapi")), path
