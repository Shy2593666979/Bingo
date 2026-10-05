# C 手写字体试用版

> 当前状态（2026-10-05）：用户已选定系统默认字体，手写字库不再打包。本文为历史试用记录，原 APK 与备份保留；最新说明见 `font-system-build.md`。

## 原版本保留

- 开发分支：`ui/handwritten-font-c-20261004`。
- 原分支：`main`，未改动其提交历史，也未推送远端。
- 修改字体之前的完整工作区（含未提交文件和未跟踪文件）已经保存为 Git stash：`aea5416f7d42c8e4c1ab498857a0bee2d356aaa3`。
- 备份名称：`backup: before C handwritten font 2026-10-04`。本次使用 `apply` 恢复到新分支，没有 `pop`，备份仍然保留。不要清理这个 stash。
- 本次没有创建代码提交。回到原版前，先保存当前分支工作区，再切换分支并恢复该备份，避免覆盖后续修改。

## 字体方案

全局正文、标题、输入框和按钮使用霞鹜文楷简体中文完整版 v1.522，保持现有颜色、字号、布局和 Material 图标。HTML C 方案使用文楷 TC；手机采用同系列简体中文版本，保证简体聊天字形覆盖。

字体 SHA-256：`39ad71264b588165b469e35e6afb162a378dacd1f95348160240ba9038ac3009`。

默认使用手写方案。构建时加入 `--dart-define=BINGO_FONT_STYLE=system` 可以恢复原系统字体，不用删除手写方案。仅切换该参数仍会包含字库资源；彻底恢复原包体积需使用上述原版本备份。

## 手机构建

ARM64 release，构建号 6038，连接 `https://agentchat.cloud/bingo/api/v1`。保留现有签名配置和定位页实现；高德动态地图仍需单独 Android Key，与字体试用无关。完整中文字体与原生地图 SDK 会增加包体积，以构建产物实际大小为准。

产物：`apps/mobile/build/distributions/bingo-phone-arm64-release-v6038-wenkai-c.apk`。

- 实际 Android versionCode：8038（ARM64 ABI 构建号偏移）。
- 文件大小：66,779,914 字节，约 63.7 MiB / 66.8 MB。
- APK SHA-256：`56f724752f4fd9a05ad749933a4d333a32792b397521b3eeda75543156e46c5a`。
- APK 签名校验通过，沿用项目已有 Android debug 签名配置；这是 release 构建模式，不是新增正式分发证书。
- 完整字库、授权文件、公网 HTTPS 地址与 API 前缀均已核对。
- 移动端全量测试 81 项通过，原系统字体回退配置的 2 项主题测试通过。
