import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/core/widgets/center_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class AvatarCropPage extends StatefulWidget {
  const AvatarCropPage({required this.image, super.key});
  final Uint8List image;

  @override
  State<AvatarCropPage> createState() => _AvatarCropPageState();
}

class _AvatarCropPageState extends State<AvatarCropPage> {
  final _boundary = GlobalKey();
  final _transform = TransformationController();
  bool _saving = false;
  Size? _imageSize;
  double? _diameter;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  Future<void> _decode() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.image);
      final frame = await codec.getNextFrame();
      final size =
          Size(frame.image.width.toDouble(), frame.image.height.toDouble());
      frame.image.dispose();
      codec.dispose();
      if (mounted) setState(() => _imageSize = size);
    } on Exception {
      if (mounted) {
        showCenterToast(context, '无法读取这张图片，请重新选择');
        Navigator.of(context).pop();
      }
    }
  }

  Size _displaySize(double diameter) {
    final size = _imageSize!;
    final scale = diameter / size.shortestSide;
    return Size(size.width * scale, size.height * scale);
  }

  void _reset() {
    if (_diameter == null || _imageSize == null) return;
    final size = _displaySize(_diameter!);
    _transform.value = Matrix4.identity()
      ..translateByDouble(
          (_diameter! - size.width) / 2, (_diameter! - size.height) / 2, 0, 1);
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary =
          _boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image =
          await boundary.toImage(pixelRatio: 512 / boundary.size.width);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (mounted && data != null) {
        Navigator.of(context).pop(data.buffer.asUint8List());
      }
    } on Exception {
      if (mounted) showCenterToast(context, '头像裁剪失败，请重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('裁剪头像')),
        body: SafeArea(
            child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(children: [
            const Spacer(),
            const Text('拖动调整位置，双指放大图片',
                style: TextStyle(color: BingoPalette.blue, fontSize: 16)),
            const SizedBox(height: 28),
            LayoutBuilder(builder: (context, constraints) {
              final diameter = constraints.maxWidth.clamp(200.0, 340.0);
              if (_imageSize == null) {
                return SizedBox.square(
                    dimension: diameter,
                    child: const Center(child: CircularProgressIndicator()));
              }
              if (_diameter != diameter) {
                _diameter = diameter;
                _reset();
              }
              final display = _displaySize(diameter);
              return Container(
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: BingoPalette.cyan, width: 3)),
                child: RepaintBoundary(
                    key: _boundary,
                    child: ClipOval(
                      child: SizedBox.square(
                        dimension: diameter,
                        child: InteractiveViewer(
                          transformationController: _transform,
                          constrained: false,
                          alignment: Alignment.topLeft,
                          minScale: 1,
                          maxScale: 5,
                          child: Image.memory(widget.image,
                              width: display.width,
                              height: display.height,
                              fit: BoxFit.fill),
                        ),
                      ),
                    )),
              );
            }),
            const SizedBox(height: 20),
            TextButton(onPressed: _reset, child: const Text('重置位置')),
            const Spacer(),
            SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving || _imageSize == null ? null : _save,
                  child: Text(_saving ? '正在保存…' : '使用这张头像'),
                )),
          ]),
        )),
      );
}
