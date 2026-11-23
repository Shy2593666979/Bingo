"""All model definitions, imported here to register SQLModel metadata."""

from .base import new_id
from .calls import CallInvitation
from .community import (
    CharacterComment,
    CharacterFavorite,
    CharacterInstall,
    CharacterLike,
    CharacterShare,
    CommunityReport,
)
from .conversations import Conversation, Message
from .device_actions import DeviceAction
from .engagement import MorningGreeting, ProactiveMessage
from .games import PartyGame
from .groups import (
    MAX_GROUP_AI_MEMBERS,
    ChatGroup,
    GroupCall,
    GroupMember,
    GroupMemory,
    GroupMessage,
    GroupRun,
    GroupRunEvent,
)
from .memories import Memory, MemoryCheckpoint
from .push import PushDevice, PushOutbox
from .roles import Role, RolePreference, UserCompanion, VoiceJob
from .stickers import UserSticker
from .users import AuthSession, User
from .voices import Voice
from .welcome import WelcomeJob

__all__ = [
    "new_id",
    "Role",
    "RolePreference",
    "UserCompanion",
    "VoiceJob",
    "Voice",
    "User",
    "AuthSession",
    "DeviceAction",
    "Conversation",
    "Message",
    "MemoryCheckpoint",
    "Memory",
    "ProactiveMessage",
    "MorningGreeting",
    "PartyGame",
    "CallInvitation",
    "PushDevice",
    "PushOutbox",
    "ChatGroup",
    "GroupMember",
    "GroupCall",
    "GroupMessage",
    "GroupRun",
    "GroupRunEvent",
    "GroupMemory",
    "MAX_GROUP_AI_MEMBERS",
    "CharacterShare",
    "CharacterInstall",
    "CharacterFavorite",
    "CharacterLike",
    "CharacterComment",
    "CommunityReport",
    "UserSticker",
    "WelcomeJob",
]
