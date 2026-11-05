import base64
import json

from sqlalchemy import func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import defer
from sqlmodel import delete, select, update

from bingo.db.models import Role, RolePreference, User, new_id
from bingo.db.models.community import (
    CharacterComment,
    CharacterFavorite,
    CharacterInstall,
    CharacterLike,
    CharacterShare,
    CommunityReport,
)
from bingo.db.repositories import RoleRepository
from bingo.roles import role_id
from bingo.schemas.community import ShareCreate
from bingo.services.context import BinaryAsset
from bingo.services.exceptions import ServiceError
from bingo.services.roles import response_for_user


async def require_share(session, identifier, user, *, allow_own=False):
    share = await session.get(CharacterShare, identifier)
    if not share or (
        share.status != "published" and not (allow_own and share.author_id == user.id)
    ):
        raise ServiceError(404, "这个分享已撤回或不存在")
    return share


async def share_response(session, share, user, *, detail=False):
    installed = (
        await session.exec(
            select(CharacterInstall).where(
                CharacterInstall.user_id == user.id, CharacterInstall.share_id == share.id
            )
        )
    ).first()
    installed_role = await session.get(Role, installed.role_id) if installed else None
    installed_id = installed_role.id if installed_role and not installed_role.deleted else None
    favorites = (
        await session.exec(
            select(func.count())
            .select_from(CharacterFavorite)
            .where(CharacterFavorite.share_id == share.id)
        )
    ).one()
    installs = (
        await session.exec(
            select(func.count())
            .select_from(CharacterInstall)
            .where(CharacterInstall.share_id == share.id)
        )
    ).one()
    likes = (
        await session.exec(
            select(func.count())
            .select_from(CharacterLike)
            .where(CharacterLike.share_id == share.id)
        )
    ).one()
    comments = (
        await session.exec(
            select(func.count())
            .select_from(CharacterComment)
            .where(CharacterComment.share_id == share.id, CharacterComment.deleted.is_(False))
        )
    ).one()
    result = {
        "id": share.id,
        "name": share.name,
        "introduction": share.introduction,
        "author_name": share.author_name,
        "is_mine": share.author_id == user.id,
        "created_at": share.created_at.isoformat(),
        "status": share.status,
        "has_avatar": share.has_avatar,
        "has_images": share.has_images,
        "parent_share_id": share.parent_share_id,
        "install_count": installs,
        "favorite_count": favorites,
        "like_count": likes,
        "comment_count": comments,
        "popularity_score": likes + favorites + comments,
        "is_liked": await session.get(CharacterLike, (user.id, share.id)) is not None,
        "is_favorite": await session.get(CharacterFavorite, (user.id, share.id)) is not None,
        "installed_role_id": installed_id,
        **json.loads(share.summary_json),
    }
    if detail:
        result["persona"] = json.loads(share.snapshot_json)
        result["image_count"] = len(json.loads(share.images_json or "[]"))
    return result


