# Bingo 服务端

用于本地开发的 FastAPI 服务。将 `config/config.example.yaml` 复制为 `config/config.yaml`，然后在当前目录运行：

```powershell
uv sync --extra dev
uv run python -m bingo
```

`config/config.yaml` 按组件组织配置。默认模型提供商是 `echo`；连接真实模型时，将 `model.provider` 设置为 `openai_compat`，并填写接口地址、密钥和模型。只有当配置文件位于默认位置之外时，才需要设置 `BINGO_CONFIG_FILE`。如果本地配置文件不存在，Bingo 会使用带有安全默认值的 `config/config.example.yaml`。

推送通知默认关闭。关于个推和小米/OPPO/vivo 离线通道的配置，请参阅 [`../../docs/push.md`](../../docs/push.md)。

运行日志默认写入 `logs/bingo.log` 和 `logs/access.log`。日志使用北京时间，每天轮换，并保留 14 天。可以在 `config/config.yaml` 的 `logging` 部分配置；如果生产环境由 Docker 或 systemd 收集标准输出，请将两个文件名都设置为 `null`。请求日志不会包含查询字符串或请求体，业务事件必须使用 `bingo.services.logging.log_event` 暴露的安全字段。
