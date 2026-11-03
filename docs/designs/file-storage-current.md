# 当前文件存储

## 当前 App / 后端

| 内容 | 当前实现 | 依据 |
| --- | --- | --- |
| 聊天发送的图片 | 请求携带 Base64，后端保存到 `apps/server/data/images`，会话记录保存图片 ID。客户端可缓存展示。 | `apps/server/bingo/services/chat.py` 的 `_save_images` 与 `get_chat_image` |
| 社区分享配图 | Base64 图片存入后端 `character_shares.images_json`，通过鉴权图片接口读取。 | `apps/server/bingo/services/community.py`、`bingo/db/models/community.py` |
| 自定义角色头像、用户头像 | 图片内容存储在后端数据库的 avatar_data / user_avatar_data 等字段；App 可缓存。 | `apps/server/bingo/db/models/roles.py`、`bingo/db/models/users.py` |
| 自定义聊天背景 | App 私有目录 `files/wallpapers/<账号散列>/`，外观选择保存在本地 SharedPreferences；不会自动上传。 | `ChatAppearanceStorage.kt` |
| 内置头像、气泡 | Flutter 静态 assets，随安装包分发。 | `apps/mobile/assets/` |
| 24 个内置表情 | 六张透明角色图集打包进 App，客户端保留本地展示数据，后端保留权威文字和语义目录。 | `apps/mobile/assets/stickers/`、`apps/server/bingo/utils/stickers/catalog.py`、`apps/mobile/lib/features/stickers/sticker.dart` |
| 用户添加的表情 | 图片原始字节保存在服务端 `data/stickers`，账号、文字、描述及摘要保存在 `user_stickers` 表，读取图片必须鉴权。 | `apps/server/bingo/api/stickers.py` |

当前后端在开发电脑上运行，因此服务端文件实际也落在这台电脑。当前互动预览服务保留 `.tmp/appearance-qa.db` 中的账号与数据，但使用项目配置的真实模型；普通服务默认数据库位置由 `config.yaml` 指定。

现阶段未接入云对象存储。不能把“HTML 本地添加”描述为“已经上传到平台”。
