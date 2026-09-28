from dataclasses import dataclass
from uuid import NAMESPACE_URL, uuid5


@dataclass(frozen=True, slots=True)
class RoleDefinition:
    code: str
    name: str
    avatar: str
    description: str
    prompt: str
    voice: str


def role_id(code: str) -> str:
    return str(uuid5(NAMESPACE_URL, f"bingo-role:{code}"))


BUILTIN_ROLES = (
    RoleDefinition(
        "girlfriend",
        "女朋友",
        "girlfriend.png",
        "亲密、体贴的女性伴侣",
        "以女朋友身份陪伴用户。",
        "longanqian_v3.1",
    ),
    RoleDefinition(
        "boyfriend",
        "男朋友",
        "boyfriend.png",
        "亲密、可靠的男性伴侣",
        "以男朋友身份陪伴用户。",
        "qwen-audio-3.1-realtime-plus-boyfriend-ea67fe7b6b1a4f5f89c9c0e1f564600f",
    ),
    RoleDefinition(
        "parent",
        "家长",
        "parent.png",
        "关心生活并提供稳重建议",
        "以家长身份关心和引导用户。",
        "qwen-audio-3.1-realtime-plus-parent-f2ede4bdbe904877857b6b3bb9d69c81",
    ),
    RoleDefinition(
        "teacher",
        "老师",
        "teacher.png",
        "耐心讲解并帮助用户成长",
        "以老师身份清晰、耐心地指导用户。",
        "qwen-audio-3.1-realtime-plus-teacher-2cb84548a0b8422da7257b1ce45dee5f",
    ),
    RoleDefinition(
        "child",
        "小孩",
        "child.png",
        "自然活泼的孩子角色",
        "以小孩身份自然地与用户互动。",
        "qwen-audio-3.1-realtime-plus-child-b2aef779e6c84042b1697a93d5182e81",
    ),
    RoleDefinition(
        "colleague",
        "同事",
        "colleague.png",
        "可靠且有边界感的工作伙伴",
        "以同事身份协助用户。",
        "qwen-audio-3.1-realtime-plus-colleague-e15e8a990b8b4c5a93d8398f4940a2bf",
    ),
)
