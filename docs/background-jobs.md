# 后台任务

每次助手完成一轮回复后，服务端会安排：

- 立即抽取长期记忆和用户资料；
- 用户闲置 1、3、10 小时后发送结合上下文的主动回访消息；
- 用户闲置 5 小时后生成 3 条结合上下文的对话推荐。

用户发送新消息后，活动版本会变化、推荐会被清除，旧的主动回访和推荐任务会失效。记忆抽取仍然有效，因为每次完成的对话都可能包含需要长期保存的资料信息。

Redis 使用以下固定键名：

```text
bingo:jobs:scheduled
bingo:job:{job_id}
bingo:user:{user_id}:activity_version
bingo:user:{user_id}:last_active_at
bingo:user:{user_id}:recommendations
```

Android 客户端会在登录时、回到前台时以及应用活跃期间每分钟一次获取待处理消息和推荐。它会先将主动消息保存到本地对话，再确认已收到。应用关闭后的送达需要 FCM，当前版本不负责这部分。
