# 发送位置：方案 A 接入与验证

## 本次验证（2026-10-04）

- 使用用户提供的 Key 请求高德 Web 服务，仅测试北京公共地标，不采集用户位置。
- 逆地理编码：HTTP 200，`status=1`、`infocode=10000`，返回北京市、东城区、街道、地址以及 30 个周边 POI。直辖市的 `city` 返回空数组，接入时需规范化为北京市，展示地址避免重复城市名。
- 地点搜索：HTTP 200，`status=1`、`infocode=10000`，返回天安门、天安门广场、天安门东地铁站及坐标。
- 静态地图：HTTP 200，返回 PNG；设计稿保留完整原图和版权标识。
- Chat Completions / Responses 序列化兼容位置 JSON 文本；服务端测试验证位置持久化、历史上下文及流式协议。
- 已实现安卓与服务端完整位置消息链路。模拟器实测定位、附近地点、搜索天安门、发送地图卡、打开详情；真实模型已能回复分享的地点。

## 设计稿

打开 `bingo-location.html`，可比较三套卡片，也可点击加号、选择地点、发送、查看详情。

1. A 经典地图卡：地点名称、地址在上，地图在下；推荐。
2. B 地图优先：地图在上，地点信息在下。
3. C 轻量地点卡：地点摘要与定位图标，地图放进详情。

都使用已选方案 A 的浅薄荷颜色。原型离线运行，不包含 Key，不定位，不调用接口，AI 回复只是明确标注的占位示例。

## 已选方案 A

- 加号菜单增加「位置」。用户进入选择页，获取当前位置、查找附近地点或搜索其他地点，确认后才发送。拒绝定位仍可搜索；定位超时、地址解析失败、缩略图失败分别处理。
- 普通系统定位和高德 Web 服务可以组合使用：GPS / WGS84 坐标先经官方接口转换为 GCJ-02，再逆地理编码和生成缩略图。没有精确定位授权时不伪装成精确坐标。
- 选择页已调整为微信式大地图与底部地点列表，取消/发送浮在地图上。原生高德动态地图已接入，但需另配 Android Key 并在 ARM 手机实测鉴权；当前没有该 Key，不声称动态地图已验证。缺少 Key 或 x86 模拟器使用静态地图回退；聊天地图卡片不变。
- 保留既有 SSE / WebSocket 格式，给聊天请求和消息响应增加可选 `location` 数据。位置消息使用独立类型与字段，不根据普通聊天字符串猜测 JSON。旧消息与旧客户端继续兼容。
- 服务端 schema 校验坐标范围、坐标系、字段长度；Services 负责规范化、持久化、地图缓存和模型输入转换；API 层仅鉴权与响应。用 `json.dumps(..., ensure_ascii=False)` 转成用户角色的 JSON 文本，不把位置内容提升成系统指令。
- 服务端消息表、本地数据库及历史同步均保存位置字段；聊天列表与伙伴详情显示专用卡片，而不是原始 JSON。模型历史中的位置数据也按相同规则恢复。
- 发送 POI / 手选地点不意味着用户当前在那里，因此不自动覆盖原先 Redis 三级「用户当前位置」。只发一次静态位置，不后台实时追踪；精确地址和坐标不默认提取到长期记忆。
- Web 服务 Key 放后端环境或未跟踪配置，不提交 GitHub，不写进 HTML / APK。缩略图返回内部鉴权资源，不暴露带 Key 的外部 URL；校验消息归属，限制搜索 / 地图请求频率、缓存与费用。
- 用户明确发送精确位置时再传给当前聊天所用的模型服务；提供仅发送区县选项。位置记录随消息保存；地图为公共地点缩略图，仅内存缓存十分钟，不保存用户绑定的地图文件。

## 实测截图

- [选择位置](assets/ui-audit/location-picker-a.png)
- [聊天中的方案 A 地图卡](assets/ui-audit/location-chat-a.png)
- [位置详情](assets/ui-audit/location-detail-a.png)
- [新版大地图选择页（模拟器静态地图回退）](assets/ui-audit/location-picker-wechat-style.png)

截图只含 APP 内容，不包含模拟器边框。

## 官方资料

- [逆地理编码](https://developer.amap.com/api/webservice/guide/api/georegeo)
- [地点搜索](https://developer.amap.com/api/webservice/guide/api/search)
- [静态地图](https://developer.amap.com/api/webservice/guide/api/staticmaps)
- [坐标转换](https://developer.amap.com/api/webservice/guide/api/convert)
- [Android 定位 SDK Key](https://developer.amap.com/api/android-location-sdk/guide/create-project/get-key/)

上线前还需核对账号配额与适用授权。Key 已在聊天中提供，正式部署建议重新生成并限制可调用来源。
