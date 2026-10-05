# 系统默认字体精简版

按用户选择恢复系统默认字体，不指定自定义 `fontFamily`，标题、正文、表单与按钮跟随手机字体。保持颜色、字号和其他现有功能不变。

已移除五款 APP 字库、pubspec 字体与授权资产注册、设置中的字体切换入口、字体偏好读取与写入接口；旧版保存的字体标识不再读取，覆盖安装即可使用系统字体，不需要清除账号或聊天记录。Material 图标字体仍然保留，不属于可删除的正文试用字体。

为保留回退条件，字库及授权文件移至 Git 忽略的 `.tmp/font-options-backup-20261005`，不在 APP 资源目录，不进入新 APK。旧单字体与字体全集发行包未覆盖，HTML 对比页面也保留。

Flutter 全量测试 83 项通过，静态分析无问题。构建与原字体全集使用相同 ARM64 release 配置和公网 HTTPS `/bingo/api/v1`，仅比较字体精简效果；地图生产安全配置未变，手机仍保留静态地图回退，模拟器继续使用开发 JS 地图配置。

原字体全集包：74,526,945 字节 / 74.5 MB / 71.07 MiB。其中五个正文 TTF 在 APK 内压缩后共占 44,062,560 字节。

## 实际产物

- 手机 ARM64 release：`apps/mobile/build/distributions/bingo-phone-arm64-release-v6052-system-font.apk`，Android versionCode 8052，签名校验通过。
- 新包 30,452,440 字节 / 30.45 MB / 29.04 MiB，比字体全集包减少 44,074,505 字节 / 44.07 MB。
- SHA-256：`be05cc5f661f8ee9398fcb223c260113880e6eefefc228db9a642477f6ce9412`。
- APK 中没有正文 TTF 和 `assets/fonts` 资源；FontManifest 仅注册 `MaterialIcons`，确认不是仅修改显示字体而仍保留大字库。
- 模拟器安装 debug 6051，覆盖安装保留账号与聊天数据。实际截图显示系统字体，设置页面不再显示字体切换入口；本地服务连接正常。
- 模拟器产物：`apps/mobile/build/distributions/bingo-emulator-debug-v6051-system-font.apk`。
