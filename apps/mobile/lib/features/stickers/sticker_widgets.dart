import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bingo/core/widgets/center_toast.dart';
import 'package:bingo/features/stickers/sticker.dart';

class StickerScope extends InheritedWidget {
  const StickerScope({required this.gateway, required super.child, super.key});
  final StickerGateway gateway;
  static StickerGateway? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StickerScope>()?.gateway;
  @override
  bool updateShouldNotify(StickerScope oldWidget) =>
      gateway != oldWidget.gateway;
}

class StickerArt extends StatelessWidget {
  const StickerArt(this.sticker, {this.size = 120, super.key});
  final ChatSticker sticker;
  final double size;
  @override
  Widget build(BuildContext context) {
    final gateway = StickerScope.maybeOf(context);
    if (sticker.asset != null) {
      return SizedBox.square(
          dimension: size,
          child: ClipRect(
              child: OverflowBox(
                  alignment: Alignment.topLeft,
                  minWidth: size * 2,
                  maxWidth: size * 2,
                  minHeight: size * 2,
                  maxHeight: size * 2,
                  child: Transform.translate(
                      offset: Offset(-(sticker.index % 2) * size,
                          -(sticker.index ~/ 2) * size),
                      child: Image.asset(sticker.asset!,
                          width: size * 2,
                          height: size * 2,
                          fit: BoxFit.fill)))));
    }
    return SizedBox.square(
        dimension: size,
        child: gateway == null
            ? const Icon(Icons.image_outlined, color: Color(0xFF9AA89A))
            : Image.network(gateway.stickerImageUrl(sticker.id),
                headers: {
                  if (gateway.stickerToken != null)
                    'Authorization': 'Bearer ${gateway.stickerToken}'
                },
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                    Icons.broken_image_outlined,
                    color: Color(0xFF9AA89A))));
  }
}

class StickerMessageView extends StatelessWidget {
  const StickerMessageView(this.sticker, {super.key});
  final ChatSticker sticker;
  @override
  Widget build(BuildContext context) => Semantics(
      label: '表情：${sticker.label}',
      child: SizedBox(
          width: 140,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            StickerArt(sticker),
            Text(sticker.label,
                maxLines: 2,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF67554F),
                    height: 1.25,
                    shadows: [
                      Shadow(color: Colors.white, blurRadius: 2),
                      Shadow(color: Colors.white, blurRadius: 4)
                    ]))
          ])));
}

class StickerPanel extends StatefulWidget {
  const StickerPanel({required this.onSend, this.enabled = true, super.key});
  final ValueChanged<ChatSticker> onSend;
  final bool enabled;
  @override
  State<StickerPanel> createState() => _StickerPanelState();
}

