# Bingo

Bingo 是一个本地优先的个人助手原型。Flutter Android 客户端连接到运行在同一局域网计算机上的 FastAPI 服务。

## 仓库结构

```text
apps/mobile   Flutter Android 客户端
apps/server   FastAPI 智能体服务
docs          架构和通信协议
scripts       本地开发辅助脚本
```

## 快速开始

### 服务端

依赖环境：Python 3.12 和 `uv`。

```powershell
Copy-Item apps/server/config/config.example.yaml apps/server/config/config.yaml
./scripts/run_server.ps1
```

打开 `http://127.0.0.1:8000/docs`，或检查健康状态：

```powershell
Invoke-RestMethod http://127.0.0.1:8000/api/v1/health
```

启动服务端前，先启动持久化的本地后台任务代理：

```powershell
docker compose -f infra/docker/docker-compose.yml up -d
```

不配置 `redis.url` 时，开发环境仍可使用进程内代理，但服务端重启后，待处理任务和推荐内容会丢失。

默认的 `echo` 提供商不需要 API Key。若要使用兼容 OpenAI 的模型接口，请配置 `apps/server/config/config.yaml` 中的 `model` 部分。

### Android 客户端

连接一台已开启 USB 调试的 Android 手机，授权此计算机，然后在仓库根目录运行：

```powershell
./scripts/run_mobile.ps1
```

脚本会选择已连接的 Android 设备，并启动持久化的 Flutter 开发会话。Dart 或 UI 修改后按 `r` 热重载，按 `R` 完整重启 Dart 应用，按 `q` 停止。需要时可以覆盖默认参数：

```powershell
./scripts/run_mobile.ps1 -DeviceId emulator-5554 -ApiBaseUrl http://192.168.18.133:8000
```

自托管部署可以单独设置对外 API 路径，不需要修改仓库默认值：

```powershell
./scripts/run_mobile.ps1 `
  -ApiBaseUrl https://agentchat.cloud `
  -ApiPrefix /bingo/api/v1
```

服务端私有的 `config/config.yaml` 中也要使用相同的前缀。构建发布包时，通过 `--dart-define=API_BASE_URL=...` 和 `--dart-define=API_PREFIX=...` 传入这两个值。

辅助脚本会使用仓库计算机上的 JDK 17，不会修改全局 Java 安装。也可以通过 `-JavaHome` 指定其他 JDK。

手机和计算机必须处于同一网络，Windows 防火墙必须允许 TCP 8000。修改 Android 原生代码、Gradle 配置或插件依赖后，通常需要停止并重新运行命令。

## 开发检查

```powershell
cd apps/server
uv sync --extra dev
uv run ruff check .
uv run pytest
```

设计细节请参阅 [docs/architecture.md](docs/architecture.md) 和 [docs/protocol.md](docs/protocol.md)。中文的[声音复刻指南](docs/voice-cloning.md)记录了完整的 Qwen-Audio-Realtime 自定义声音流程。
