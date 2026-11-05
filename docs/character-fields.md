# 搭子人物资料字段

官方搭子与用户创建的搭子统一使用七项核心资料。简介、开场白、发现分类属于辅助资料，
不再与人物背景混用；用户信息、长期记忆和关系进展仍独立保存。

| 页面名称 | 官方目录字段 | API 字段 | 内容 |
| --- | --- | --- | --- |
| 人物头像 | `avatar` | `avatar_data` / `avatar_asset` | 上传图片或内置头像 |
| 人物名称 | `name` | `character_name` | 如“老雷”，不是“董事长” |
| 人物关系 | `relationship` | `relationship` | 如“董事长”，支持自定义 |
| 说话风格 | `speaking_style` | `speaking_style` | 语气、表达方式和相处习惯；最多 1000 字 |
| 性格标签 | `personality_tags` | `personality_tags` | 原人物特征，选择 2～3 个标签 |
| 人物背景 | `background` | `background` | 经历、职业、兴趣等；最多 2000 字 |
| 人物声音 | `voice` | `voice_source_id` | 系统/其他可用搭子音色或自己复刻的音色 |

## 官方目录

`bingo/roles/catalog.py` 的每个 `RoleDefinition` 使用具名参数一次性定义人物资料。
昵称、旧性格预设及分类/标签映射从定义自动生成。角色 `code`、稳定 ID、顺序和音色不变。
目录中的 `name` 已明确指人物名称，落入旧数据库的 `roles.name` 仍保留关系/内部名称语义，
以兼容历史会话、用户资料和旧客户端。新界面使用 `character_name` 和 `relationship`。

## 存储与兼容

- `roles.background` 独立保存人物背景；升级时将旧 `prompt` 原文复制过来，不猜测拆分，不删原文。
- `roles.speaking_style` 保存人物默认说话风格。
- `role_preferences.speaking_style` 保存当前用户对该搭子的风格设置，官方人物不被其他用户的修改影响。
- `traits_json` 继续存储标签，接口使用 `personality_tags`，不重复存两份标签。
- 保留 `name`、`nickname`、`role_type`、`traits`、`prompt`、`personality` 旧接口字段。
  请求同时提供新旧别名时，以 `character_name`、`relationship`、`personality_tags` 为准。
- 旧请求中的 `prompt` 仍能更新人物背景；旧 `personality` 预设仍能更新说话风格，
  并清除该用户此前的自定义风格覆盖。仅修改其他资料时保留现有风格。
- 官方搭子只允许修改当前用户的说话风格；头像、名称、关系、标签、背景、声音保持官方定义。
- 社区分享快照保存背景和风格，添加搭子时完整恢复；旧快照回退到 `prompt` 和 `personality`。
- 升级为增量迁移，可重复运行，不重建数据库，不改用户聊天和音色归属。

## 模型上下文

人物名称、关系、性格标签和人物背景统一组成角色上下文；当前用户的有效说话风格单独传入。
单聊、群聊及通话共用这些资料。社区展示和创建页不再把内部提示词当作额外必填字段。

## 创建与编辑页面

七项核心资料按顺序展示。说话风格既可选择预设，也可文字描述；人物关系支持选择与自定义。
头像保留默认图，声音保留默认音色。简短介绍和开场白收进“更多资料”，可以不填。