async def publish(session, user: User, payload: ShareCreate):
    images_json = json.dumps(payload.images, ensure_ascii=False) if payload.images else None
    existing = (
        await session.exec(
            select(CharacterShare).where(
                CharacterShare.author_id == user.id, CharacterShare.request_id == payload.request_id
            )
        )
    ).first()
    if existing:
        if (
            existing.source_role_id != payload.role_id
            or existing.introduction != payload.introduction
            or (existing.images_json or None) != images_json
            or json.loads(existing.summary_json).get("title", "") != payload.title
            or json.loads(existing.summary_json).get("share_tags", []) != payload.share_tags
        ):
            raise ServiceError(409, "请重新打开分享页面后提交")
        return await share_response(session, existing, user, detail=True)
    role = await session.get(Role, payload.role_id)
    if not await RoleRepository(session).can_access(user, role):
        raise ServiceError(404, "搭子不存在")
    role_info = await response_for_user(session, user, role)
    source = await session.get(Role, role.voice_source_id) if role.voice_source_id else None
    if role.owner_id is None:
        source = role
    # Public shares may reuse system voices, never another account's private clone.
    public_voice = source if source and source.owner_id is None and not source.deleted else None
    if public_voice is None:
        public_voice = await session.get(Role, role_id("girlfriend"))
    snapshot = {
        "name": role.nickname,
        "prompt": role.prompt,
        "background": role_info["background"],
        "speaking_style": role_info["speaking_style"],
        "personality_tags": role_info["personality_tags"],
        "relationship": role_info["relationship"],
        "description": role.description,
        "opening_line": role.opening_line,
        "role_type": role.name if role.owner_id is None else role.role_type,
        "personality": role_info["personality"] or "温柔体贴",
        "categories": json.loads(role.categories_json),
        "traits": json.loads(role.traits_json),
        "voice_source_id": public_voice.id if public_voice else None,
        "avatar_asset": role.avatar,
    }
    summary = {
        key: snapshot[key]
        for key in (
            "role_type", "personality", "categories", "traits", "avatar_asset",
            "relationship", "speaking_style", "personality_tags",
        )
    }
    summary["image_count"] = len(payload.images)
    summary["title"] = payload.title
    summary["share_tags"] = payload.share_tags
    share = CharacterShare(
        author_id=user.id,
        source_role_id=role.id,
        request_id=payload.request_id,
        author_name=user.username or "Bingo 用户",
        name=role.nickname,
        introduction=payload.introduction,
        parent_share_id=role.source_publication_id,
        snapshot_json=json.dumps(snapshot, ensure_ascii=False),
        summary_json=json.dumps(summary, ensure_ascii=False),
        avatar_data=role.avatar_data,
        has_avatar=bool(role.avatar_data),
        images_json=images_json,
        has_images=bool(payload.images),
    )
    session.add(share)
    try:
        await session.commit()
    except IntegrityError:
        await session.rollback()
        await session.refresh(user)
        duplicate = (
            await session.exec(
                select(CharacterShare.id).where(
                    CharacterShare.author_id == user.id,
                    CharacterShare.request_id == payload.request_id,
                )
            )
        ).first()
        if duplicate is None:
            raise
        return await publish(session, user, payload)
    return await share_response(session, share, user, detail=True)


async def list_shares(session, user, *, query="", scope="all", sort="latest", offset=0, limit=20):
    statement = select(CharacterShare).options(
        defer(CharacterShare.avatar_data),
        defer(CharacterShare.snapshot_json),
        defer(CharacterShare.images_json),
    )
    if scope == "mine":
        statement = statement.where(CharacterShare.author_id == user.id)
    else:
        statement = statement.where(CharacterShare.status == "published")
    if scope == "favorites":
        statement = statement.join(
            CharacterFavorite, CharacterFavorite.share_id == CharacterShare.id
        ).where(CharacterFavorite.user_id == user.id)
    if scope == "recommended":
        # Install history is deliberate: removing a copy does not turn the same
        # publication into a new discovery. Filtering happens before pagination.
        statement = statement.where(
            CharacterShare.author_id != user.id,
            CharacterShare.id.not_in(
                select(CharacterInstall.share_id).where(CharacterInstall.user_id == user.id)
            ),
            CharacterShare.id.not_in(
                select(CommunityReport.share_id).where(CommunityReport.user_id == user.id)
            ),
        )
    if query.strip():
        statement = statement.where(
            CharacterShare.name.contains(query.strip(), autoescape=True)
            | CharacterShare.author_name.contains(query.strip(), autoescape=True)
            | CharacterShare.introduction.contains(query.strip(), autoescape=True)
            | CharacterShare.summary_json.contains(query.strip(), autoescape=True)
        )
    if sort == "popular" or scope == "recommended":
        popularity = sum(
            select(func.count())
            .select_from(model)
            .where(
                model.share_id == CharacterShare.id,
                *([model.deleted.is_(False)] if model is CharacterComment else []),
            )
            .correlate(CharacterShare)
            .scalar_subquery()
            for model in (CharacterLike, CharacterFavorite, CharacterComment)
        )
        statement = statement.order_by(popularity.desc())
    statement = statement.order_by(CharacterShare.created_at.desc(), CharacterShare.id.desc())
    rows = (await session.exec(statement.offset(offset).limit(limit + 1))).all()
    total = (
        await session.exec(select(func.count()).select_from(statement.order_by(None).subquery()))
    ).one()
    return {
        "items": [await share_response(session, share, user) for share in rows[:limit]],
        "next_offset": offset + limit if len(rows) > limit else None,
        "total": total,
    }


async def get_share(session, user, identifier):
    return await share_response(
        session, await require_share(session, identifier, user, allow_own=True), user, detail=True
    )


