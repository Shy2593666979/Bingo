import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bingo/core/design/chat_scene.dart';
import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/core/appearance/bubble_art.dart';
import 'package:bingo/core/appearance/raster_bubble.dart';
import 'package:bingo/core/appearance/reference_bubble_sizes.dart';
import 'package:bingo/core/appearance/h2_bubble_frame.dart';

class ChatAppearance {
  const ChatAppearance(
      {this.background = 'mint',
      this.bubble = 'mint',
      this.photo,
      this.fade = 0,
      this.zoom = 1,
      this.x = 0,
      this.y = 0});
  final String background, bubble;
  final String? photo;
  final double fade, x, y, zoom;
  ChatAppearance copyWith(
          {String? background,
          String? bubble,
          String? photo,
          double? fade,
          double? zoom,
          double? x,
          double? y}) =>
      ChatAppearance(
          background: background ?? this.background,
          bubble: bubble ?? this.bubble,
          photo: photo ?? this.photo,
          fade: fade ?? this.fade,
          zoom: zoom ?? this.zoom,
          x: x ?? this.x,
          y: y ?? this.y);
  Map<String, dynamic> toJson() => {
        'background': background,
        'bubble': bubble,
        'photo': photo,
        'fade': fade,
        'zoom': zoom,
        'x': x,
        'y': y
      };
  factory ChatAppearance.fromJson(Map<String, dynamic> v) => ChatAppearance(
      background:
          v['background'] is String ? v['background'] as String : 'mint',
      bubble: v['bubble'] is String ? v['bubble'] as String : 'mint',
      photo: v['photo'] as String?,
      fade: ((v['fade'] as num?)?.toDouble() ?? 0).clamp(0, .85),
      zoom: ((v['zoom'] as num?)?.toDouble() ?? 1).clamp(1, 2.5),
      x: ((v['x'] as num?)?.toDouble() ?? 0).clamp(-1, 1),
      y: ((v['y'] as num?)?.toDouble() ?? 0).clamp(-1, 1));
}

class AppearanceStore extends ChangeNotifier {
  AppearanceStore(this.userId);
  final String userId;
  static const channel = MethodChannel('bingo/appearance');
  Map<String, ChatAppearance> _values = {};
  Future<void>? _loading;
  bool _disposed = false;
  ChatAppearance effective([String? roleId]) =>
      _values[roleId] ?? _values['global'] ?? const ChatAppearance();
  bool hasOverride(String roleId) => _values.containsKey(roleId);
  Future<void> load() => _loading ??= _load().catchError((Object error) {
        _loading = null;
        throw error;
      });
  Future<void> _load() async {
    try {
      final raw =
          await channel.invokeMethod<String>('load', {'user_id': userId});
      final values = raw == null
          ? <String, dynamic>{}
          : jsonDecode(raw) as Map<String, dynamic>;
      if (_disposed) return;
      _values = values.map((key, value) => MapEntry(key,
          ChatAppearance.fromJson(Map<String, dynamic>.from(value as Map))));
      notifyListeners();
    } on MissingPluginException {
      return;
    }
  }

  Future<void> save(ChatAppearance? value, {String? roleId}) async {
    await load();
    final next = Map<String, ChatAppearance>.of(_values);
    if (value == null) {
      next.remove(roleId ?? 'global');
    } else {
      next[roleId ?? 'global'] = value;
    }
    await channel.invokeMethod<void>('save', {
      'user_id': userId,
      'data':
          jsonEncode(next.map((key, value) => MapEntry(key, value.toJson())))
    });
    if (_disposed) return;
    _values = next;
    notifyListeners();
  }

