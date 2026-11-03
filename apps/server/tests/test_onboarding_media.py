"""Bundled intros must follow the current voices, not a stale prototype cache."""

import hashlib
import json
from pathlib import Path

from bingo.roles import BUILTIN_ROLES


def test_bundled_introductions_match_current_distinct_role_voices():
    root = Path(__file__).resolve().parents[3]
    assets = root / "apps/mobile/assets/onboarding"
    lines = {row["code"]: row for row in json.loads((assets / "roles.json").read_text("utf-8"))}
    sources = {
        row["code"]: row
        for row in json.loads((root / "docs/onboarding-voice-sources.json").read_text("utf-8"))
    }
    encoded = {
        row["code"]: row
        for row in json.loads((root / "docs/mobile-audio-optimization.json").read_text("utf-8"))
    }
    assert set(lines) == set(sources) == set(encoded) == {role.code for role in BUILTIN_ROLES}
    assert len({role.voice for role in BUILTIN_ROLES}) == 12
    for role in BUILTIN_ROLES:
        metadata = sources[role.code]
        assert metadata["voice_fingerprint"] == hashlib.sha256(role.voice.encode()).hexdigest(), (
            role.code
        )
        assert (
            metadata["text_sha256"]
            == hashlib.sha256(lines[role.code]["intro"].encode()).hexdigest()
        )
        assert (
            metadata["wav_sha256"]
            == hashlib.sha256((assets / f"{role.code}.wav").read_bytes()).hexdigest()
        )
        assert (
            encoded[role.code]["output_sha256"]
            == hashlib.sha256((assets / f"{role.code}.m4a").read_bytes()).hexdigest()
        )
