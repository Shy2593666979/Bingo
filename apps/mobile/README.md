# Bingo 移动端

连接同一局域网 Bingo 服务端的 Flutter Android 客户端。

## 前置条件

安装 Flutter，并通过 `flutter doctor` 完成 Android 开发环境检查。如果这个代码副本是在安装 Flutter 之前创建的，请先在仓库根目录初始化生成的 Android 文件：

```powershell
./scripts/bootstrap_mobile.ps1
```

## 使用热重载运行

在仓库根目录连接已授权的 Android 调试设备，并启动持久化开发会话：

```powershell
./scripts/run_mobile.ps1
```

运行期间：

- `r`：热重载 Dart 和 UI 修改
- `R`：热重启 Dart 应用
- `q`：停止应用

如需选择设备或显式修改服务端地址：

```powershell
./scripts/run_mobile.ps1 -DeviceId emulator-5554 -ApiBaseUrl http://192.168.18.133:8000
```

应用仅在本地开发环境允许明文 HTTP；生产环境必须使用 HTTPS。修改 Android 原生代码、Gradle 配置或插件依赖后，通常需要重新启动 `flutter run`。