  Future<String> importPhoto(Uint8List bytes) async =>
      (await channel.invokeMethod<String>(
          'importPhoto', {'user_id': userId, 'bytes': bytes}))!;
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class ChatSkin {
  const ChatSkin(this.id, this.name, this.description, this.accent, this.user,
      this.other, this.wall, this.icon);
  final String id, name, description;
  final Color accent, user, other, wall;
  final IconData icon;
  String? get asset {
    if (!id.startsWith('ref_')) return null;
    final name = id.substring(4);
    return 'assets/chat_bubbles/$name${name == 'pot' || name == 'truck' ? '-v2' : ''}.webp';
  }

  static const references = [
    ChatSkin(
        'ref_carrot',
        '胡萝卜啵啵',
        '插画皮肤 · 甜萌',
        Color(0xFF986044),
        Color(0xFFFFE1D3),
        Color(0xFFFFFBF6),
        Color(0xFFFAFAF9),
        Icons.auto_awesome_outlined),
    ChatSkin(
        'ref_wolf',
        '大狗狗是狼',
        '插画皮肤 · 甜萌',
        Color(0xFF5C6285),
        Color(0xFFE1E7F6),
        Color(0xFFF1F4FA),
        Color(0xFFFAFAF9),
        Icons.auto_awesome_outlined),
    ChatSkin(
        'ref_shiba',
        '啃骨小柴',
        '插画皮肤 · 甜萌',
        Color(0xFF8A684B),
        Color(0xFFFFF7E8),
        Color(0xFFFFFCF7),
        Color(0xFFFAFAF9),
        Icons.auto_awesome_outlined),
    ChatSkin(
        'ref_sailor',
        '小小航海家',
        '插画皮肤 · 甜萌',
        Color(0xFF477F96),
        Color(0xFFE0F5FF),
        Color(0xFFF2FAFF),
        Color(0xFFFAFAF9),
        Icons.auto_awesome_outlined),
    ChatSkin(
        'ref_ginger',
        '一只姜小猫',
        '插画皮肤 · 甜萌',
        Color(0xFF99702B),
        Color(0xFFFFF0CE),
        Color(0xFFFFFCF1),
        Color(0xFFFAFAF9),
        Icons.auto_awesome_outlined),
    ChatSkin(
        'ref_peachmilk',
        '桃子草莓奶',
        '插画皮肤 · 甜萌',
        Color(0xFF9F7183),
        Color(0xFFFFF5F8),
        Color(0xFFFFFCFD),
        Color(0xFFFAFAF9),
        Icons.auto_awesome_outlined),
    ChatSkin(
        'ref_nian',
        '年兽小粉团',
        '插画皮肤 · 甜萌',
        Color(0xFF997480),
        Color(0xFFFFE7ED),
        Color(0xFFFFFAFC),
        Color(0xFFFAFAF9),
        Icons.auto_awesome_outlined),
    ChatSkin(
        'ref_ghost',
        '魔法幽灵',
        '插画皮肤 · 甜萌',
        Color(0xFF6E527F),
        Color(0xFFF1E8FF),
        Color(0xFFFBF8FF),
        Color(0xFFFAFAF9),
        Icons.auto_awesome_outlined),
    ChatSkin(
        'ref_bear',
        '小熊甜品师',
        '插画皮肤 · 甜萌',
        Color(0xFF977146),
        Color(0xFFFFEDCF),
        Color(0xFFFFFBF2),
        Color(0xFFFAFAF9),
        Icons.auto_awesome_outlined),
    ChatSkin(
        'ref_moeye',
        '无敌萌萌ye',
        '插画皮肤 · 甜萌',
        Color(0xFF95647F),
        Color(0xFFFFDFF1),
        Color(0xFFFFF7FC),
        Color(0xFFFAFAF9),
        Icons.auto_awesome_outlined),
    ChatSkin(
        'ref_qiqi',
        '七七大王',
        '插画皮肤 · 甜萌',
        Color(0xFF917737),
        Color(0xFFFFF4BA),
        Color(0xFFFFFBE1),
        Color(0xFFFAFAF9),
        Icons.auto_awesome_outlined),
    ChatSkin(
        'ref_icecream',
        '尔尔冰淇凌',
        '插画皮肤 · 甜萌',
        Color(0xFFA47281),
        Color(0xFFFFEAF1),
        Color(0xFFFFFCFD),
        Color(0xFFFAFAF9),
        Icons.auto_awesome_outlined),
    ChatSkin(
        'ref_droolcat',
        '傻猫流口水',
        '插画皮肤 · 趣味',
        Color(0xFF5D5B60),
        Color(0xFFEAE8E6),
        Color(0xFFF4F3F1),
        Color(0xFFFAFAF9),
        Icons.auto_awesome_outlined),
    ChatSkin(
        'ref_truck',
        '大运来咯',
        '插画皮肤 · 趣味',
        Color(0xFF9D5145),
        Color(0xFFFFF9F2),
        Color(0xFFFFFCF7),
        Color(0xFFFAFAF9),
        Icons.auto_awesome_outlined),
    ChatSkin(
        'ref_pot',
        '加热中',
        '插画皮肤 · 趣味',
        Color(0xFF5D6D77),
        Color(0xFFEEF1F2),
        Color(0xFFFAFCFC),
        Color(0xFFFAFAF9),
        Icons.auto_awesome_outlined),
    ChatSkin(
        'ref_sadworker',
        '伤心社畜',
        '插画皮肤 · 趣味',
        Color(0xFF72777C),
        Color(0xFFF5F7F8),
        Color(0xFFFFFFFF),
        Color(0xFFFAFAF9),
        Icons.auto_awesome_outlined),
    ChatSkin(
        'ref_please',
        '求你了',
        '插画皮肤 · 趣味',
        Color(0xFF4F4F52),
        Color(0xFFFFFFFF),
        Color(0xFFFFFFFF),
        Color(0xFFFAFAF9),
        Icons.auto_awesome_outlined),
    ChatSkin(
        'ref_blossom',
        '桃花运',
        '插画皮肤 · 趣味',
        Color(0xFFA45A76),
        Color(0xFFFFEAF1),
        Color(0xFFFFF9FC),
        Color(0xFFFAFAF9),
        Icons.auto_awesome_outlined),
    ChatSkin(
        'ref_chefmouse',
        '鼠大厨',
        '插画皮肤 · 趣味',
        Color(0xFF747C82),
        Color(0xFFF2F5F7),
        Color(0xFFFFFFFF),
        Color(0xFFFAFAF9),
        Icons.auto_awesome_outlined),
    ChatSkin(
        'ref_star27',
        '星环遇二七',
        '插画皮肤 · 趣味',
        Color(0xFFA08542),
        Color(0xFFFFF3CF),
        Color(0xFFFFFBEF),
        Color(0xFFFAFAF9),
        Icons.auto_awesome_outlined),
    ChatSkin(
        'ref_snowburger',
        '寒雪堡堡',
        '插画皮肤 · 趣味',
        Color(0xFF568DA2),
        Color(0xFFE2F7FF),
        Color(0xFFF5FCFF),
        Color(0xFFFAFAF9),
        Icons.auto_awesome_outlined),
    ChatSkin(
        'ref_autumncat',
        '秋雨小猫',
        '插画皮肤 · 趣味',
        Color(0xFF657F9D),
        Color(0xFFEDF5FF),
        Color(0xFFFAFCFF),
        Color(0xFFFAFAF9),
        Icons.auto_awesome_outlined),
    ChatSkin(
        'ref_wuta',
        '无他',
        '插画皮肤 · 趣味',
        Color(0xFF65866A),
        Color(0xFFEAF5E8),
        Color(0xFFFDFFFA),
        Color(0xFFFAFAF9),
        Icons.auto_awesome_outlined),
    ChatSkin(
        'ref_mushroom',
        '蘑菇豪',
        '插画皮肤 · 趣味',
        Color(0xFFA6777D),
        Color(0xFFFFF1EC),
        Color(0xFFFFFCF7),
        Color(0xFFFAFAF9),
        Icons.auto_awesome_outlined),
  ];
  static const h2 = [
    ChatSkin('h2_mint', '薄荷日常', '绿叶 · 清透薄荷', Color(0xFF08A987),
        Color(0xFFCAFAEC), Colors.white, Color(0xFFECFBF7), Icons.spa_outlined),
    ChatSkin(
        'h2_bear',
        '软糖小熊',
        '小熊 · 软糖爱心',
        Color(0xFFE5809B),
        Color(0xFFFFE7EF),
        Colors.white,
        Color(0xFFFFF5F8),
        Icons.favorite_outline),
    ChatSkin(
        'h2_cat',
        '猫咪来信',
        '猫耳 · 奶油爪印',
        Color(0xFFCCA44A),
        Color(0xFFFFF2CD),
        Colors.white,
        Color(0xFFFFFBF0),
        Icons.pets_outlined),
    ChatSkin('h2_moon', '星月晚安', '星星 · 月亮', Color(0xFF9A82DF), Color(0xFFECE5FF),
        Colors.white, Color(0xFFF7F3FF), Icons.nightlight_outlined),
    ChatSkin(
        'h2_heart',
        '桃桃心动',
        '桃粉 · 心动时刻',
        Color(0xFFF177A4),
        Color(0xFFFFE2ED),
        Colors.white,
        Color(0xFFFFF4F8),
        Icons.favorite_outline),
    ChatSkin(
        'h2_ocean',
        '海盐晴空',
        '水滴 · 轻柔云朵',
        Color(0xFF65B8DF),
        Color(0xFFDFF5FF),
        Colors.white,
        Color(0xFFF1FAFF),
        Icons.water_drop_outlined),
  ];
  static const all = [...references, ...h2, ...originals];
  static const originals = [
    ChatSkin(
        'mint',
        '薄荷日常',
        '薄荷绿 · 清透陪伴',
        BingoPalette.primary,
        BingoPalette.userBubble,
        Colors.white,
        BingoPalette.pageTop,
        Icons.spa_outlined),
    ChatSkin(
        'rabbit',
        '奶兔贴贴',
        '兔耳 · 软萌爪印',
        Color(0xFF986271),
        Color(0xFFF8DFE5),
        Color(0xFFFFFBF5),
        Color(0xFFFBF1F2),
        Icons.cruelty_free_outlined),
    ChatSkin(
        'ribbon',
        '丝带情书',
        '蝴蝶结 · 蕾丝花边',
        Color(0xFF9D5C76),
        Color(0xFFF7DCE8),
        Color(0xFFFFF9FC),
        Color(0xFFFCF2F6),
        Icons.redeem_outlined),
    ChatSkin('kitty', '猫爪奶咖', '猫耳 · 奶咖贴纸', Color(0xFF8A6A53), Color(0xFFF0DEC7),
        Color(0xFFFFFCF5), Color(0xFFFAF5EC), Icons.pets_outlined),
    ChatSkin('jelly', '莓莓果冻', '晶莹 · 糖果高光', Color(0xFFA54E79), Color(0xFFF8CFE4),
        Color(0xFFF5E9FF), Color(0xFFFCF0F8), Icons.bubble_chart_outlined),
    ChatSkin('peach', '蜜桃来信', '胶带 · 蜜桃信笺', Color(0xFFA55440), Color(0xFFFFDCCE),
        Color(0xFFFFF8F1), Color(0xFFFFF3EB), Icons.favorite_border_rounded),
    ChatSkin(
        'violet',
        '星愿紫',
        '垂落星星 · 梦幻紫',
        Color(0xFF7254A1),
        Color(0xFFE8DCFA),
        Color(0xFFF9F6FF),
        Color(0xFFF1ECFA),
        Icons.auto_awesome_outlined),
    ChatSkin('ocean', '海盐蓝', '水光 · 海盐果冻', Color(0xFF346D96), Color(0xFFD1EAF9),
        Color(0xFFF2FAFE), Color(0xFFEDF6FB), Icons.water_drop_outlined),
    ChatSkin('paper', '奶油手账', '胶带 · 缝线纸边', Color(0xFF82613E), Color(0xFFF3E2AD),
        Color(0xFFFFFDF5), Color(0xFFF8F2E5), Icons.edit_note_rounded),
    ChatSkin('rose', '玫瑰软糖', '缎带 · 玫瑰花边', Color(0xFF9B4F71), Color(0xFFF6D7E6),
        Color(0xFFFFF7FA), Color(0xFFFCEDF4), Icons.local_florist_outlined),
    ChatSkin('comic', '墨线漫画', '个性 · 硬朗投影', Color(0xFF384044), Color(0xFFFFE899),
        Color(0xFFFFFFFF), Color(0xFFF3F3EE), Icons.bolt_rounded),
  ];
  static ChatSkin find(String id) =>
      all.firstWhere((s) => s.id == id, orElse: () => originals.first);
  BorderRadius radius(bool userSide) {
    final (large, small) = switch (id) {
      'paper' => (5.0, 5.0),
      'comic' => (17.0, 3.0),
      'ocean' => (30.0, 3.0),
      'rose' => (30.0, 13.0),
      'peach' => (22.0, 6.0),
      _ => (26.0, 8.0)
    };
    return BorderRadius.only(
        topLeft: Radius.circular(large),
        topRight: Radius.circular(large),
        bottomLeft: Radius.circular(userSide ? large : small),
        bottomRight: Radius.circular(userSide ? small : large));
  }

  BoxDecoration decoration(bool userSide) {
    final color = userSide ? user : other;
    return BoxDecoration(
        color: color,
        gradient: ['peach', 'violet', 'ocean', 'rose'].contains(id)
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color.lerp(color, Colors.white, .35)!, color])
            : null,
        borderRadius: radius(userSide),
        border: id == 'mint'
            ? null
            : Border.all(
                color: accent.withValues(alpha: id == 'comic' ? 1 : .23),
                width: id == 'comic' ? 1.5 : 1),
        boxShadow: [
          BoxShadow(
              color: id == 'comic' ? accent : accent.withValues(alpha: .07),
              blurRadius: id == 'comic' ? 0 : 10,
              offset: id == 'comic' ? const Offset(3, 3) : const Offset(0, 3))
        ]);
  }
}

