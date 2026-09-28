# 系统架构

## 当前范围

```text
Flutter Android 应用
        |
        | 通过局域网使用 HTTP
        v
FastAPI 服务
        |
        +-- 智能体运行时
        +-- 大语言模型提供商
        +-- 工具注册表
        |     +-- 网络搜索
        |     +-- 天气
        |     +-- 设备闹钟请求
        +-- 身份验证和用户资料
        +-- SQLite 对话、记忆和设备操作
        +-- Redis 延迟陪伴任务和推荐
```

移动端负责界面展示和连接管理。服务端负责模型访问、对话状态和持久化。API Key 不会进入 APK。

实时通话也遵循相同的边界。Android 采集并播放 PCM 音频，但只连接 Bingo 的鉴权 WebSocket。FastAPI 服务负责在二进制音频帧与 Qwen-Audio-Realtime 事件协议之间转换，因此 DashScope 密钥和供应商专用协议都保留在服务端。

Android 应用还会保存一份按用户隔离的 SQLite 对话副本。首次运行时会导入现有服务端历史记录一次。之后启动时从本地 SQLite 恢复当前对话和历史列表；只有新的聊天请求以及常规会话/资料检查需要访问服务端。

## 边界

- `api` 将 HTTP 流量转换为应用调用。
- `agent` 编排一次聊天运行，不依赖 FastAPI。
- `agent/model_client.py` 隐藏供应商专用的模型 API。
- `tools` 通过统一的 `BaseTool`、`ToolContext` 和 `ToolRegistry` 暴露异步工具；智能体运行时只依赖注册表。
- `db` 负责持久化模型和查询。
- 不透明的登录会话保存在服务端；密码使用带盐的 scrypt 哈希，移动端令牌使用 Android Keystore 加密存储。
- 系统提示词按请求组装，包含用户的助手名称、个性（包括说话风格）、角色、当前 `Asia/Shanghai` 时间和长期记忆。
- 对话和记忆按已认证的用户 ID 隔离。
- Flutter 功能依赖仓储层，不直接依赖传输细节。
- `bingo/local_chat` 将 Flutter 连接到 Android 内置的 `SQLiteOpenHelper`，避免运行时或构建时依赖第三方数据库插件。

设备操作受到代码强制的审批边界保护。模型可以创建待处理请求，但只有已认证用户可以批准。随后 Android 调用操作系统界面并报告结果。

浏览器自动化、调度器、多智能体执行和云基础设施不在当前范围内。

## 云迁移

将服务端迁移到云主机应当只需要部署和配置变更，而不需要重写代码。替换移动端基础 URL、启用 HTTPS，并在并发量或运维需求达到必要程度时将 SQLite 迁移到 PostgreSQL。
