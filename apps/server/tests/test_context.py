from datetime import datetime

from bingo.agent.context import build_context
from bingo.db.models import Memory, Message
from bingo.prompts import SYSTEM_PROMPT


def test_context_cleans_only_assistant_text_and_keeps_user_and_memory_unchanged():
    messages = [
        Message(conversation_id="chat", role="user", content="我说的是————这个"),
        Message(conversation_id="chat", role="assistant", content="抱抱你——辛苦了。"),
        Message(conversation_id="chat", role="assistant", content="————"),
    ]
    memory = Memory(content="保留——原始记忆")
    context = build_context(
        messages,
        [memory],
        username="用户",
        assistant_name="Bingo",
        personality="温柔",
        role="朋友",
        timezone="Asia/Shanghai",
    )
    assert "保留——原始记忆" in context[0].content
    assert context[1].content.endswith("我说的是————这个")
    assert context[2].content == "抱抱你，辛苦了。"
    assert len(context) == 3
    assert messages[1].content == "抱抱你——辛苦了。"
    assert memory.content == "保留——原始记忆"


def test_only_user_context_gets_timestamp_without_changing_messages_or_memories() -> None:
    messages = [
        Message(
            conversation_id="conversation",
            role="user",
            content="今天好累",
            created_at=datetime.fromisoformat("2026-10-02T21:30:00+08:00"),
        ),
        Message(conversation_id="conversation", role="assistant", content="怎么了？"),
        Message(
            conversation_id="conversation",
            role="user",
            content="我刚才说的那件事……",
            created_at=datetime.fromisoformat("2026-10-09T10:05:00+08:00"),
        ),
    ]
    memories = [Memory(content="用户喜欢浅烘咖啡", scope="user")]
    context = build_context(
        messages,
        memories,
        username="小明",
        assistant_name="Bingo",
        personality="温柔",
        role="朋友",
        timezone="Asia/Shanghai",
        now=datetime.fromisoformat("2026-10-09T10:10:00+08:00"),
    )
    assert context[1].content == "[2026年10月2日 晚上 21:30] 今天好累"
    assert context[2].content == "怎么了？"
    assert context[3].content == "[10月9日 今天 上午 10:05] 我刚才说的那件事……"
    assert messages[0].content == "今天好累"
    assert messages[2].content == "我刚才说的那件事……"
    assert memories[0].content == "用户喜欢浅烘咖啡"
    assert "用户全局记忆：\n- [fact] 用户喜欢浅烘咖啡" in context[0].content
    assert "用户消息开头的方括号是时间信息，不是用户说的话。" in context[0].content


def test_location_is_a_system_template_field() -> None:
    assert "用户当前位置：{current_location}" in SYSTEM_PROMPT
    context = build_context(
        [],
        [],
        username="小明",
        assistant_name="Bingo",
        personality="温柔体贴",
        role="朋友",
        timezone="Asia/Shanghai",
        current_location="北京市海淀区",
    )
    prompt = context[0].content
    assert prompt.count("用户当前位置：") == 1
    assert "用户当前位置：北京市海淀区" in prompt
    assert prompt.index("用户当前位置：") < prompt.index("用户全局记忆：")


def test_context_contains_persona_time_and_memory() -> None:
    context = build_context(
        [],
        [Memory(content="用户喜欢浅烘咖啡")],
        username="小明",
        assistant_name="Bingo",
        personality="温柔体贴",
        role="朋友",
        timezone="Asia/Shanghai",
    )

    prompt = context[0].content
    assert "你是 Bingo" in prompt
    assert "小明" in prompt
    assert "温柔体贴" in prompt
    assert "朋友" in prompt
    assert "只输出纯文本，不使用 Markdown" in prompt
    assert "用户喜欢浅烘咖啡" in prompt
    assert "当前时间：" in prompt
    assert "（周" in prompt
    assert any(
        period in prompt for period in ("早上", "上午", "中午", "下午", "晚上", "深夜", "凌晨")
    )


def test_context_excludes_call_timeline_records() -> None:
    context = build_context(
        [
            Message(conversation_id="conversation", role="user", content="hello"),
            Message(
                conversation_id="conversation",
                role="assistant",
                content="call ended",
                message_type="call",
                call_status="ended",
                call_duration_seconds=65,
            ),
        ],
        [],
        username="user",
        assistant_name="Bingo",
        personality="kind",
        role="friend",
        timezone="Asia/Shanghai",
    )

    assert len(context) == 2
    assert context[1].content.endswith("] hello")


def test_context_separates_memory_scopes_and_prioritizes_current_role() -> None:
    context = build_context(
        [],
        [
            Memory(content="用户住在北京", scope="user"),
            Memory(content="老师需要检查学习计划", scope="role"),
            Memory(content="用户称老师为导师", scope="user_role"),
        ],
        username="小明",
        assistant_name="Bingo",
        personality="温柔体贴",
        role="老师",
        role_prompt="耐心指导用户。",
        timezone="Asia/Shanghai",
    )

    prompt = context[0].content
    assert "当前角色设置拥有最高优先级" in prompt
    assert "用户全局记忆：\n- [fact] 用户住在北京" in prompt
    assert "当前角色记忆：\n- [fact] 老师需要检查学习计划" in prompt
    assert "当前角色与用户的关系记忆：\n- [fact] 用户称老师为导师" in prompt
