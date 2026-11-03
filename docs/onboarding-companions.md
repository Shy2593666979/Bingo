# 新用户搭子选择 · C 版

实现参照 开发阶段临时产物（已清理） 的 C 方案。

## 行为

- 注册 → 完善个人资料 → 搭子选择 → 首页。未完成选择的账号重新登录后回到选择页。
- 12 位默认角色横向卡片，滑动仅浏览。点击添加可以多选，再点取消；底部头像也可移除。
- 至少选择一位才能继续。保存失败保留本页选择并允许重试。
- 当前卡片稳定后播放介绍；换卡、静音、后台和退出停止上一段。支持重听。
- 首页和角色列表只展示该账号选择的默认搭子及其自建、社区添加的搭子。
- 旧账号保留原有角色、对话和资料，不强制重新选择。

## 数据与兼容

新版 App 注册发送 `companion_selection: true`。旧客户端未发送该字段时沿用原有默认角色列表。
新增 `users.selective_companions`、`users.companion_selection_complete` 和
`user_companions(user_id, role_id)`；已有 SQLite 数据会自动补列，旧账号默认已完成。

`GET /onboarding/companions` 返回可选默认模板；`POST /onboarding/companions`
提交 `role_ids`。至少 1 位，最多 12 位，禁止重复或无效角色。一次事务保存选择并设置首位角色；
完成后的同集合重试幂等，不同集合返回 409。未选默认角色不能通过直接 ID 进入聊天或群聊。
用户自建草稿仍可编辑。

## 语音

`apps/mobile/assets/onboarding/` 包含介绍文本、WAV 母版和 12 段本地 AAC-LC。
安装包仅包含文本和 AAC，24 kHz 单声道、96 kbps，通过 Android MediaPlayer 播放。
使用当前各角色配置的真实音色预生成，进入页面无需下载或等待实时合成。
当前 12 位角色分别使用不同音色，HTML 预览的 WAV 也已同步更新。
音色与文案来源指纹记录于 `docs/onboarding-voice-sources.json`；
服务端 `tests/test_onboarding_media.py` 校验配置、母版和压缩成品，防止介绍录音过时。

## 验证

- Flutter 静态分析无问题；新选择页及首页、消息列表、角色页、群聊语音相关测试 17 项通过。
- 服务端验证覆盖选择校验、重试、重新登录、未选角色权限、自建角色兼容与旧 SQLite 升级。
- 雷电模拟器安装验证：选择甜甜及暖暖，接口和首页均仅有两位；重启后保留。
- 设备音频记录确认 AudioTrack 启动，24 kHz 单声道。
