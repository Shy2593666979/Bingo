# Bingo A 版 Logo

沿用原小芽形象，使用确认的 A 版：白色主体、淡粉轮廓、绿色叶片和挥手表情。

- `apps/mobile/assets/images/bingo_logo.png`：淡粉底标准图标，同时用于 README。
- `bingo_logo.webp`：应用内默认品牌头像。
- `bingo_logo_foreground.webp`：透明底标识，用于开屏、登录及语音处理页面。
- `bingo_logo_foreground.png`：Android 自适应图标前景源文件。
- Android 12 的开屏资源保留系统裁切安全区，避免切掉叶片。

桌面图标由 `dart run flutter_launcher_icons` 生成。页面主色与开屏数据预加载逻辑保持不变。
