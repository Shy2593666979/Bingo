# 字体对比试用版

> 当前状态（2026-10-05）：用户已选定系统默认字体，APP 字库、切换页面和偏好读取已移除。本文保留为试用版历史记录；最新说明见 `font-system-build.md`。

设置入口：陪伴空间右上角用户头像 → 我的 → 应用设置 → 应用字体。

保留此前 HTML 中的七个方案：系统默认、清爽黑体、温柔手写、文艺宋体、轻巧小薇、活泼快乐、温柔混搭。混搭使用 Noto Sans SC 正文、霞鹜文楷标题与伙伴名称，不增加额外字库。默认仍是之前选定的温柔手写。

点击选项后即时应用，保存在手机本地偏好中；返回页面、重启与退出登录不会清除选择，不请求后端接口。保存失败时保留原选择并提示。未知或已移除的字体标识回退到默认方案，便于选定后精简字库。

## 资源

没有使用 HTML 中只包含预览文字的子集字体。正式字库来源与授权：

| 字库 | 来源 | 授权 |
| --- | --- | --- |
| LXGW WenKai Regular | 保留原 v1.522 完整简体字库 | assets/fonts/OFL.txt |
| Noto Sans SC Variable | https://github.com/google/fonts/tree/main/ofl/notosanssc | notosanssc-OFL.txt |
| Noto Serif SC Variable | https://github.com/google/fonts/tree/main/ofl/notoserifsc | notoserifsc-OFL.txt |
| ZCOOL XiaoWei Regular | https://github.com/google/fonts/tree/main/ofl/zcoolxiaowei | zcoolxiaowei-OFL.txt |
| ZCOOL KuaiLe Regular | https://github.com/google/fonts/tree/main/ofl/zcoolkuaile | zcoolkuaile-OFL.txt |

四款新增字库原文件总计 50,726,588 字节。全部保留作者发布的字形，不裁剪聊天文字；五个字库均覆盖当前 Dart 源码中的汉字。字库本身未包含的罕见字由系统回退，不承诺覆盖所有 Unicode 汉字。图片、Material 图标、地图内高德文字与系统权限弹窗不随应用字体切换。

各字体选项复用统一主题颜色、字号与布局。系统字体预览不继承当前选中的自定义字体；每个选项都用自己的字体显示样例。已加入存取、选择生效、混搭主题和保存失败回退测试，Flutter 全量 87 项通过，静态分析无问题。

## 打包

本轮提供字体全集试用包，包体积会高于单字体版，选定后再移除未使用的字体资源和注册，不提前删除任何方案。

- 手机 ARM64 release：`apps/mobile/build/distributions/bingo-phone-arm64-release-v6050-font-options.apk`，实际 Android versionCode 8050，签名校验通过。
- 文件大小 74,526,945 字节，74.5 MB / 71.07 MiB；SHA-256 `2bf9606e61db479ece572c0a673d0ee9ad2851eaad16558d252fa9555d29cc80`。
- 模拟器 debug：`apps/mobile/build/distributions/bingo-emulator-debug-v6049-font-options.apk`，已安装；实际验证从温柔手写切到清爽黑体，强制停止再打开后，设置仍显示清爽黑体。验证结束恢复原先温柔手写，字体选择页保持打开供体验。
- APK 内已核对五个完整字体文件与对应注册；混搭与系统默认不重复打包字库。旧 v6038 单字体手机包未覆盖。

模拟器 debug 使用本地后端与 ADB 8000 端口反向转发，包含开发验证用的 JS 地图配置；手机 ARM64 release 使用公网 HTTPS `/bingo/api/v1`。生产 JS 地图安全代理尚未部署，release 不打包 JS 安全密钥，手机位置页保留静态地图回退，不把开发地图密钥方案作为生产方案。
