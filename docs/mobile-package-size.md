# Android 局域网安装包瘦身

2026-11-01 的原始通用 Release APK 为 201.97 MiB。

第一轮 ARM64 APK 为 **90.89 MiB（95,309,839 字节）**，减少 **55%**。

第二轮最终包为 **55.47 MiB（58,164,791 字节）**。保持四套字体原文件、
图片原尺寸和全部透明像素，图片 RGB 使用高质量 WebP；显示尺寸下最低 PSNR 为
42.165 dB。图片总大小为 11.14 MiB。角色介绍改为本地 AAC-LC 96 kbps，
全部 12 段约 1.20 MiB，随包提供，无下载等待。

第二轮额外验证：

- `scripts/optimize_mobile_assets.py --perceptual`，报告 `mobile-asset-optimization-v2.json`。
- `scripts/encode_onboarding_audio.py --ffmpeg <ffmpeg路径>`，报告 `mobile-audio-optimization.json`。
- 角色介绍重新按当前 12 个不同音色生成，来源指纹记录在 `onboarding-voice-sources.json`。
  `tests/test_onboarding_media.py` 校验角色音色、文案、WAV 母版和 AAC 成品，防止旧介绍混入。
- 本地 AAC 使用已有 Android MediaPlayer 解码，保留语音的临时音频焦点，
  切换卡片、离开页面、后台与焦点丢失时停止。
- 最新交付文件为 `../dist/Bingo-LAN-20261101/Bingo-LAN-arm64-compact.apk`；
  包内语音、字体、架构和局域网地址已核验，详情 `compact-report.json`。
- 最终版本在雷电逐张验证 12 张卡片播放，确认 Android AAC 解码正常；
  音频临时焦点和切至后台停止已检查，测试账号原状态已恢复。
  记录：开发阶段临时产物（已清理）。

本次保留全部功能、字体、角色语音和现有界面，调整资源打包方式：

- PNG 原图保留在项目中，运行时使用同尺寸、无损 WebP。
- `scripts/optimize_mobile_assets.py` 生成并逐像素验证 48 张 RGBA 图片，
  总大小从 67.31 MiB 降至 42.34 MiB。源图片均无 ICC 配置。
- `pubspec.yaml` 明确列举运行时图片，排除旧头像、旧锅/卡车气泡、未使用的
  设计参考图、旧背景图及启动器源图。四份字体仍通过字体声明打包。
- 服务端和已保存的 `.png` 头像标识保持兼容，由 `squareAvatarAsset` 转成对应 WebP 路径。
- 气泡 ID、透明边缘、插画裁切尺寸和表情文案保持不变。
- 用分架构参数构建 ARM64 包，防止第三方 SDK 的其他架构库混入。

构建命令（PowerShell，工作目录 `apps/mobile`）：

```powershell
$env:JAVA_HOME = 'D:/DevTools/jdk-17.0.20+8'
$env:BINGO_ALLOW_CLEARTEXT = 'true'
D:/DevTools/flutter/bin/flutter.bat build apk --release --no-pub --split-per-abi --target-platform android-arm64 --dart-define=API_BASE_URL=http://192.168.1.4:8000
```

输出 `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`。
这版用于 ARM64 安卓手机；雷电等 x86 模拟器需要支持 ARM64 转译，或者单独构建 x86 包。

资产体积与逐像素验证报告：`mobile-asset-optimization.json`。
交付 APK 的字节数、架构与 SHA256：`../dist/Bingo-LAN-20261101/slim-report.json`。

验证：头像、表情、外观、气泡、社区、新用户选择及相关页面共 34 项测试通过；
Flutter 静态分析无问题。原始 APK 保留用于对比。

已在支持 ARM64 转译的雷电模拟器覆盖安装并成功启动，账号与记录保留，
局域网请求成功。首页、聊天页和表情面板截图已对照，无缺图或布局变化；
截图位于 开发阶段临时产物（已清理）。