class AppearanceScope extends InheritedWidget {
  const AppearanceScope({required this.value, required super.child, super.key});
  final ChatAppearance value;
  static ChatAppearance of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppearanceScope>()?.value ??
      const ChatAppearance();
  static ChatSkin skin(BuildContext context) =>
      ChatSkin.find(of(context).bubble);
  @override
  bool updateShouldNotify(AppearanceScope oldWidget) =>
      value != oldWidget.value;
}

class BubbleSurface extends StatelessWidget {
  const BubbleSurface(
      {required this.isUser,
      required this.child,
      this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      super.key});
  final bool isUser;
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) {
    final skin = AppearanceScope.skin(context);
    return SkinBubbleFrame(
        skin: skin, isUser: isUser, padding: padding, child: child);
  }
}

class SkinBubbleFrame extends StatelessWidget {
  const SkinBubbleFrame(
      {required this.skin,
      required this.isUser,
      required this.child,
      this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      this.compact = false,
      super.key});
  final ChatSkin skin;
  final bool isUser, compact;
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) {
    if (skin.id.startsWith('h2_')) {
      return H2BubbleFrame(
          index: ChatSkin.h2.indexWhere((s) => s.id == skin.id),
          compact: compact,
          padding: padding,
          child: child);
    }
    if (skin.asset != null) {
      return RasterBubbleFrame(
          asset: skin.asset!,
          sourceSize: referenceBubbleSizes[skin.id.substring(4)] ??
              const Size(1942, 809),
          fallback: isUser ? skin.user : skin.other,
          compact: compact,
          padding: padding,
          child: child);
    }
    if (skin.id == 'mint') {
      return SageBubble(isUser: isUser, padding: padding, child: child);
    }
    final painter = BubbleArtworkPainter(
        id: skin.id,
        isUser: isUser,
        fill: isUser ? skin.user : skin.other,
        accent: skin.accent,
        radius: skin.radius(isUser),
        compact: compact);
    final ornamentPadding = ['ribbon', 'rose'].contains(skin.id)
        ? (compact ? 12.0 : 24.0)
        : ['violet', 'jelly', 'ocean'].contains(skin.id)
            ? (compact ? 9.0 : 16.0)
            : 0.0;
    return ConstrainedBox(
        constraints: BoxConstraints(minWidth: compact ? 0 : 84),
        child: CustomPaint(
            painter: painter,
            child: Padding(
                padding: EdgeInsets.fromLTRB(
                    padding.left + 4,
                    (padding.top < ornamentPadding
                            ? ornamentPadding
                            : padding.top) +
                        painter.top,
                    padding.right + 4,
                    padding.bottom + painter.bottom),
                child: child)));
  }
}

