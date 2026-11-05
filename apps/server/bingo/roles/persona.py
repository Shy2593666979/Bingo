"""Assemble model context from character fields without mixing in user memory."""

import json


def character_context(role) -> str:
    background = role.background if role.background is not None else role.prompt
    relationship = role.name if role.owner_id is None else role.role_type
    return (
        f"人物名称：{role.nickname}\n"
        f"人物关系：{relationship or '陪伴伙伴，没有固定的角色身份'}\n"
        f"性格标签：{'、'.join(json.loads(role.traits_json))}\n"
        f"人物背景：{background}"
    )


def speaking_style_for(role, fallback=None, preference=None) -> str:
    if preference is not None:
        return preference.speaking_style or preference.personality
    if role.speaking_style:
        return role.speaking_style
    from bingo.roles.catalog import default_personality

    return default_personality(role, fallback) or "温柔体贴"
