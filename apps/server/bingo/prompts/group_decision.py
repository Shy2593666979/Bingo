"""Text-group turn boundaries: distinguish useful follow-up from more chatter."""

TEXT_TURN_RULES = (
    "以recent中的本轮交流为主要依据；previous_context只是旧背景，不是新的接话任务。"
    "speaker_reply_counts统计本轮累计发言次数，不是连续次数，不能被其他人插一句就清零。"
    "普通闲聊、问候、找人或定向问答不是持续讨论：问题得到回应后优先结束。"
    "例如用户问‘小田老师呢’：暖暖接一句，小田老师回应一句，就足够；"
    "暖暖只有确实要纠正重要信息或回应未解决的问题时，才可再补一句。"
    "若暖暖本轮已说两句，即使中间小田说过一句，也不要再选暖暖第三句。"
    "不要把客套、附和、再次邀约、重复承诺、说‘我在’、继续旧剧情当作新价值。"
    "只有participation_intent=discussion的明确持续讨论，才允许围绕新观点多次来回。"
    "选finish是正常且优先的结果，不需要让每个人都总结，也不要为热闹强行续聊。"
)

TEXT_CONTINUATION = (
    "判断本轮是否确实还欠一句有必要的回应。以latest_user、recent、pending_participants"
    "和speaker_reply_counts为准，不因previous_context中的旧话题继续生成。"
    "普通问候、找人和闲聊默认finish。没有待回应对象、问题已回答、已向真人提问时，应等待真人。"
    "普通场景示例：用户问小田老师呢→暖暖邀请小田→小田说我在：finish；"
    "若暖暖又补一句，那之后必须finish，不能继续安排暖暖第三句。"
    "用户说哈喽→AI问今晚想聊什么：finish。用户想听两人说话→两人都回应：finish。"
    "participation_intent=discussion不适用普通找人的两轮示例："
    "用户要求持续讨论且实质分歧尚未解决时，应continue。"
    "其他例外：搭子向另一位提出尚未回答的问题；"
    "需要纠正重要错误。只有能指出这类具体未完成任务时才continue。"
)