class ChatWallpaper extends StatelessWidget {
  const ChatWallpaper({required this.value, required this.child, super.key});
  final ChatAppearance value;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final skin = ChatSkin.find(value.background);
    if (value.background == 'mint') {
      return DecoratedBox(
          decoration: const BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                Color(0xFFFFFFFF),
                Color(0xFFFAFDFC),
                Color(0xFFF3FAF7)
              ])),
          child: child);
    }
    return DecoratedBox(
        decoration: BoxDecoration(
            color: skin.wall,
            gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  skin.wall,
                  Color.lerp(skin.wall, Colors.white, .65)!
                ])),
        child: Stack(fit: StackFit.passthrough, children: [
          Positioned.fill(
              child: value.background == 'photo' && value.photo != null
                  ? ClipRect(
                      child: Transform.scale(
                          scale: value.zoom,
                          alignment: Alignment(value.x, value.y),
                          child: Image.file(File(value.photo!),
                              fit: BoxFit.cover,
                              alignment: Alignment(value.x, value.y),
                              cacheWidth: 1440,
                              errorBuilder: (_, __, ___) =>
                                  ColoredBox(color: skin.wall))))
                  : CustomPaint(painter: _WallpaperPattern(skin))),
          if (value.background == 'photo')
            Positioned.fill(
                child: ColoredBox(
                    color: Colors.white.withValues(alpha: value.fade))),
          child,
        ]));
  }
}

