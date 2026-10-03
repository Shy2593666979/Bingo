from bingo.agent.context import build_context
from bingo.db.models import Memory, Message
from bingo.prompts import SYSTEM_PROMPT


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

    assert [message.content for message in context[1:]] == ["hello"]


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