async def install(session, user, identifier):
    share = await require_share(session, identifier, user)
    existing = (
        await session.exec(
            select(CharacterInstall).where(
                CharacterInstall.user_id == user.id, CharacterInstall.share_id == share.id
            )
        )
    ).first()
    if existing:
        role = await session.get(Role, existing.role_id)
        if role and not role.deleted:
            return await response_for_user(session, user, role)
    snapshot = json.loads(share.snapshot_json)
    source = await session.get(Role, snapshot.get("voice_source_id"))
    if not source or source.owner_id is not None or source.deleted or not source.enabled:
        source = await session.get(Role, role_id("girlfriend"))
    identifier = new_id()
    # Names shown to users may collide; internal names remain unique and editable copies
    # are renamed automatically to satisfy the existing role editor's unique-name rule.
    names = set(
        (
            await session.exec(
                select(Role.display_name).where(Role.owner_id == user.id, Role.deleted.is_(False))
            )
        ).all()
    )
    builtin_roles = (
        await session.exec(select(Role).where(Role.owner_id.is_(None)))
    ).all()
    names.update(value for role in builtin_roles for value in (role.name, role.nickname))
    name = snapshot["name"]
    index = 2
    while name in names:
        suffix = f" {index}"
        name = snapshot["name"][: 30 - len(suffix)] + suffix
        index += 1
    role = Role(
        id=identifier,
        code=identifier,
        name=identifier.replace("-", "")[:30],
        owner_id=user.id,
        display_name=name,
        role_type=snapshot.get("role_type"),
        background=snapshot.get("background", snapshot["prompt"]),
        speaking_style=snapshot.get("speaking_style", snapshot["personality"]),
        description=snapshot["description"],
        opening_line=snapshot.get("opening_line", ""),
        prompt=snapshot["prompt"],
        avatar=snapshot.get("avatar_asset", "bingo_logo.png"),
        avatar_data=share.avatar_data,
        voice=source.voice if source else "",
        voice_source_id=source.id if source else None,
        source_publication_id=share.id,
        categories_json=json.dumps(snapshot["categories"], ensure_ascii=False),
        traits_json=json.dumps(snapshot["traits"], ensure_ascii=False),
        sort_order=100,
    )
    session.add(role)
    session.add(
        RolePreference(
            user_id=user.id, role_id=role.id, personality=snapshot["personality"],
            speaking_style=snapshot.get("speaking_style"),
        )
    )
    if existing:
        # A deleted copy can be re-added from two devices at once. Only the
        # request that replaces the old mapping keeps its newly created role.
        replaced = await session.exec(
            update(CharacterInstall)
            .where(CharacterInstall.id == existing.id, CharacterInstall.role_id == existing.role_id)
            .values(role_id=role.id)
        )
        if replaced.rowcount != 1:
            await session.rollback()
            await session.refresh(user)
            await session.refresh(share)
            return await install(session, user, share.id)
    else:
        session.add(CharacterInstall(user_id=user.id, share_id=share.id, role_id=role.id))
    try:
        await session.commit()
    except IntegrityError:
        await session.rollback()
        await session.refresh(user)
        await session.refresh(share)
        duplicate = (
            await session.exec(
                select(CharacterInstall.id).where(
                    CharacterInstall.user_id == user.id, CharacterInstall.share_id == share.id
                )
            )
        ).first()
        if duplicate is None:
            raise
        return await install(session, user, share.id)
    return await response_for_user(session, user, role)


async def set_favorite(session, user, identifier, favorite):
    await require_share(session, identifier, user)
    row = await session.get(CharacterFavorite, (user.id, identifier))
    if favorite and row is None:
        session.add(CharacterFavorite(user_id=user.id, share_id=identifier))
    elif not favorite and row:
        await session.delete(row)
    try:
        await session.commit()
    except IntegrityError:
        await session.rollback()
        await session.refresh(user)
    return await get_share(session, user, identifier)


async def set_like(session, user, identifier, liked):
    await require_share(session, identifier, user)
    row = await session.get(CharacterLike, (user.id, identifier))
    if liked and row is None:
        session.add(CharacterLike(user_id=user.id, share_id=identifier))
    elif not liked and row:
        await session.delete(row)
    try:
        await session.commit()
    except IntegrityError:
        await session.rollback()
        await session.refresh(user)
    return await get_share(session, user, identifier)