class _StickerPanelState extends State<StickerPanel> {
  final _scroll = ScrollController();
  List<ChatSticker> _custom = [];
  bool _busy = false, _failed = false, _loaded = false;
  StickerGateway? _gateway;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final gateway = StickerScope.maybeOf(context);
    if (!_loaded || gateway != _gateway) {
      _loaded = true;
      _gateway = gateway;
      _load();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await _gateway?.listStickers() ?? <ChatSticker>[];
      if (mounted) {
        setState(() {
          _custom = rows;
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _add() async {
    if (_busy) return;
    if (_gateway == null) {
      showCenterToast(context, '请先登录再添加表情');
      return;
    }
    setState(() => _busy = true);
    try {
      final image = await const MethodChannel('bingo/device_tools')
          .invokeMapMethod<String, dynamic>('pickStickerImage');
      if (image == null || !mounted) return;
      final bytes = image['bytes'] as Uint8List;
      final edit = TextEditingController();
      final label = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
                  scrollable: true,
                  title: const Text('给表情加句话'),
                  content: Column(mainAxisSize: MainAxisSize.min, children: [
                    SizedBox(
                        height: 110,
                        child: Image.memory(bytes, fit: BoxFit.contain)),
                    const SizedBox(height: 14),
                    TextField(
                        controller: edit,
                        maxLength: 30,
                        autofocus: true,
                        decoration: const InputDecoration(
                            hintText: '例如：抱抱、晚安啦',
                            helperText: '文字会随表情一起展示，AI 也能理解。'))
                  ]),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('取消')),
                    TextButton(
                        onPressed: () {
                          if (edit.text.trim().isNotEmpty) {
                            Navigator.pop(context, edit.text.trim());
                          }
                        },
                        child: const Text('添加'))
                  ]));
      await Future<void>.delayed(const Duration(milliseconds: 250));
      edit.dispose();
      if (label == null || !mounted) return;
      final saved = await _gateway!
          .uploadSticker(bytes, image['mime_type'] as String, label);
      if (!mounted) return;
      setState(() {
        _custom.removeWhere((s) => s.id == saved.id);
        _custom.add(saved);
        _failed = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut);
        }
      });
      showCenterToast(context, '已添加到我的表情');
    } catch (_) {
      if (mounted) {
        showCenterToast(context, '添加失败，请选择不超过 5 MB 的 PNG、JPG、GIF 或 WebP 图片后重试');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(ChatSticker sticker) async {
    final yes = await showModalBottomSheet<bool>(
        context: context,
        builder: (context) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                  title: const Text('移除此表情'),
                  onTap: () => Navigator.pop(context, true)),
              ListTile(
                  title: const Text('取消'),
                  onTap: () => Navigator.pop(context, false))
            ])));
    if (yes != true) return;
    try {
      await _gateway!.deleteSticker(sticker.id);
      if (mounted) {
        setState(() => _custom.removeWhere((s) => s.id == sticker.id));
      }
    } catch (_) {
      if (mounted) showCenterToast(context, '移除失败，请重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    final stickers = [...ChatSticker.builtins, ..._custom];
    return SizedBox(
        height: math.min(300, MediaQuery.sizeOf(context).height * .39),
        child: ColoredBox(
            color: const Color(0xFFEEEEEE),
            child: GridView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(10),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: .82),
                itemCount: stickers.length + 1 + (_failed ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Semantics(
                        label: '添加自己的表情',
                        button: true,
                        child: InkWell(
                            onTap: _busy ? null : _add,
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                                padding: const EdgeInsets.only(bottom: 20),
                                child: CustomPaint(
                                    painter: const _DashedFrame(),
                                    child: Center(
                                        child: _busy
                                            ? const SizedBox.square(
                                                dimension: 22,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2))
                                            : const Icon(Icons.add_rounded,
                                                size: 36,
                                                color: Color(0xFF657065)))))));
                  }
                  if (index > stickers.length) {
                    return TextButton(
                        onPressed: _load,
                        child:
                            const Text('重新加载', style: TextStyle(fontSize: 11)));
                  }
                  final sticker = stickers[index - 1];
                  return Semantics(
                      label: '发送表情：${sticker.label}',
                      button: true,
                      child: InkWell(
                          onTap: widget.enabled
                              ? () => widget.onSend(sticker)
                              : null,
                          onLongPress:
                              sticker.custom ? () => _remove(sticker) : null,
                          child: Column(children: [
                            Expanded(
                                child: Center(
                                    child: FittedBox(
                                        fit: BoxFit.contain,
                                        child: StickerArt(sticker, size: 80)))),
                            const SizedBox(height: 2),
                            Text(sticker.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    fontSize: 12,
                                    height: 1.3,
                                    color: Color(0xFF665650),
                                    fontWeight: FontWeight.w600))
                          ])));
                })));
  }
}

class _DashedFrame extends CustomPainter {
  const _DashedFrame();
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
          Offset.zero & size, const Radius.circular(8)));
    final paint = Paint()
      ..color = const Color(0xFF939D91)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metric in path.computeMetrics()) {
      for (double d = 0; d < metric.length; d += 9) {
        canvas.drawPath(
            metric.extractPath(d, math.min(d + 5, metric.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedFrame old) => false;
}
