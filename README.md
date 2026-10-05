<p align="center">
  <img src="apps/mobile/assets/images/bingo_logo.png" width="150" alt="Bingo Logo" />
</p>

<h1 align="center">Bingo</h1>

<p align="center">
  <strong>把陪伴变成一个名字、一种性格、一个熟悉的声音。</strong>
</p>

<p align="center">
  Bingo 是基于 Flutter + Python / FastAPI 的 Android AI 陪伴应用。<br />
  在你的陪伴空间里，与不同伙伴独立聊天、实时通话，也可以亲手创建新的伙伴。
</p>

<p align="center">
  <img alt="Flutter" src="https://img.shields.io/badge/Flutter-Android-02569B?logo=flutter&logoColor=white" />
  <img alt="FastAPI" src="https://img.shields.io/badge/FastAPI-Python_3.12-009688?logo=fastapi&logoColor=white" />
  <img alt="Redis" src="https://img.shields.io/badge/Redis-Background_Jobs-DC382D?logo=redis&logoColor=white" />
  <img alt="Status" src="https://img.shields.io/badge/Status-Active_Prototype-24B47E" />
</p>

> [!NOTE]
> Bingo 目前是一个持续迭代中的原型项目，更适合学习、研究、二次开发和自托管实验。

## 陪伴空间

<table>
  <tr>
    <td align="center" width="25%"><img src="docs/media/companion-space.png" width="230" alt="新版陪伴空间与伙伴卡片" /><br /><sub>一个空间，独立的陪伴</sub></td>
    <td align="center" width="25%"><img src="docs/media/chat-starters.png" width="230" alt="甜甜的圆形头像与专属聊天开场问题" /><br /><sub>不同伙伴，不同的开场</sub></td>
    <td align="center" width="25%"><img src="docs/media/create-companion.png" width="230" alt="创建伙伴的昵称、角色与性格设置" /><br /><sub>定义属于你的伙伴</sub></td>
    <td align="center" width="25%"><img src="docs/media/my-profile.png" width="230" alt="我的页面与个人资料、应用设置" /><br /><sub>资料与设置，统一管理</sub></td>
  </tr>
</table>

<p align="center"><sub>新版界面来自独立演示账号的真实 Android 截图，仅保留 APP 内容。</sub></p>

## 动态预览

保留以下四段 GIF；它们录制于早期版本，当前界面以新版截图为准。

<table>
  <tr>
    <td align="center" width="50%">
      <img src="docs/media/girlfriend-incoming-call.gif" width="330" alt="Bingo 女朋友角色主动来电并接听" /><br />
      <sub><b>女朋友 · 主动来电</b><br />按住发送语音 → 收到来电 → 等待 3 秒 → 点击接听</sub>
    </td>
    <td align="center" width="50%">
      <img src="docs/media/girlfriend-call.gif" width="330" alt="Bingo 女朋友角色实时语音通话" /><br />
      <sub><b>女朋友 · 实时陪伴</b><br />接通后开始聆听，支持静音、挂断与免提</sub>
    </td>
  </tr>
  <tr>
    <td align="center" width="50%">
      <img src="docs/media/boyfriend-chat.gif" width="330" alt="Bingo 男朋友角色日常对话" /><br />
      <sub><b>男朋友 · 日常陪伴</b><br />温柔回应你的情绪，也给出贴心的生活建议</sub>
    </td>
    <td align="center" width="50%">
      <img src="docs/media/quick-actions.gif" width="330" alt="Bingo 男朋友角色快捷功能菜单" /><br />
      <sub><b>男朋友 · 快捷功能</b><br />相册、相机与实时语音通话</sub>
    </td>
  </tr>
</table>

<p align="center"><sub>展示素材由 Android 模拟器实际运行截取，已移除模拟器外框和系统状态栏。</sub></p>

## 为什么是 Bingo

- **不只是聊天**：文字、图片、语音输入与实时语音通话共用同一套个性化上下文。
- **一个空间，多种陪伴**：甜甜、暖暖、小周、小田老师、文清和星星，分别对应女朋友、男朋友、同事、老师、家长和小朋友；每位伙伴拥有独立对话与未读消息。
- **亲手创建伙伴**：自定义昵称、可选角色、性格、伙伴设定和图标化陪伴特征；上传头像后可缩放、移动并圆形裁剪。
- **让声音也熟悉起来**：直接按页面文案朗读 20～30 秒，少于 15 秒提示重录；展示上传、复刻和验证阶段，完成后中文试听。也可直接选择内置音色或已有伙伴的声音。
- **记得你说过的话**：结合用户资料、长期记忆与当前伙伴的聊天上下文；Android 本地保存会话副本，伙伴之间的聊天不混在一起。
- **不止等你开口**：一轮回复结束后，闲置一小时触发回访；昨天聊过的每位伙伴，次日 7～9 点分别随机安排早安，参考昨天的对话与长期记忆，有可靠地区天气时再自然融入天气。
- **管理起来很顺手**：卡片左滑编辑或删除、自定义本地拖动排序；默认六位伙伴仅支持编辑。个人资料和应用设置统一放在「我的」。
- **主动而不冒进**：支持后台任务、推荐和可配置推送；涉及设备的操作必须由用户明确批准。
- **密钥不进 APK**：模型、实时语音和第三方服务凭证全部保留在 FastAPI 服务端。
- **可自托管**：开发时可在局域网运行，部署时也可切换为 HTTPS 公网服务。

