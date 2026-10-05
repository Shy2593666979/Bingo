# 接口分层与当前地区

## 分层

- `bingo/api` 只处理 HTTP 参数、鉴权依赖及传输适配，不直接查询数据库。
- `bingo/services` 承担业务编排、授权校验、事务与业务异常；`bingo/db` 保留模型和仓储。
- 普通 REST JSON 使用 `{"code":0,"message":"操作成功","data":...}`；错误保持原 HTTP 状态码，`code` 为对应状态码。参数错误不回传敏感输入。
- `204` 仍为空响应。WebSocket 消息、聊天 NDJSON、图片和音频二进制不套 JSON 包装。
- 手机网关读取新版包装，同时兼容旧版原始 JSON，便于先更新手机再升级服务。旧客户端不兼容新版 REST，发布时应同时更新。
- `services/asr.py`、`services/realtime_call.py` 是已有 WebSocket 传输代理，不承担 REST response 包装。

## 当前地区

- 完成首次资料设置后进入应用、以及应用从后台回到前台时，获取一次地区；不因页面跳转反复定位。
- 首次按 Android 系统流程申请前台定位权限，拒绝后不自动重复弹出。用户可在「我的 → 使用当前地区」主动重新开启，或到系统设置授权；没有后台定位权限。
- 在 Android 本机通过 Geocoder 将坐标转换为省、市、区县。原始坐标不上传、不存数据库、不写日志；定位与反查最多等待 20 秒，失败不编造地址。
- 本机地理编码服务依赖设备提供的服务和网络。缺少地理编码服务、关闭定位或反查不到区县时，不提供地区，也不影响聊天。真实手机需要授予定位权限并联网验证。
- `PUT /me/location` 只接收 `province`、`city`、`district`；`GET /me/location` 查询当前缓存；`DELETE /me/location` 清除缓存。三个接口均须登录。
- Redis key：`bingo:user:{user_id}:location`，有效期 24 小时，用户隔离。值包含省市区、拼接展示字符串和更新时间，不落 SQL。
- 直辖市去重：`北京市 + 北京市 + 海淀区 → 北京市海淀区`。普通市、县：`河南省濮阳市濮阳县`。
- 文本聊天和实时通话使用系统提示词模板中的 `用户当前位置：{current_location}`，与时间、时区等信息统一展示，不在上下文末尾拼接。获取成功时显示省市区县；缓存缺失/过期/Redis 故障时显示 `用户当前位置：暂未获取`，不编造地址。
- 「我的」可以关闭地区使用，停止定位并清空 Redis；断网无法立即清空时，下一次进入应用会重试清除。

## 兼容性验证

后端包含 JSON 包装、鉴权/参数错误、204 空响应、地区隔离/清除、提示词和分层边界测试；原有图片、音频和流式聊天测试继续运行。安卓包含新版/旧版 JSON 网关、定位权限失败与仅上报地区的桥接测试。

## 聊天中发送位置

与后台仅缓存三级地区不同，「聊天 → 加号 → 位置」只有用户确认发送后才把选中地点交给伙伴和聊天模型。搜索/手选地点不会覆盖 Redis 中的用户当前位置。

- 后端配置 `maps.api_key` 为高德 Web 服务 Key，或用 `BINGO_AMAP_API_KEY` 环境变量覆盖；`maps.timeout_seconds` 默认 15 秒。Key 只保存在服务器，不写入 APK、设计稿或 Git。
- `GET /locations/search?keywords=天安门&city=北京`：返回 `data.places`。
- `GET /locations/reverse?longitude=116.397&latitude=39.909&coordinate_system=GCJ-02`：返回 `data.location` 与周边 `data.places`；也支持 WGS84 并在服务端转换。
- `GET /locations/map?longitude=116.397&latitude=39.909&zoom=15`：须 Bearer 鉴权，返回 PNG，不套 JSON 包装。保留高德版权标识，内存缓存十分钟，每用户查询限流。
- 聊天请求增加可选 `location`，与图片互斥；原有事件格式不变。历史消息为 `message_type: location`，带同一 `location` 对象。服务端及手机本地数据库均保留位置字段。

示例聊天请求（坐标系固定 GCJ-02）：

```json
{
  "content": "",
  "location": {
    "name": "天安门",
    "address": "北京市东城区长安街北侧",
    "province": "北京市",
    "city": "北京市",
    "district": "东城区",
    "longitude": 116.397463,
    "latitude": 39.909187,
    "coordinate_system": "GCJ-02",
    "source": "poi",
    "precision": "point"
  }
}
```

模型接收用户角色的 `{"type":"location","location":{...},"caption":"..."}` JSON 文本；手机显示地点名称、地址和地图卡片。`source` 可为 `poi/current/map/user_shared_region`，`precision` 可为 `point/approximate/district`。仅发送区县时必须省份/区县齐全，省略经纬度，不能夹带精确坐标。地点精确地址不默认提取至长期记忆。

本功能不实时共享位置，不申请后台定位权限。

### 位置选择页与加载优化

- 选择页采用大地图、浮动取消/发送、中心定位针、重新定位按钮和底部搜索/附近地点列表；聊天消息卡片仍保留方案 A。
- Android 定位仅复用 30 秒内、符合精度条件且定位提供商仍开启的系统定位结果；没有有效缓存仍请求新位置，拒绝权限时可搜索。
- 同一账号、同一网关的上次地点只在内存预览两分钟；缓存不自动选中，刷新前不能发送，其他账号不会展示该预览。地图不在用户确认前自动当成当前位置上报。
- 后端复用高德 HTTPS 连接；地点搜索和逆地理编码结果缓存两分钟，缓存最多 256 条且仍限流。地图缩略图支持高度参数 `height=220..640` 和 `marker=false`，用于选择页，历史聊天卡片使用原参数不变。
- 原生动态地图接入 `com.amap.api:3dmap:10.0.600`，支持连续拖动与缩放；停下后防抖查询地址，旧查询结果不覆盖新选点。只有配置 Android Key 且设备为 ARM 架构时启用。未配置 Key、用户未同意高德隐私说明、x86 模拟器或地图加载超时时，退回可选点的静态地图，不伪装成原生 SDK 鉴权成功。
- 构建环境设置 `BINGO_AMAP_ANDROID_KEY`（也可用同名 Gradle property）。这是绑定包名及证书的 Android SDK Key，必须与后端 Web 服务 Key 分开；Android SDK Key 会随应用打包，必须在高德控制台限制包名和签名，不能作为服务器凭据使用。配置值不提交 Git。
- 包名 `com.example.bingo`；目前调试和 release 都使用已有 Android debug 证书，其 SHA-1 为 `51:BC:0E:0D:A8:F2:6F:41:2C:FE:B1:5D:A3:E5:9D:52:09:E2:63:F9`。未来换正式签名时须同步修改 Key 绑定。
- 初始化原生 SDK 前展示高德隐私说明，允许查看政策或拒绝，并只在同意后调用 SDK 隐私接口。正式上线还需核对完整隐私政策、SDK 披露、服务授权及账号配额。

本地公共地标实测：同一 WGS84 地点逆地理编码首次约 3.1 秒，缓存命中约 9 毫秒。这是单次本地后端测试，不代表手机定位到完成展示的端到端耗时。

当前标准原生地图 SDK 会增加包体积：ARM64 release 验证构建约 51.5 MiB，原先约 28.9 MiB。若坚持约 30 MB，需另行选择轻量地图实现，不能仅靠 ABI 拆分去掉当前 SDK 的原生库；未拿到 Android Key 前，此构建不能视为动态地图已通过真实手机鉴权。
