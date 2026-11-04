# Bingo 服务端

用于本地开发的 FastAPI 服务。将 `config/config.example.yaml` 复制为 `config/config.yaml`，然后在当前目录运行：

```powershell
uv sync --extra dev
uv run python -m bingo
```

`config/config.yaml` 按组件组织配置。默认模型提供商是 `echo`；连接真实模型时，将 `model.provider` 设置为 `openai_compat`，并填写接口地址、密钥和模型。只有当配置文件位于默认位置之外时，才需要设置 `BINGO_CONFIG_FILE`。如果本地配置文件不存在，Bingo 会使用带有安全默认值的 `config/config.example.yaml`。

推送通知默认关闭。关于个推和小米/OPPO/vivo 离线通道的配置，请参阅 [`../../docs/push.md`](../../docs/push.md)。

群聊电话仍使用 `/groups/{group_id}/calls/stream`。客户端在 `client_audio_ready` 中发送
`playback_results: true` 后即自动使用自然多人接话；旧客户端保留有界回应以兼容旧播放回执。
新客户端的 `played` 必须携带 `utterance_id`、`generation` 和真实播放 `status`
（`completed`、`interrupted`、`timeout`、`failed`）。只有完成播放才写入已听历史并计数。

群聊电话默认就是自然多人交流，无需用户开启讨论模式，也没有轮数选择控件。
开发者通过 `config/config.yaml` 的 `group_call.max_silent_turns` 配置连续发言上限，默认 30。
客户端不能修改这个配置；旧版试验性的设置、暂停和继续控制命令会被拒绝。
用户可以直接表达心情、提问、提出辩题、暂停或换话题，搭子自然回应。
服务端通过 `discussion_state` 返回内部状态。有效用户转写开启新段并重置连续计数；
partial 只打断，不清零。无最终转写时，连续 8 秒没有新的 partial 才尝试恢复。
明确要求先安静后，不会因误识别 partial 自动恢复；用户再次正常说话时自然回应。
没有新内容或达到连续上限后回到监听，通话保持连接。

当前保护边界为单讨论段 20 分钟、单通电话自动生成时间 60 分钟、模型请求 400 次；
用户插话不会重置整通电话的预算。调度、角色生成、摘要和意图识别都计入请求数。
统计包含 TTS 请求、生成音频字节和播放结果，尚不等同于供应商的精确计费 token。
状态由当前通话内存持有；结束时在 `GroupCall.transcript_json` 列表末尾追加
`type=discussion_summary, version=1` 的统计记录，不将讨论摘要写入角色长期记忆。
部署新服务端后需配套更新客户端，才能验证自主讨论与严格播放回执；回声误打断仍须真机测试。

运行日志默认写入 `logs/bingo.log` 和 `logs/access.log`。日志使用北京时间，每天轮换，并保留 14 天。可以在 `config/config.yaml` 的 `logging` 部分配置；如果生产环境由 Docker 或 systemd 收集标准输出，请将两个文件名都设置为 `null`。请求日志不会包含查询字符串或请求体，业务事件必须使用 `bingo.services.logging.log_event` 暴露的安全字段。
