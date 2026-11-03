import 'dart:convert';
import 'dart:typed_data';

class ChatSticker {
  const ChatSticker(
      {required this.id,
      required this.label,
      required this.description,
      this.asset,
      this.index = 0});
  final String id, label, description;
  final String? asset;
  final int index;
  bool get custom => id.startsWith('custom_');
  static const prefix = '[[bingo.sticker.v1]]';
  static const suffix = '[[/bingo.sticker]]';
  String encode() => '$prefix${jsonEncode({
            'v': 1,
            'id': id,
            'label': label,
            'description': description
          })}$suffix';
  factory ChatSticker.fromJson(Map<String, dynamic> value) => ChatSticker(
      id: value['id'] as String,
      label: value['label'] as String,
      description: value['description'] as String);
  static ChatSticker? parse(String text) {
    if (!text.startsWith(prefix) ||
        !text.endsWith(suffix) ||
        text.length > 4000) {
      return null;
    }
    try {
      final data =
          jsonDecode(text.substring(prefix.length, text.length - suffix.length))
              as Map<String, dynamic>;
      if (data['v'] != 1 ||
          data['label'] is! String ||
          data['description'] is! String ||
          data['id'] is! String) {
        return null;
      }
      final label = data['label'] as String,
          description = data['description'] as String,
          id = data['id'] as String;
      if (label.trim().isEmpty ||
          label.runes.length > 30 ||
          description.trim().isEmpty ||
          description.runes.length > 300) {
        return null;
      }
      final builtin = builtins.where((s) => s.id == id).firstOrNull;
      if (builtin != null) {
        return ChatSticker(
            id: id,
            label: label,
            description: description,
            asset: builtin.asset,
            index: builtin.index);
      }
      if (!RegExp(r'^custom_[a-fA-F0-9-]{36}$').hasMatch(id)) {
        return null;
      }
      return ChatSticker(id: id, label: label, description: description);
    } catch (_) {
      return null;
    }
  }

  static String preview(String text) {
    final sticker = parse(text);
    return sticker == null ? text : '[表情] ${sticker.label}';
  }

  static const builtins = <ChatSticker>[
    ChatSticker(
        id: "girlfriend_0",
        label: "喜欢你",
        description: "双手比心，表达喜欢和亲近",
        asset: "assets/stickers/girlfriend.webp",
        index: 0),
    ChatSticker(
        id: "girlfriend_1",
        label: "抱抱",
        description: "张开双臂，表达拥抱、安慰与亲近",
        asset: "assets/stickers/girlfriend.webp",
        index: 1),
    ChatSticker(
        id: "girlfriend_2",
        label: "晚安啦",
        description: "闭眼抱枕，表达晚安和休息",
        asset: "assets/stickers/girlfriend.webp",
        index: 2),
    ChatSticker(
        id: "girlfriend_3",
        label: "送你小花",
        description: "手拿小花，表达感谢和友善",
        asset: "assets/stickers/girlfriend.webp",
        index: 3),
    ChatSticker(
        id: "boyfriend_0",
        label: "抱一下",
        description: "张开双臂，表达拥抱和支持",
        asset: "assets/stickers/boyfriend.webp",
        index: 0),
    ChatSticker(
        id: "boyfriend_1",
        label: "一起加油",
        description: "握拳加油，表达鼓励",
        asset: "assets/stickers/boyfriend.webp",
        index: 1),
    ChatSticker(
        id: "boyfriend_2",
        label: "早点休息",
        description: "抱着月亮枕头，表达休息和晚安",
        asset: "assets/stickers/boyfriend.webp",
        index: 2),
    ChatSticker(
        id: "boyfriend_3",
        label: "我在听",
        description: "侧耳倾听，表达愿意听对方说话",
        asset: "assets/stickers/boyfriend.webp",
        index: 3),
    ChatSticker(
        id: "colleague_0",
        label: "收到",
        description: "拿着记录板竖拇指，表达收到和确认",
        asset: "assets/stickers/colleague.webp",
        index: 0),
    ChatSticker(
        id: "colleague_1",
        label: "有点累了",
        description: "趴在电脑旁，表达疲惫",
        asset: "assets/stickers/colleague.webp",
        index: 1),
    ChatSticker(
        id: "colleague_2",
        label: "下班快乐",
        description: "举起咖啡，庆祝下班",
        asset: "assets/stickers/colleague.webp",
        index: 2),
    ChatSticker(
        id: "colleague_3",
        label: "开工！",
        description: "握拳提气，表达开工和努力",
        asset: "assets/stickers/colleague.webp",
        index: 3),
    ChatSticker(
        id: "teacher_0",
        label: "真棒",
        description: "抱着书竖拇指，表达赞赏和肯定",
        asset: "assets/stickers/teacher.webp",
        index: 0),
    ChatSticker(
        id: "teacher_1",
        label: "慢慢来",
        description: "举起手指，表达耐心解释与提醒",
        asset: "assets/stickers/teacher.webp",
        index: 1),
    ChatSticker(
        id: "teacher_2",
        label: "懂啦",
        description: "露出恍然大悟的表情，表达理解",
        asset: "assets/stickers/teacher.webp",
        index: 2),
    ChatSticker(
        id: "teacher_3",
        label: "歇一歇",
        description: "双手捧杯，表达休息和放松",
        asset: "assets/stickers/teacher.webp",
        index: 3),
    ChatSticker(
        id: "parent_0",
        label: "吃饭啦",
        description: "端着热面，表达关心和提醒吃饭",
        asset: "assets/stickers/parent.webp",
        index: 0),
    ChatSticker(
        id: "parent_1",
        label: "做得好",
        description: "双手竖拇指，表达肯定和鼓励",
        asset: "assets/stickers/parent.webp",
        index: 1),
    ChatSticker(
        id: "parent_2",
        label: "别着凉",
        description: "拿着围巾，表达关心与保暖提醒",
        asset: "assets/stickers/parent.webp",
        index: 2),
    ChatSticker(
        id: "parent_3",
        label: "早点睡",
        description: "捧着热饮挥手，表达晚安与早睡提醒",
        asset: "assets/stickers/parent.webp",
        index: 3),
    ChatSticker(
        id: "child_0",
        label: "耶！",
        description: "举起双手，表达开心和庆祝",
        asset: "assets/stickers/child.webp",
        index: 0),
    ChatSticker(
        id: "child_1",
        label: "有点委屈",
        description: "含泪托脸，表达委屈或撒娇",
        asset: "assets/stickers/child.webp",
        index: 1),
    ChatSticker(
        id: "child_2",
        label: "击个掌",
        description: "伸出手掌，表达击掌和鼓励",
        asset: "assets/stickers/child.webp",
        index: 2),
    ChatSticker(
        id: "child_3",
        label: "看我画的",
        description: "展示画作，表达分享和期待认可",
        asset: "assets/stickers/child.webp",
        index: 3),
  ];
}

abstract interface class StickerGateway {
  Future<List<ChatSticker>> listStickers();
  Future<ChatSticker> uploadSticker(Uint8List bytes, String mime, String label);
  Future<void> deleteSticker(String id);
  String stickerImageUrl(String id);
  String? get stickerToken;
}
