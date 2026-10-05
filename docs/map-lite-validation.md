# 高德轻量地图验证（2026-10-05）

## 范围

只在 `.tmp/map-lite-validation/mobile` 的隔离副本中试验。当前 `ui/handwritten-font-c-20261004` 分支的应用代码、原 6038 手机包、服务器配置与部署均未替换。本轮不把试验包作为可用手机发行版交付。

## SDK 来源

官方轻量地图下载页：https://developer.amap.com/api/lightweight-android-sdk/download

该页当前发布轻量地图 1.3.2、搜索 9.7.4、定位 6.4.9 的合包。概述和部分接入示例仍描述较旧版本，应以实际下载文件核对，不应据旧概述推断它没有更新。

- 官方下载：`https://a.amap.com/lbs/static/amap_3dmap_lite/Lite3DMap.zip`。
- ZIP MD5：`8dbdd267ac70d7826983166621718b26`，与官方下载页一致。
- JAR：`Lite3DMap_1.3.2_AMapSearch_9.7.4_AMapLocation_6.4.9_20250521.jar`，1,894,862 字节，没有 `.so` 原生引擎库。
- JAR SHA-256：`94329af7141a920bfc63aa4102946db91a011faeb058190602a378bb9cbd47e4`。

## 已验证

隔离副本把 `3dmap:10.0.600` 替换为该官方 JAR，使用 Android WebView 和 SDK 的 `AMapWrapper / IAMapWebView`，保持 Flutter 地图通道与位置选择页契约，保留完整文楷字库和同一公网 API 地址。

| 项目 | 结果 |
| --- | --- |
| Android ARM64 release 编译（现有 AGP 9.1 / target 36） | 通过 |
| APK 签名校验 | 通过，沿用原签名 |
| 原完整地图手机包 | 66,779,914 字节 / 63.69 MiB |
| 轻量 SDK 隔离测试包 | 44,182,510 字节 / 42.14 MiB |
| 实际减少 | 21.55 MiB |
| 测试包剩余 AMap/AutoNavi 原生 `.so` | 0 |
| 完整文楷字体压缩占用 | 12.16 MiB，未裁剪 |
| 位置与主题 Flutter 测试 | 10 项通过（不等于 SDK 真实地图渲染通过） |

公共地标接口验证，调用现有 MapsService 而非手机端动态地图：搜索天安门返回 15 个结果，单次约 3,476 ms；逆地理编码约 143 ms，返回区县及 15 个附近地点；重复查询缓存命中小于 1 ms。测试只使用公共地标，不获取设备位置，不发送用户聊天消息，不暴露服务器 Key。

## 尚未验证，不能据此发布

- 当前没有高德 Android SDK Key，试验构建保留不可用时回退静态地图的逻辑，不能证明 SDK 鉴权或连续拖动、缩放的实机体验。
- 当前 ADB 没有连接的模拟器/手机，没有安装试验包、没有实测 WebView 地图首屏、冷启动/热启动及弱网耗时。不能宣称轻量版加载一定更快。
- 官方 JAR 内存在含 HTTP 加载路径的旧模板；原型没有启用混合内容或广泛文件跨源权限。正式接入前要确认 SDK 的 HTTPS 配置和实际网络行为，不能为了白屏直接放开全局明文流量。
- 需验证 WebView 初始化、隐私授权、中心位置更新、生命周期与错误回退，再决定是否替换现有原生地图。
- 保留完整手写字体时仍约 42 MiB，不是 30 MiB。若恢复原系统字体并去掉字库资源，从本次压缩占用推算可能接近 30 MiB，但本轮没有构建该组合，不作为实测结果。

## 下一步需要的 Key

官方轻量 Android SDK 使用 Android 平台 Key：包名 `com.example.bingo`，当前签名 SHA-1 `51:BC:0E:0D:A8:F2:6F:41:2C:FE:B1:5D:A3:E5:9D:52:09:E2:63:F9`。它不是后端 Web 服务 Key。

若改走直接 WebView + JS API 2.0 的另一条方案，则需要 Web端（JS API）Key 和 `securityJsCode`（正式环境优先使用安全代理）。这是另一种接入方式，不能把已有 Web 服务 Key 或 Android Key 随意混用。相关官方说明：https://developer.amap.com/api/javascript-api-v2/getting-started