class _WallpaperPattern extends CustomPainter {
  _WallpaperPattern(this.skin);
  final ChatSkin skin;
  @override
  void paint(Canvas canvas, Size size) {
    if (skin.id == 'mint' || skin.asset != null) return;
    final paint = Paint()
      ..color = skin.accent.withValues(alpha: .08)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    if (skin.id == 'paper') {
      for (double y = 18; y < size.height; y += 28) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      }
      canvas.drawLine(const Offset(28, 0), Offset(28, size.height), paint);
      return;
    }
    for (double y = 28; y < size.height; y += 92) {
      for (double x = 25 + ((y ~/ 92).isOdd ? 40 : 0);
          x < size.width;
          x += 92) {
        if (skin.id == 'violet') {
          canvas.drawPath(
              Path()
                ..moveTo(x, y - 7)
                ..quadraticBezierTo(x + 1, y - 1, x + 7, y)
                ..quadraticBezierTo(x + 1, y + 1, x, y + 7)
                ..quadraticBezierTo(x - 1, y + 1, x - 7, y)
                ..quadraticBezierTo(x - 1, y - 1, x, y - 7),
              paint);
        } else if (skin.id == 'rabbit' || skin.id == 'kitty') {
          canvas.drawOval(
              Rect.fromCenter(center: Offset(x, y + 3), width: 8, height: 6),
              paint);
          for (final dx in [-5.0, 0.0, 5.0]) {
            canvas.drawCircle(Offset(x + dx, y - 3), 1.5, paint);
          }
        } else if (skin.id == 'jelly') {
          canvas.drawCircle(Offset(x, y), 7, paint);
          canvas.drawCircle(Offset(x + 10, y - 9), 2, paint);
        } else if (skin.id == 'peach' ||
            skin.id == 'rose' ||
            skin.id == 'ribbon') {
          canvas.drawPath(
              Path()
                ..moveTo(x, y + 5)
                ..cubicTo(x - 15, y - 3, x - 3, y - 12, x, y - 5)
                ..cubicTo(x + 3, y - 12, x + 15, y - 3, x, y + 5),
              paint);
        } else if (skin.id == 'ocean') {
          canvas.drawArc(
              Rect.fromCenter(center: Offset(x, y), width: 32, height: 14),
              0,
              3.14,
              false,
              paint);
          canvas.drawArc(
              Rect.fromCenter(
                  center: Offset(x + 12, y + 6), width: 32, height: 14),
              0,
              3.14,
              false,
              paint);
        } else {
          canvas.drawCircle(
              Offset(x, y), 1.5, paint..style = PaintingStyle.fill);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_WallpaperPattern oldDelegate) =>
      oldDelegate.skin.id != skin.id;
}
