# 工具

服务端工具位于 `apps/server/bingo/tools`。

```text
tools/
  base.py          BaseTool、ToolContext、ToolResult
  registry.py      注册、定义、校验、分发
  web_search.py    web_search
  weather.py       weather_get
  device_alarm.py  device_alarm_create
```

每个工具都定义稳定的 snake_case 名称、面向模型的描述、JSON Schema 参数对象以及异步 `run` 方法。`ToolContext` 携带已认证用户、数据库会话和时区。工具返回模型可读的 `ToolResult`；设备工具还可以返回请求审批的客户端事件。

只能在 `tools/__init__.py` 的 `create_tool_registry()` 中注册新工具。注册表会拒绝重复名称，并将无效参数和执行失败转换为模型可读的结果，因此单个工具可以专注于参数校验和自身领域逻辑。

当前工具：

- `web_search(query, max_results?)`：不使用浏览器的 DuckDuckGo Lite 搜索。
- `weather_get(location, date?)`：Open-Meteo 地理编码和天气预报数据。
- `device_alarm_create(scheduled_at, label, recurrence?)`：创建按用户隔离的待处理 Android 操作，不会直接调用设备。
