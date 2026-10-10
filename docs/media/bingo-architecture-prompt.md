# 架构图生成记录

2026-10-11。使用内置 image_gen 生成并校对，最终图转存为无损 WebP，仅改变编码，不缩放或拉伸。

## 生成提示词

Use case: infographic-diagram. Asset type: a polished raster technical architecture illustration for the GitHub README of Bingo, a real Flutter Android + Python FastAPI AI companionship app. Generate one elegant, accurate horizontal engineering diagram, landscape about 1800x1000 (aspect 1.8:1), near-white mint background, mint green and deep teal typography, tiny tasteful coral/gold accents, flat minimalist rounded cards, subtle shadow, sophisticated spacious alignment, crisp Chinese sans-serif text. Not a UI mockup, no photo, no mascot, no decorative fake technology. Legible at README width 1000px, large labels, short copy. Title exactly "Bingo 技术架构", subtitle "有名字、有性格、有声音的 AI 陪伴".

Layout: four main columns left to right connected by clean thin orthogonal arrow lines. Lower band for storage and scheduled tasks. Balanced visual hierarchy, clean purposeful icons (phone, shield, layers, cloud, database, clock). All printed labels use the exact following strings. Do not print explanatory instructions or invent features.

COLUMN 1 heading "Android 客户端"; large "Flutter"; three rows "伙伴 · 聊天 · 陪伴玩法", "录音 · 朗读 · 实时通话", "SQLite 本地会话缓存".
COLUMN 2 heading "安全接入"; rows "Nginx · HTTPS", "/bingo/api/v1", "FastAPI · API 层", "鉴权 · 参数校验", "HTTP 统一响应", "WebSocket 事件协议".
COLUMN 3 heading "Services 业务层"; four separate inner rounded modules:
"伙伴与会话" with secondary "资料 · 角色 · 独立聊天";
"Agent Runtime" with secondary "提示词 · 短期上下文 · 长期记忆" and small tertiary "工具：搜索 · 天气 · 来电 · 闹钟";
"语音服务" with secondary "ASR · 流式 TTS · 声音复刻 · 通话";
"陪伴玩法" with secondary "一起专注 · 小约定 · 入睡 · 小记".
COLUMN 4 heading "外部服务"; four rows "可配置 LLM / 视觉模型", "DashScope 语音服务", "高德地图服务", "个推消息推送".

Bottom band: three generous rounded cards below the central server columns:
card title "SQLite" subtitle "用户 · 伙伴 · 会话 · 长期记忆";
card title "Redis" subtitle "延迟任务 · 推荐缓存 · 地区缓存";
card title "后台陪伴调度" subtitle two rows "1 小时关心 · 5 小时推荐", "次日 7–9 点随机早安".
Thin downward arrows from Services to SQLite and Redis. Background scheduled worker connects to data storage and to external Getui push. Keep connections uncluttered; main arrows only through Client → Safety ingress/API → Services → External services; bidirectional main arrows may be used for responses. No direct client → LLM arrow. API is not shown directly writing to database.
Small understated footer exactly "模型与语音密钥留在服务端 · 设备操作由用户确认". Include no API credentials, phone numbers, deployment IPs, unrelated logos, unsupported PostgreSQL/Kafka/Docker/Kubernetes claims, browser/iOS app, extra text, watermarks, fake 3D effects. Important technical accuracy: HTTP response wrapping only applies to HTTP, not WebSocket; SQLite exists both on phone and server; Redis is cache/scheduling not long-term memory; custom voices are role-specific; device actions are confirmed on Android. Render beautiful complete Chinese text, no garbled letters, no cropped text or edges.

## 校对修改提示词

Edit this architecture image with only two technical corrections. Preserve the exact canvas size, all layout, colors, icons, Chinese text, typography, card geometry, main horizontal arrows and footer. 1. Remove all five small vertical arrows between the six white cards inside the 安全接入 column (Nginx/HTTPS, /bingo/api/v1, FastAPI/API层, 鉴权参数校验, HTTP统一响应, WebSocket事件协议). These cards are a set of capabilities, not one serialized chain; especially HTTP统一响应 must NOT feed WebSocket事件协议. Fill the removed arrows with the same surrounding pale mint background. Do not introduce any new internal arrows. 2. Remove ONLY the horizontal double-headed arrow directly between bottom SQLite card and bottom Redis card, filling its gap with original background. They are independent storage services; keep the two separate downward branches from Services to them. Keep the existing Redis ↔ 后台陪伴调度 arrow and the worker → 个推 upward arrow. Do not change any other element, no text corrections or additional content. Retain excellent sharp legible Chinese lettering.

