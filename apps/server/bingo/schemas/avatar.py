import base64
import binascii
import struct


def validate_avatar(value: str | None) -> str | None:
    if value is None:
        return None
    try:
        image = base64.b64decode(value, validate=True)
        if image[:8] != b"\x89PNG\r\n\x1a\n" or len(image) < 24:
            raise ValueError("头像格式无效")
        width, height = struct.unpack(">II", image[16:24])
        if not 1 <= width <= 1024 or not 1 <= height <= 1024:
            raise ValueError("头像尺寸过大")
    except (ValueError, binascii.Error) as error:
        raise ValueError("请上传有效的裁剪头像") from error
    return value
