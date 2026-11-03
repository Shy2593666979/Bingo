import base64
import binascii
import hashlib
import struct
from pathlib import Path
from uuid import UUID

from sqlalchemy.exc import IntegrityError
from sqlmodel import select

from bingo.db.models.stickers import UserSticker
from bingo.schemas.stickers import StickerUpload
from bingo.services.exceptions import ServiceError
from bingo.utils.stickers.catalog import CATALOG
from bingo.utils.stickers.content import PREFIX, encode_sticker, parse_sticker

DIRECTORY = Path(__file__).resolve().parents[2] / "data" / "stickers"


def file_path(identifier):
    return DIRECTORY / (str(UUID(identifier)) + ".image")


async def normalize_sticker(session, user_id, content):
    if not content.startswith(PREFIX):
        return content
    value = parse_sticker(content)
    if not value:
        raise ServiceError(422, "表情消息格式无效")
    if value["id"] in CATALOG:
        return encode_sticker(CATALOG[value["id"]])
    if not value["id"].startswith("custom_"):
        raise ServiceError(422, "表情不存在")
    row = await session.get(UserSticker, value["id"][7:])
    if not row or row.user_id != user_id or row.deleted:
        raise ServiceError(404, "表情不存在或已移除")
    return encode_sticker(
        {"id": "custom_" + row.id, "label": row.label, "description": row.description}
    )


def sticker_response(row):
    return {"id": "custom_" + row.id, "label": row.label, "description": row.description}


async def list_stickers(user, session) -> list[dict]:
    rows = (
        await session.exec(
            select(UserSticker)
            .where(UserSticker.user_id == user.id, UserSticker.deleted.is_(False))
            .order_by(UserSticker.id)
        )
    ).all()
    return [sticker_response(row) for row in rows]


async def upload_sticker(payload: StickerUpload, user, session) -> dict:
    label = payload.label.strip()
    if not label:
        raise ServiceError(422, "请填写表情文字")
    try:
        raw = base64.b64decode(payload.data, validate=True)
    except (ValueError, binascii.Error):
        raise ServiceError(422, "图片数据无效") from None
    valid = False
    if payload.mime_type == "image/png" and len(raw) >= 33 and raw.startswith(b"\x89PNG\r\n\x1a\n"):
        width, height = struct.unpack(">II", raw[16:24])
        valid = 0 < width <= 4096 and 0 < height <= 4096
    elif payload.mime_type == "image/jpeg":
        valid = raw.startswith(b"\xff\xd8") and raw.endswith(b"\xff\xd9") and len(raw) > 20
    elif payload.mime_type == "image/gif" and len(raw) > 20 and raw[:6] in (b"GIF87a", b"GIF89a"):
        width, height = struct.unpack("<HH", raw[6:10])
        valid = 0 < width <= 4096 and 0 < height <= 4096
    elif payload.mime_type == "image/webp":
        valid = len(raw) > 20 and raw[:4] == b"RIFF" and raw[8:12] == b"WEBP"
    if not valid or len(raw) > 5 * 1024 * 1024:
        raise ServiceError(422, "请使用不超过 5 MB 的 PNG、JPG、GIF 或 WebP 图片")
    digest = hashlib.sha256(raw).hexdigest()
    row = (
        await session.exec(
            select(UserSticker).where(UserSticker.user_id == user.id, UserSticker.digest == digest)
        )
    ).first()
    if row is None or row.deleted:
        count = len(
            (
                await session.exec(
                    select(UserSticker.id).where(
                        UserSticker.user_id == user.id, UserSticker.deleted.is_(False)
                    )
                )
            ).all()
        )
        if count >= 100:
            raise ServiceError(422, "最多可添加 100 个自己的表情")
    if row is None:
        row = UserSticker(
            user_id=user.id,
            digest=digest,
            label=label,
            description=payload.description.strip() or label,
            mime_type=payload.mime_type,
        )
    row.deleted = False
    row.label = label
    row.description = payload.description.strip() or label
    written_path = file_path(row.id)
    written_path.parent.mkdir(parents=True, exist_ok=True)
    written_path.write_bytes(raw)
    session.add(row)
    try:
        await session.commit()
    except IntegrityError:
        await session.rollback()
        written_path.unlink(missing_ok=True)
        row = (
            await session.exec(
                select(UserSticker).where(
                    UserSticker.user_id == user.id, UserSticker.digest == digest
                )
            )
        ).one()
        row.deleted = False
        row.label = label
        row.description = payload.description.strip() or label
        await session.commit()
    return sticker_response(row)


async def sticker_image(identifier: str, user, session):
    row = await session.get(UserSticker, identifier)
    if not row or row.user_id != user.id:
        raise ServiceError(404, "表情不存在")
    path = file_path(row.id)
    if not path.is_file():
        raise ServiceError(404, "表情图片不存在")
    return path, row.mime_type


async def remove_sticker(identifier: str, user, session):
    row = await session.get(UserSticker, identifier)
    if not row or row.user_id != user.id:
        raise ServiceError(404, "表情不存在")
    row.deleted = True
    await session.commit()
