# Bingo 字体预览资源

用于 `../../bingo-font-options.html`，不修改移动端字体配置。

本地字体来自 Google Fonts，仅下载该预览使用的文字子集。不能把这些子集直接当作 APP 完整字库，否则未包含的汉字会回退到系统字体。正式接入 Flutter 时，需要取得完整 TTF/OTF 字库、保留授权文件，并检查包体积和布局。

| 显示名称 | 来源 | 授权 |
| --- | --- | --- |
| Noto Sans SC | https://fonts.google.com/noto/specimen/Noto+Sans+SC | SIL Open Font License 1.1 |
| Noto Serif SC | https://fonts.google.com/noto/specimen/Noto+Serif+SC | SIL Open Font License 1.1 |
| 霞鹜文楷（预览使用 LXGW WenKai TC） | https://fonts.google.com/specimen/LXGW+WenKai+TC | SIL Open Font License 1.1 |
| 站酷小薇体 | https://fonts.google.com/specimen/ZCOOL+XiaoWei | SIL Open Font License 1.1 |
| 站酷快乐体 | https://fonts.google.com/specimen/ZCOOL+KuaiLe | SIL Open Font License 1.1 |

每款字体的原始授权保存在同目录 `*-OFL.txt`。文楷方案这里只作视觉对比；正式接入简体中文 APP 时优先验证简体字库版本的字形覆盖。

系统默认方案使用浏览器和当前设备的字体，不能精确代表 Android 手机上现有默认字体。