Key 不写入 Git。拿到 Android Key、连接测试设备后，优先补齐真实地图验证，再决定是否正式切换。

## 提供 Android Key 后的运行验证

2026-10-05 已收到 Android Key，并仅存入 `.tmp/map-lite-validation/android-key.local`；该路径被 Git 忽略。Key 未写入本文件、应用源码或服务器配置。模拟器仍使用原包名与原签名，测试活动只浏览北京公共地标，不请求设备定位，不发送聊天消息。

- 测试设备：已有 LDPlayer 模拟器，WebView `146.0.7680.119`。临时安装了隔离副本的 debug 测试 APK，原手机 release 文件未覆盖。
- 最初 SDK 本地 `file://` 页面发生跨域错误，截图为空白。其 `MAP_READY` 初始化回调仍在约 2.8 秒触发，因此初始化回调不是底图渲染成功证据。
- 隔离测试活动尝试 HTTPS 本地来源、受限本地脚本资源映射、严格来源响应头和 `upgrade-insecure-requests`。没有启用文件的通用跨域权限，没有放开混合内容或全局明文流量。
- 修正后不再出现原先的跨域及混合内容报错；缩放按钮和拖动产生不同坐标、zoom 的回调。但底图仍然灰白，尚不满足可用地图验收。
- 通过测试 WebView 自身的调试接口核对：Worker 地图数据请求返回 `INVALID_USER_KEY / 10001`；其请求 Key 不是本次提供的 Android Key，也没有 SDK 签名参数。官方 JAR 内包含固定默认 Key 的地图脚本，当前实验接入的数据请求链路没有正确使用 Android SDK 鉴权。不能据此断言用户新创建的 Android Key 无效，也不能据此宣称 SDK 已通过鉴权。
- 调整实验页的 SDK 脚本入口 Key 后，Worker 数据请求仍然没有正确接入 Android SDK 鉴权。原因仍需进一步确认，可能涉及旧资源配置与当前 WebView 请求处理；不能仅按内置 Key 文本替换后发布。

本轮结论：体积及编译验证通过，真实动态地图显示验证未通过。保留现有应用方案，不提交或发布轻量 SDK 替换。当前试验截图、调试结果和源码保存在 `.tmp/map-lite-validation`，不将其初始化耗时作为可用地图加载速度对外报告。

替代路线是直接 WebView + 正式 JS API 2.0，使用本项目单独申请的 Web端（JS API）Key 与安全配置，避免依赖轻量 SDK 的内置脚本默认 Key。该路线尚未完成鉴权验证，不保证仅凭更换方案即可解决全部兼容性问题。

## JS API 2.0 独立验证

2026-10-05 收到 Web端 Key 和安全密钥后，在同一隔离副本中新增 `JsMapProbeActivity`，直接通过 Android WebView 加载官方 HTTPS JS API 2.0，不再使用轻量 SDK 的页面和请求拦截。凭据仅存放在 Git 忽略的 `.tmp/map-lite-validation/js-credentials.local`，测试页面仅生成到隔离副本。正式上线应使用安全代理，不能把此次测试页内的安全密钥配置直接当作生产方案。

- 同一模拟器实际截图已经显示道路、建筑、中文地点标签及高德版权标识，不再灰白。
- 单次首次页面 `complete` 回调耗时 2,693 ms；已有真实底图截图佐证，但不是多轮冷启动均值，也不能据此认定比原生更快。
- 放大按钮使 zoom 从 15 变为 16；ADB 模拟手指拖动后，中心从公共地标坐标变为 `116.395653, 39.910789`，收到 `moveend`；重新定位按钮可以恢复公共地标中心及 zoom 15。
- 官方 JS 插件地点搜索返回 `complete` 和 5 个结果，逆地理编码返回 `complete` 及北京市东城区的地址。未读取设备定位，未发送用户消息。
- 本次只验证内嵌地图技术路线，不等同于 Flutter 选点页面、当前位置获取、聊天发送与服务器安全代理已经完成集成。没有生成新的手机 release 包，也没有替换正式应用代码。

截图与机器结果仅保存在被忽略的 `.tmp/map-lite-validation/js-probe.png`、`js-probe-results.json`。测试后恢复模拟器原 v6036 应用，保留应用数据，移除 WebView 调试端口转发；原 v6038 手机发行包保持不变。