def comment_response(comment, user):
    return {
        "id": comment.id,
        "author_name": comment.author_name,
        "content": comment.content,
        "is_mine": comment.user_id == user.id,
        "created_at": comment.created_at.isoformat(),
    }


async def list_comments(session, user, identifier, offset=0, limit=20):
    await require_share(session, identifier, user, allow_own=True)
    statement = select(CharacterComment).where(
        CharacterComment.share_id == identifier, CharacterComment.deleted.is_(False)
    )
    rows = (
        await session.exec(
            statement.order_by(CharacterComment.created_at.desc(), CharacterComment.id.desc())
            .offset(offset)
            .limit(limit + 1)
        )
    ).all()
    return {
        "items": [comment_response(row, user) for row in rows[:limit]],
        "next_offset": offset + limit if len(rows) > limit else None,
    }


async def add_comment(session, user, identifier, payload):
    await require_share(session, identifier, user)
    old = (
        await session.exec(
            select(CharacterComment).where(
                CharacterComment.user_id == user.id,
                CharacterComment.share_id == identifier,
                CharacterComment.request_id == payload.request_id,
            )
        )
    ).first()
    if old:
        if old.content != payload.content or old.deleted:
            raise ServiceError(409, "评论内容已变更，请重新提交")
        return comment_response(old, user)
    row = CharacterComment(
        user_id=user.id,
        share_id=identifier,
        request_id=payload.request_id,
        author_name=user.username or "Bingo 用户",
        content=payload.content,
    )
    session.add(row)
    try:
        await session.commit()
        await session.refresh(row)
    except IntegrityError:
        await session.rollback()
        await session.refresh(user)
        return await add_comment(session, user, identifier, payload)
    return comment_response(row, user)


async def delete_comment(session, user, identifier, comment_id):
    share = await require_share(session, identifier, user, allow_own=True)
    row = await session.get(CharacterComment, comment_id)
    if (
        not row
        or row.share_id != identifier
        or (row.user_id != user.id and share.author_id != user.id)
    ):
        raise ServiceError(404, "评论不存在")
    row.deleted = True
    await session.commit()


async def withdraw(session, user, identifier):
    share = await require_share(session, identifier, user, allow_own=True)
    if share.author_id != user.id:
        raise ServiceError(404, "分享不存在")
    share.status = "withdrawn"
    await session.commit()


async def report(session, user, identifier, reason):
    await require_share(session, identifier, user)
    existing = (
        await session.exec(
            select(CommunityReport).where(
                CommunityReport.user_id == user.id, CommunityReport.share_id == identifier
            )
        )
    ).first()
    if existing is None:
        session.add(CommunityReport(user_id=user.id, share_id=identifier, reason=reason.strip()))
    try:
        await session.commit()
    except IntegrityError:
        await session.rollback()


async def avatar(session, user, identifier):
    share = await require_share(session, identifier, user, allow_own=True)
    if not share.avatar_data:
        raise ServiceError(404, "没有设置头像")
    return BinaryAsset(
        base64.b64decode(share.avatar_data), "image/png", {"Cache-Control": "private, max-age=300"}
    )


_IMAGE_MEDIA = {
    b"\x89PNG": "image/png",
    b"\xff\xd8": "image/jpeg",
    b"GIF8": "image/gif",
}


async def image(session, user, identifier, index: int):
    share = await require_share(session, identifier, user, allow_own=True)
    images = json.loads(share.images_json) if share.images_json else []
    if index < 0 or index >= len(images):
        raise ServiceError(404, "没有这张图片")
    data = base64.b64decode(images[index])
    media = next(
        (mime for magic, mime in _IMAGE_MEDIA.items() if data[: len(magic)] == magic),
        "image/webp" if data[:4] == b"RIFF" and data[8:12] == b"WEBP" else "image/png",
    )
    return BinaryAsset(data, media, {"Cache-Control": "private, max-age=3600"})


async def delete_user_community_data(session, user_id):
    authored = select(CharacterShare.id).where(CharacterShare.author_id == user_id)
    for model in (
        CharacterFavorite,
        CharacterInstall,
        CharacterLike,
        CharacterComment,
        CommunityReport,
    ):
        await session.exec(
            delete(model).where((model.user_id == user_id) | model.share_id.in_(authored))
        )
    await session.exec(delete(CharacterShare).where(CharacterShare.author_id == user_id))
