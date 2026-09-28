# 客户端-服务端协议

所有接口都以 `/api/v1` 为根路径，并使用 HTTP。

## 身份验证

- `POST /auth/register`：使用手机号和密码注册。
- `POST /auth/login`：创建持久化 Bearer 会话。
- `POST /auth/logout`：撤销当前会话。
- `GET /me`：恢复已登录用户和资料。
- `PUT /me/profile`：设置用户名、助手名称、个性和角色。
- `GET /profile/options`：列出支持的个性和角色值。
- `POST /asr/transcribe`：鉴权的单次语音转文字 WAV 上传。
- `WS /realtime/calls/stream`：鉴权的全双工实时语音通话。

除健康检查、注册、登录和资料选项接口外，其他请求都需要
`Authorization: Bearer <access_token>`。Android 客户端将此不透明令牌存储在由 Android Keystore 加密的偏好设置中。

## 聊天流

`POST /chat/stream` 接受：

```json
{
  "conversation_id": null,
  "content": "Hello",
  "run_id": "mobile-unique-id",
  "supersedes_run_id": null,
  "images": []
}
```

对于只有图片或同时包含图片和文字的消息，使用同一个接口并附带一张图片。存在图片时，`content` 可以为空。

```json
{
  "conversation_id": null,
  "content": "这是什么？",
  "run_id": "mobile-unique-id",
  "supersedes_run_id": null,
  "images": [
    {
      "mime_type": "image/jpeg",
      "data": "base64-encoded-image"
    }
  ]
}
```

如果配置了可选的 `vision` 模型，就使用它处理图片消息；否则使用主模型配置。文字和图片消息共享相同的上下文、工具循环、中断处理、流事件和消息持久化逻辑。图片限制为 5 MB，格式必须是 JPEG、PNG 或 WebP。

响应媒体类型为 `application/x-ndjson`，每一行都是一个 JSON 事件。服务端会缓存模型 token，只有遇到句末标点（`。`、`！`、`？`、`!`、`?`）或换行时才作为 `segment` 发出。最后剩余的非空内容会在 `done` 前发出。

```json
{"type":"start","run_id":"mobile-unique-id","conversation_id":"uuid"}
{"type":"segment","content":"第一句话。"}
{"type":"segment","content":"第二句话！"}
{"type":"done","run_id":"mobile-unique-id","message_id":"uuid"}
```

Android 客户端会将每个 `segment` 渲染为独立的助手气泡。在 `done` 到达前，同一消息列表末尾会保留输入中气泡。工具执行不会作为聊天界面状态显示；只有完整的模型/工具循环结束后才会发出 `done`。

运行仍处于活动状态时，客户端可以发送另一个请求，其 `supersedes_run_id` 会标识上一次运行。服务端停止上一次模型/工具循环，将已经发送的助手文本以 `interrupted` 状态保存，并发出 `interrupted` 事件。新运行会等待上一次运行完成持久化后再构建上下文。客户端必须忽略运行 ID 已不再处于活动状态的事件。

被中断的运行不会安排记忆抽取或陪伴任务。下一次完成的运行会对上一次成功抽取之后的所有消息执行带检查点的记忆处理，其中包括被中断的上下文。

对话消息响应包含 `run_id` 和 `status`。`status` 取值为 `streaming`、`interrupted` 或 `completed`；由于流式内容会在运行完成或中断时提交，持久化历史通常只包含后两种状态。

操作手机的工具会在执行前发出审批事件：

```json
{
  "type": "approval_required",
  "action_id": "uuid",
  "tool": "device_alarm_create",
  "title": "Create alarm",
  "description": "2026-09-26 07:00",
  "arguments": {
    "scheduled_at": "2026-09-26T07:00:00+08:00",
    "label": "Wake up",
    "recurrence": "none"
  }
}
```

客户端必须先调用 `POST /device-actions/{id}/approve`，然后才能调用 Android 原生工具。客户端通过 `POST /device-actions/{id}/complete` 报告结果；拒绝操作使用 `POST /device-actions/{id}/reject`。这些状态转换由服务端强制执行，不会根据聊天文本推断。

## 其他接口

- `POST /chat`：非流式兼容接口。
- `GET /chat/images/{image_id}`：鉴权访问已持久化的聊天图片。
- `GET /health`：服务状态。
- `GET /conversations`：按创建时间排序的对话。
- `GET /conversations/{conversation_id}/messages`：按创建时间排序的消息。
- `GET /memories`：已保存的长期记忆。
- `POST /memories`：手动保存一条记忆。
- `DELETE /memories/{memory_id}`：删除一条记忆。
- `GET /proactive/messages`：获取未送达的主动助手消息。
- `POST /proactive/messages/{id}/ack`：确认本地已持久化。
- `GET /recommendations`：获取最多三条上下文相关的对话开场建议。
- `DELETE /recommendations`：清除当前推荐。
- `POST /device-actions/{action_id}/approve`：批准待处理的设备操作。
- `POST /device-actions/{action_id}/reject`：拒绝待处理的设备操作。
- `POST /device-actions/{action_id}/complete`：报告原生执行状态。

以 `记住` 或 `请记住` 开头的消息还会将剩余文本保存为长期记忆。已保存的记忆和当前配置的本地时间会包含在后续模型调用的系统提示词中。对话和记忆始终按已认证用户隔离。

## 实时语音通话

`WS /realtime/calls/stream` 可以通过查询参数接收 `conversation_id`。鉴权使用与 HTTP API 相同的 Bearer 请求头。Android 客户端发送 16 kHz、16-bit、单声道 PCM 二进制帧。Bingo 将音频代理到 Qwen-Audio-Realtime，并以 24 kHz、16-bit、单声道 PCM 二进制帧返回。JSON 文本帧携带 `ready`、转写、说话中、错误和结束事件。客户端发送 `{"type":"hangup"}` JSON 帧即可结束通话。

服务端持有 DashScope API Key，根据用户当前角色和记忆构建实时指令，注入最近的对话历史，并保存最终的用户和助手转写内容。原始通话音频不会被存储。