> 声音复刻需要配置真实语音服务并获得声音本人的授权。删除自定义伙伴后，其复刻声音不能再被选择使用。应用关闭后的通知送达需要另行配置推送服务；无推送配置时，通过前台轮询同步主动消息。

## 系统架构

```mermaid
flowchart LR
    A[Flutter Android] -->|HTTPS / WebSocket| B[FastAPI API]
    A -->|Local cache| C[(Android SQLite)]
    B --> S[Services]
    S --> D[Agent Runtime]
    D --> E[LLM Provider]
    D --> F[Tool Registry]
    F --> F1[Web Search]
    F --> F2[Weather]
    F --> F3[Device Actions]
    S --> G[(SQLite)]
    S --> H[(Redis)]
    S --> I[Realtime Audio Provider]
```

- Flutter 负责交互、本地会话恢复、音频采集播放与 Android 设备操作。
- FastAPI API 层负责鉴权、参数校验和响应；Services 层负责业务流程、数据库访问、模型与第三方服务调用。
- 普通 HTTP 接口采用统一响应封装；WebSocket 保留事件协议，不套用 HTTP 响应格式。
- Redis 保存延迟任务、推荐队列和有有效期的地区信息；SQL 保存会话、伙伴与早安调度记录。

## 仓库结构

```text
apps/mobile   Flutter Android 客户端
apps/server   FastAPI 智能体服务
docs          架构、协议、推送与声音复刻文档
infra         Redis 等基础设施配置
scripts       本地开发和移动端辅助脚本
```

## 快速开始

### 1. 启动 Redis

```powershell
docker compose -f infra/docker/docker-compose.yml up -d
```

### 2. 启动服务端

需要 Python 3.12 和 [`uv`](https://docs.astral.sh/uv/)。

```powershell
Copy-Item apps/server/config/config.example.yaml apps/server/config/config.yaml
Set-Location apps/server
uv sync --extra dev
uv run python -m bingo
```

默认 `echo` 模型提供商不需要 API Key。如需连接真实模型，请在 `apps/server/config/config.yaml` 的 `model` 部分配置 OpenAI 兼容接口。

启动后可访问 `http://127.0.0.1:8000/docs`，或检查：

```powershell
Invoke-RestMethod http://127.0.0.1:8000/api/v1/health
```

### 3. 运行 Android 客户端

连接已开启 USB 调试的 Android 手机或模拟器：

```powershell
Set-Location ../..
./scripts/run_mobile.ps1
```

指定设备和服务端地址：

```powershell
./scripts/run_mobile.ps1 `
  -DeviceId emulator-5554 `
  -ApiBaseUrl http://192.168.18.133:8000
```

自托管部署可单独设置 HTTPS 基础地址和 API 前缀：

```powershell
./scripts/run_mobile.ps1 `
  -ApiBaseUrl https://example.com `
  -ApiPrefix /bingo/api/v1
```

## 开发检查

```powershell
Set-Location apps/server
uv run ruff check .
uv run pytest

Set-Location ../mobile
flutter analyze
flutter test
```

## 安全边界

- 密码使用带盐 `scrypt` 哈希，移动端会话令牌由 Android Keystore 加密保存。
- 对话、记忆和设备操作按已鉴权的用户 ID 隔离。
- 模型只能创建待处理的设备请求；实际操作由 Android 端在用户批准后执行。
- 生产环境必须使用 HTTPS；明文 HTTP 仅用于本地开发。

## 文档

- [系统架构](docs/architecture.md)
- [API 与通信协议](docs/protocol.md)
- [后台任务](docs/background-jobs.md)
- [一小时回访与次日早安](docs/proactive-greetings.md)
- [自定义伙伴与声音复刻](docs/custom-roles.md)
- [API 分层与地区信息](docs/api-and-location.md)
- [推送通知](docs/push.md)
- [工具扩展](docs/tools.md)
- [Qwen-Audio-Realtime 声音复刻指南](docs/voice-cloning.md)
