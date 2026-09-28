# Qwen-Audio-Realtime 声音复刻操作指南

本文记录 Bingo 项目为 `qwen-audio-3.1-realtime-plus` 创建角色音色的完整流程，包括准备音频、临时发布公网地址、调用阿里云百炼接口、验证音色、写入角色数据库和清理临时文件。

参考文档：

- [阿里云百炼：声音复刻](https://help.aliyun.com/zh/model-studio/voice-cloning-user-guide)
- [阿里云百炼：声音复刻 HTTP API](https://help.aliyun.com/zh/model-studio/voice-clone-design-http-api)
- [Qwen-Audio 实时语音对话模型](https://help.aliyun.com/zh/model-studio/qwen-audio-realtime-user-guides)

## 1. 工作流程

```text
本地 WAV 音频
    ↓
转换为百炼可访问的临时 HTTPS URL
    ↓
调用 voice-enrollment/create_voice
    ↓
获得 voice_id
    ↓
通过 Realtime session.update 验证
    ↓
写入 roles.voice
    ↓
关闭公网通道并删除临时副本
```

声音复刻接口不能直接读取 `D:\...\xxx.wav` 之类的本地路径。对于 Qwen-Audio-Realtime，`input.url` 必须是阿里云服务器可以直接下载、无需登录或额外请求头的公网 HTTP/HTTPS 地址。

## 2. 准备音频

Qwen-Audio-TTS 和 Qwen-Audio-Realtime 的主要要求如下：

| 项目 | 要求 |
| --- | --- |
| 格式 | 16-bit WAV、MP3 或 M4A |
| 推荐时长 | 10～20 秒 |
| 最大时长 | 60 秒 |
| 文件大小 | 不超过 10 MB |
| 采样率 | 不低于 16 kHz |
| 声道 | 单声道或双声道，双声道只处理首声道 |
| 内容 | 至少 5 秒连续清晰人声，避免背景音乐、噪音和其他说话人 |
| 语言 | 支持中文及多种其他语言 |

本项目本次使用的是 24 kHz、单声道、16-bit PCM WAV。

可以用下面的脚本检查 WAV：

```powershell
@'
import wave
from pathlib import Path

for path in Path(r"D:\Python-Project\新建文件夹").glob("*.wav"):
    with wave.open(str(path), "rb") as audio:
        duration = audio.getnframes() / audio.getframerate()
        print(
            path.name,
            f"{duration:.2f}s",
            f"{audio.getframerate()}Hz",
            f"{audio.getnchannels()}ch",
            f"{audio.getsampwidth() * 8}bit",
        )
'@ | python -
```

## 3. 设置 API Key 和业务空间地址

不要把真实 API Key 写入脚本或提交到 Git。当前 PowerShell 会话可以这样设置：

```powershell
$env:DASHSCOPE_API_KEY = "sk-替换为你的百炼APIKey"
$env:BAILIAN_WORKSPACE_ID = "llm-82csv4ok6e6xu5cp"
```

北京地域接口地址为：

```text
https://{WorkspaceId}.cn-beijing.maas.aliyuncs.com/api/v1/services/audio/tts/customization
```

本项目使用的完整域名是：

```text
https://llm-82csv4ok6e6xu5cp.cn-beijing.maas.aliyuncs.com
```

注意：`WorkspaceId` 是域名前面的 `llm-82csv4ok6e6xu5cp`，不是包含地域后缀的完整域名。

## 4. 将本地音频临时发布到公网

### 4.1 测试方法：LocalTunnel

这是本次实际走通的方法，适合临时测试。LocalTunnel 是第三方公网转发服务，真实或敏感人声建议改用下一节的阿里云 OSS。

先建立一个临时目录，并将文件复制为纯英文文件名。英文文件名可以避免中文 URL 编码或终端编码问题。

```powershell
$publicDir = "D:\Python-Project\Bingo\.tmp\voice-clone\public"
New-Item -ItemType Directory -Force -Path $publicDir | Out-Null

Copy-Item -LiteralPath "D:\Python-Project\新建文件夹\男朋友.wav" `
  -Destination "$publicDir\boyfriend.wav"
Copy-Item -LiteralPath "D:\Python-Project\新建文件夹\家长.wav" `
  -Destination "$publicDir\parent.wav"
Copy-Item -LiteralPath "D:\Python-Project\新建文件夹\老师.wav" `
  -Destination "$publicDir\teacher.wav"
Copy-Item -LiteralPath "D:\Python-Project\新建文件夹\小孩.wav" `
  -Destination "$publicDir\child.wav"
Copy-Item -LiteralPath "D:\Python-Project\新建文件夹\同事.wav" `
  -Destination "$publicDir\colleague.wav"
```

打开第一个终端，在临时目录启动只监听本机的 HTTP 服务：

```powershell
Set-Location "D:\Python-Project\Bingo\.tmp\voice-clone\public"
python -m http.server 8765 --bind 127.0.0.1
```

保持第一个终端运行，再打开第二个终端启动 LocalTunnel：

```powershell
npx --yes localtunnel --port 8765
```

命令会返回类似下面的随机 HTTPS 地址：

```text
your url is: https://example-name.loca.lt
```

男朋友音频的公网地址就是：

```text
https://example-name.loca.lt/boyfriend.wav
```

提交复刻前先验证 URL。浏览器直接下载可以作为初步检查，也可以执行：

```powershell
@'
import requests

url = "https://example-name.loca.lt/boyfriend.wav"
response = requests.get(url, timeout=30)
print(response.status_code)
print(response.headers.get("content-type"))
print(len(response.content))
print(response.content[:4])
'@ | python -
```

正常结果应满足：

- HTTP 状态码为 `200`；
- Content-Type 为 `audio/wav` 或其他正确音频类型；
- WAV 文件前四个字节为 `RIFF`；
- 返回长度与本地文件大小基本一致。

### 4.2 推荐方法：阿里云 OSS 临时 URL

正式使用或音频包含真实个人声音时，建议使用阿里云 OSS：

1. 创建与百炼相同或临近地域的私有 Bucket。
2. 上传待复刻音频，例如 `voice-clone/boyfriend.wav`。
3. 为该对象生成有效期 15～30 分钟的 HTTPS 签名 URL。
4. 确保该 URL 在无登录、无自定义请求头的环境中可以直接下载。
5. 将签名 URL 传给百炼的 `input.url`。
6. 复刻完成后删除 OSS 对象，或等待签名 URL 自动过期。

不要为了方便长期公开 Bucket，也不要使用永久公开的人声音频 URL。

## 5. 创建复刻音色

`prefix` 是音色名称前缀，只允许英文字母和数字，最多 10 个字符。下面是本项目使用的前缀：

| 角色 | prefix |
| --- | --- |
| 男朋友 | `boyfriend` |
| 家长 | `parent` |
| 老师 | `teacher` |
| 小孩 | `child` |
| 同事 | `colleague` |

创建男朋友音色：

```powershell
@'
import json
import os
import requests

workspace_id = os.environ["BAILIAN_WORKSPACE_ID"]
api_key = os.environ["DASHSCOPE_API_KEY"]
endpoint = (
    f"https://{workspace_id}.cn-beijing.maas.aliyuncs.com"
    "/api/v1/services/audio/tts/customization"
)

response = requests.post(
    endpoint,
    headers={
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    },
    json={
        "model": "voice-enrollment",
        "input": {
            "action": "create_voice",
            "target_model": "qwen-audio-3.1-realtime-plus",
            "prefix": "boyfriend",
            "url": "https://example-name.loca.lt/boyfriend.wav",
        },
    },
    timeout=180,
)

print("HTTP:", response.status_code)
print(json.dumps(response.json(), ensure_ascii=False, indent=2))
response.raise_for_status()
'@ | python -
```

成功后会返回类似：

```json
{
  "output": {
    "voice_id": "qwen-audio-3.1-realtime-plus-boyfriend-xxxxxxxx"
  },
  "usage": {
    "count": 1
  },
  "request_id": "xxxxxxxx"
}
```

务必保存完整的 `voice_id`。这个 ID 要传给 Realtime API 的 `session.update.session.voice`。

## 6. 提交前先查重

创建操作会产生一个新的持久音色。网络超时或接口报错后不要立刻盲目重试，应先按前缀查询，避免创建重复音色。

```powershell
@'
import json
import os
import requests

workspace_id = os.environ["BAILIAN_WORKSPACE_ID"]
endpoint = (
    f"https://{workspace_id}.cn-beijing.maas.aliyuncs.com"
    "/api/v1/services/audio/tts/customization"
)

response = requests.post(
    endpoint,
    headers={
        "Authorization": f"Bearer {os.environ['DASHSCOPE_API_KEY']}",
        "Content-Type": "application/json",
    },
    json={
        "model": "voice-enrollment",
        "input": {
            "action": "list_voice",
            "prefix": "boyfriend",
            "page_size": 20,
            "page_index": 0,
        },
    },
    timeout=30,
)

print(json.dumps(response.json(), ensure_ascii=False, indent=2))
'@ | python -
```

只应复用 `target_model` 为 `qwen-audio-3.1-realtime-plus`、前缀正确且状态正常的音色。

## 7. 在 Realtime 模型中验证音色

创建成功并不等于已经完成接入。至少应建立一次真实 WebSocket 连接并确认服务返回 `session.updated`。

```python
import asyncio
import json
import os

from websockets.asyncio.client import connect

WORKSPACE_ID = os.environ["BAILIAN_WORKSPACE_ID"]
API_KEY = os.environ["DASHSCOPE_API_KEY"]
VOICE_ID = "qwen-audio-3.1-realtime-plus-boyfriend-xxxxxxxx"
MODEL = "qwen-audio-3.1-realtime-plus"


async def main():
    url = (
        f"wss://{WORKSPACE_ID}.cn-beijing.maas.aliyuncs.com"
        f"/api-ws/v1/realtime?model={MODEL}"
    )
    async with connect(
        url,
        additional_headers={"Authorization": f"Bearer {API_KEY}"},
        proxy=None,
    ) as websocket:
        print(json.loads(await websocket.recv())["type"])
        await websocket.send(
            json.dumps(
                {
                    "type": "session.update",
                    "session": {
                        "modalities": ["audio", "text"],
                        "voice": VOICE_ID,
                        "instructions": "请使用自然、简短的中文回答。",
                        "input_audio_format": "pcm",
                        "output_audio_format": "pcm",
                        "turn_detection": {"type": "smart_turn"},
                        "input_audio_transcription": {"language": "zh"},
                        "output_audio": {"language": "zh"},
                        "tools": [],
                    },
                },
                ensure_ascii=False,
            )
        )
        event = json.loads(await websocket.recv())
        print(json.dumps(event, ensure_ascii=False, indent=2))
        if event.get("type") != "session.updated":
            raise RuntimeError("音色没有通过 Realtime 会话验证")


asyncio.run(main())
```

进一步验证时，可以发送一条文本消息和 `response.create`，确认收到了非空的 `response.audio.delta`，这样可以证明该音色不仅被配置接受，而且能够实际生成 PCM 音频。

## 8. 接入 Bingo 角色数据库

Bingo 的 YAML 只保存全局兜底音色：

```yaml
realtime_call:
  model: qwen-audio-3.1-realtime-plus
  voice: longanqian_v3.1
```

每个角色自己的音色定义在：

```text
apps/server/bingo/roles/catalog.py
```

角色定义示例：

```python
RoleDefinition(
    "boyfriend",
    "男朋友",
    "boyfriend.png",
    "亲密、可靠的男性伴侣",
    "以男朋友身份陪伴用户。",
    "qwen-audio-3.1-realtime-plus-boyfriend-xxxxxxxx",
)
```

服务启动时会把目录内容同步到数据库的 `roles.voice` 字段。通话时优先使用当前角色的 `role.voice`；如果数据库中的值为空，才回退到 `config.yaml` 的默认 `realtime_call.voice`。

修改目录后启动或重启服务：

```powershell
Set-Location "D:\Python-Project\Bingo\apps\server"
& ".venv\Scripts\python.exe" -m bingo
```

验证 SQLite 数据：

```powershell
@'
import sqlite3

connection = sqlite3.connect(r"D:\Python-Project\Bingo\apps\server\data\bingo.db")
for code, voice in connection.execute(
    "SELECT code, voice FROM roles ORDER BY sort_order"
):
    print(code, voice)
connection.close()
'@ | python -
```

## 9. 完成后立即清理

百炼创建成功并完成验证后：

1. 在 LocalTunnel 终端按 `Ctrl+C`。
2. 在 `http.server` 终端按 `Ctrl+C`。
3. 删除 `.tmp\voice-clone` 中的英文音频副本。
4. 保留原始录音，不要误删源文件。
5. 如果使用 OSS，删除临时对象或确认签名 URL 已过期。
6. 查询端口，确认本地 HTTP 服务已经关闭。

检查 8765 端口：

```powershell
Get-NetTCPConnection -LocalPort 8765 -ErrorAction SilentlyContinue
```

没有输出表示临时服务已关闭。

## 10. 常见问题

### `BadRequest.InputDownloadFailed`

说明百炼无法下载 `input.url`。依次检查：

1. URL 是否为公网 HTTPS 地址，而不是局域网地址或本地路径。
2. 无痕浏览器是否能直接下载，不需要登录、Cookie 或自定义请求头。
3. 返回内容是否真的是音频，而不是隧道提示页或 HTML 页面。
4. 临时隧道是否仍在运行。
5. `http.server` 是否仍在运行，端口和目录是否正确。
6. 文件下载是否完整，网络是否中途断开。

临时隧道偶尔会不稳定。本次操作中第一次家长音色创建返回过 `InputDownloadFailed`，确认没有生成重复音色后重新提交即成功。正式环境建议使用 OSS。

### 创建请求超时，不确定是否成功

不要直接再次创建。先调用 `list_voice` 按 `prefix` 查询；如果已经出现对应 `voice_id`，直接复用。

### `Unsupported voice` 或 Realtime 返回音色错误

复刻时的 `target_model` 必须与通话模型完全一致。本项目必须使用：

```text
qwen-audio-3.1-realtime-plus
```

不能把为其他 TTS、CosyVoice 或其他 Realtime 版本创建的音色直接用于该模型。

### 中文文件名访问失败

将临时副本改为纯英文文件名，并在 URL 中使用英文路径。角色的中文语言内容不会影响英文 `prefix` 和文件名。

### 音色可以配置，但效果不好

重新准备 10～20 秒的清晰录音：

- 只保留一个说话人；
- 使用正常语速；
- 不要朗读歌曲；
- 去掉长停顿、混响和背景音乐；
- 避免过强降噪导致声音失真。

## 11. 安全注意事项

声音样本具有个人和生物特征属性。操作前应确保拥有说话人的授权，并遵守适用的隐私、人格权和平台规则。

- API Key 只放环境变量或服务端配置，不放移动端和公开仓库。
- 不要在日志中输出完整 API Key。
- 不要长期公开声音样本。
- 免费隧道只用于短时测试，并在创建完成后立即关闭。
- 正式环境优先使用私有 OSS 和短时签名 URL。
- 不再使用的复刻音色应通过百炼删除接口移除。
