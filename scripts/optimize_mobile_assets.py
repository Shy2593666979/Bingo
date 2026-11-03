"""Build lossless WebP siblings; preserve PNG sources and verify every RGBA pixel.

Run from any directory with Pillow installed. Only runtime assets are selected;
the originals and unused design references remain available in the workspace.
"""
import argparse
import json
import math
from concurrent.futures import ThreadPoolExecutor
from functools import partial
from pathlib import Path

from PIL import Image, ImageChops, ImageStat

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "apps/mobile/assets"


def sources():
    yield ASSETS / "images/bingo_logo.png"
    yield from sorted((ASSETS / "avatars_square").glob("*.png"))
    yield from (p for p in sorted((ASSETS / "chat_bubbles").glob("*.png"))
                if p.name not in {"pot.png", "truck.png"})
    yield from sorted((ASSETS / "stickers").glob("*.png"))
    for name in ("home", "group_chat", "single_chat", "create_group"):
        yield ASSETS / f"reference/{name}.png"


def visible_psnr(original, result):
    scores = []
    for background in ((255, 255, 255, 255), (223, 248, 239, 255)):
        a = Image.alpha_composite(Image.new("RGBA", original.size, background), original)
        b = Image.alpha_composite(Image.new("RGBA", result.size, background), result)
        a.thumbnail((864, 864), Image.Resampling.LANCZOS)
        b.thumbnail((864, 864), Image.Resampling.LANCZOS)
        rms = ImageStat.Stat(ImageChops.difference(a.convert("RGB"), b.convert("RGB"))).rms
        mse = sum(value ** 2 for value in rms) / 3
        scores.append(99.0 if mse == 0 else 10 * math.log10(255 ** 2 / mse))
    return min(scores)


def convert(source, *, perceptual=False):
    target = source.with_suffix(".webp")
    with Image.open(source) as original:
        rgba = original.convert("RGBA")
        lossless = not perceptual or source.parent.name == "images"
        quality = 96
        while True:
            rgba.save(target, "WEBP", lossless=lossless, exact=True,
                      quality=quality, alpha_quality=100, method=6)
            with Image.open(target) as encoded:
                result = encoded.convert("RGBA")
            score = visible_psnr(rgba, result)
            if lossless or score >= 40:
                break
            if quality < 100:
                quality += 2
            else:
                lossless = True
        with Image.open(target) as result:
            assert result.size == rgba.size, source
            output = result.convert("RGBA")
            assert output.getchannel("A").tobytes() == rgba.getchannel("A").tobytes(), source
            identical = output.tobytes() == rgba.tobytes()
            if lossless:
                assert identical, source
        return {"source": source.relative_to(ROOT).as_posix(),
                "asset": target.relative_to(ROOT / "apps/mobile").as_posix(),
                "source_bytes": source.stat().st_size,
                "output_bytes": target.stat().st_size,
                "width": rgba.width, "height": rgba.height,
                "pixel_identical": identical, "alpha_identical": True,
                "quality": quality, "lossless": lossless,
                "display_psnr_db": round(score, 3)}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--perceptual", action="store_true",
                        help="High quality RGB encoding; alpha and dimensions stay exact")
    args = parser.parse_args()
    with ThreadPoolExecutor(max_workers=4) as executor:
        records = list(executor.map(partial(convert, perceptual=args.perceptual), sources()))
    report = ROOT / ("docs/mobile-asset-optimization-v2.json" if args.perceptual
                     else "docs/mobile-asset-optimization.json")
    report.write_text(json.dumps(records, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Verified {len(records)} assets; dimensions and alpha unchanged")
    print(f"Source: {sum(r['source_bytes'] for r in records) / 1048576:.2f} MiB")
    print(f"WebP:   {sum(r['output_bytes'] for r in records) / 1048576:.2f} MiB")
