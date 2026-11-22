"""Bounded thumbnail encoding cache; authorization remains in the caller."""

from functools import lru_cache
from io import BytesIO

from PIL import Image, ImageOps


@lru_cache(maxsize=32)
def avatar_thumbnail(data: bytes, size: int) -> bytes:
    if not 64 <= size <= 512:
        raise ValueError("Invalid thumbnail size")
    with Image.open(BytesIO(data)) as source:
        if source.width * source.height > 16_777_216:
            raise ValueError("Avatar dimensions exceed thumbnail processing limit")
        image = ImageOps.exif_transpose(source).convert("RGBA")
        image.thumbnail((size, size), Image.Resampling.LANCZOS)
        output = BytesIO()
        image.save(output, format="WEBP", quality=82, method=4)
        return output.getvalue()
