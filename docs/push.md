# Android 推送

Bingo 使用个推 REST API V2 作为统一的服务端推送提供商。Android 客户端包含个推以及小米、OPPO、vivo 离线通道适配器。配置凭据前，推送功能处于关闭状态。

## 所需账号

发布前，确定最终的 Android 应用 ID 和签名证书。在个推以及所需的各厂商控制台创建相同的应用，然后在个推控制台配置厂商凭据。包名和签名证书必须与已安装的 APK 匹配。

官方配置参考：

- 个推 Android：<https://docs.getui.com/getui/mobile/android/overview/>
- 个推厂商通道：<https://docs.getui.com/getui/mobile/vendor/vendor_open/>
- 个推厂商 SDK：<https://docs.getui.com/getui/mobile/vendor/androidstudio/>
- 个推 REST API V2：<https://docs.getui.com/getui/server/rest_v2/push/>

## Android 构建配置

将以下值放入用户级 Gradle 属性文件 `%USERPROFILE%\.gradle\gradle.properties`。不要提交凭据。

```properties
BINGO_GETUI_APP_ID=
BINGO_XIAOMI_APP_ID=
BINGO_XIAOMI_APP_KEY=
BINGO_OPPO_APP_KEY=
BINGO_OPPO_APP_SECRET=
BINGO_VIVO_APP_ID=
BINGO_VIVO_APP_KEY=
```

不设置 `BINGO_GETUI_APP_ID` 构建 APK 时，推送功能会保持关闭，应用仍然可以正常使用。只有在用户接受应用隐私政策后才初始化 SDK；生产发布流程必须在发布前包含这一步授权。

## 服务端配置

在 `apps/server/config/config.yaml` 的 `push` 部分设置以下值：

```yaml
push:
  provider: getui
  android:
    channel_id: bingo_companion
    channel_name: Bingo 陪伴消息
  getui:
    app_id: ""
    app_key: ""
    master_secret: ""
```

`push.getui.master_secret` 只能保存在服务端，绝不能放入 APK。

## 送达语义

### 不配置厂商通道的真机测试

可以先只配置个推凭据和 Android 的 `BINGO_GETUI_APP_ID`，不申请 OPPO 等厂商通道。登录后允许通知权限，并在手机系统允许的情况下开启自启动、允许后台运行和放宽电池限制，然后分别测试前台、后台和锁屏消息。系统设置只能改善连接保持，不能保证应用被杀掉后的实时送达；没有厂商通道时，离线消息会等待个推连接恢复，且受消息有效期限制。

当前基础通知点击后打开应用，再由应用同步主动消息；不直接跳转到指定伙伴，也不代表可以在后台自动接通语音电话。个推接口接受消息不等于手机已展示通知，需要真机验收。

服务端会先保存主动消息，再为每台活跃设备创建一条发件箱记录。发送失败后会在 30 秒、5 分钟、30 分钟、2 小时和 6 小时后重试。打开应用时仍会同步未确认的消息，因此推送只是提醒渠道，不是事实来源。

后台运行和应用已终止时，请使用厂商通知消息。早安问候等类似内容必须使用厂商的运营消息类别；不要为了绕过配额规则而将其归类为私聊消息。
