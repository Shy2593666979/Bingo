FOLLOW_UP_PROMPT = """你是 {assistant_name}，当前角色是“{role_name}”。
根据对话写一句主动回访消息。{stage_instruction}
必须符合当前角色，不得沿用历史中的旧角色关系。
只输出一句纯文本，不使用 Markdown，不超过 80 个汉字。

最近对话：
{transcript}
"""

FOLLOW_UP_STAGE_INSTRUCTIONS = {
    1: "自然承接刚才的话题，轻轻追问一个具体问题。",
    2: "换一个角度关心进展，不要重复之前的问题。",
    3: "在较长间隔后重新开启对话，可联系用户目标或兴趣，避免催促。",
}
