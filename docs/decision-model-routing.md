# 群聊决策模型

实现文件：`apps/server/bingo/agent/decision_model_client.py`。
使用项目已有的 `httpx` 直接 POST System One，不依赖 DashScope SDK，
也不经过普通聊天模型的 Responses / Chat Completions 适配器。

在服务端配置中增加以下内容，并在运行服务的环境中设置 `BINGO_DECISION_API_KEY`：

```yaml
decision_model:
  enabled: true
  endpoint: https://你的业务空间域名/compatible-mode/v1/systemone
  model: decision-model-preview
  timeout_seconds: 3
```

域名及 API Key 必须对应实际开通的业务空间和地域。此处不自动复用通用模型密钥。
示例配置默认关闭，以免没有凭据时影响现有服务。开启后配置不完整会在启动时报错。

每次只提交一个 `choice` 问题，选项为当前有效成员 ID、`wait`、`finish`。
明确要求回应的成员尚未答复时，文字群聊只允许从未回应的目标中选择。
结果必须属于提交的选项，置信度不作为未经校准的拒答阈值。
HTTP 超时、错误响应或无效选项会回退一次普通模型选人，仍校验选项；
取消异常直接传播，不启动兜底请求。两种模型均失败时不擅自随机分配发言者。

启用后，文字群聊的默认 independent_agents 路径会逐个选人、完整发布、
再读取最新已完成消息进行下一次决策。原有运行预算、失效检查和禁用 AI 互聊设置继续生效。
legacy_dispatcher 模式保留原行为。

电话通过相同客户端选人；保留原有下一段预生成、generation / episode 失效保护、
播放回执和连续 30 次自主发言上限。只替换选人，不替换角色生成、ASR、TTS 或音色。

测试使用 HTTP MockTransport 和本地服务测试夹具，不消耗真实模型额度。
上线前需用真实凭据验证接口授权、响应结构、决策质量及端到端延迟分位数。
