"""Encode local introductions as AAC-LC; retain WAV masters outside the APK."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import wave

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
DIRECTORY = ROOT / "apps/mobile/assets/onboarding"


def encode(ffmpeg, source):
    target = source.with_suffix(".m4a")
    subprocess.run([ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-i", str(source),
                    "-map_metadata", "-1", "-c:a", "aac", "-b:a", "96k", "-ar", "24000",
                    "-ac", "1", "-movflags", "+faststart", str(target)], check=True)
    with wave.open(str(source), "rb") as audio:
        assert audio.getnchannels() == 1 and audio.getframerate() == 24000
        original = np.frombuffer(audio.readframes(audio.getnframes()), dtype="<i2").astype(float)
    decoded = subprocess.run([ffmpeg, "-hide_banner", "-loglevel", "error", "-i", str(target),
                              "-f", "s16le", "-acodec", "pcm_s16le", "-"],
                             capture_output=True, check=True).stdout
    samples = np.frombuffer(decoded, dtype="<i2").astype(float)
    assert abs(len(samples) - len(original)) <= 1024, source
    length = min(len(samples), len(original))
    a, b = original[:length], samples[:length]
    correlation = float(np.corrcoef(a, b)[0, 1])
    assert correlation >= .98, (source, correlation)
    return {"code": source.stem, "duration_seconds": round(len(original) / 24000, 3),
            "source_bytes": source.stat().st_size, "output_bytes": target.stat().st_size,
            "output_sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
            "pcm_correlation": round(correlation, 6), "sample_rate": 24000,
            "channels": 1, "codec": "AAC-LC", "bitrate": 96000}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--ffmpeg", required=True)
    args = parser.parse_args()
    records = [encode(args.ffmpeg, source) for source in sorted(DIRECTORY.glob("*.wav"))]
    introductions = json.loads((DIRECTORY / "roles.json").read_text(encoding="utf-8"))
    assert {row["code"] for row in records} == {row["code"] for row in introductions}
    (ROOT / "docs/mobile-audio-optimization.json").write_text(
        json.dumps(records, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Verified {len(records)} introductions")
    print(f"WAV: {sum(r['source_bytes'] for r in records) / 1048576:.2f} MiB")
    print(f"AAC: {sum(r['output_bytes'] for r in records) / 1048576:.2f} MiB")
