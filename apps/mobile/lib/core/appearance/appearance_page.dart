import 'package:bingo/core/theme/app_theme.dart';
import 'package:bingo/shared/widgets/assistant_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bingo/core/appearance/chat_appearance.dart';
import 'package:bingo/core/widgets/center_toast.dart';

class AppearancePage extends StatefulWidget {
  const AppearancePage(
      {required this.store,
      this.roleId,
      this.partnerName,
      this.initialTab = 0,
      super.key});
  final AppearanceStore store;
  final String? roleId, partnerName;
  final int initialTab;
  @override
  State<AppearancePage> createState() => _AppearancePageState();
}

class _AppearancePageState extends State<AppearancePage> {
  late ChatAppearance _draft;
  bool _saving = false, _picking = false;
  int _tab = 0;
  @override
  void initState() {
    super.initState();
    _draft = widget.store.effective(widget.roleId);
    _tab = widget.initialTab == 1 ? 1 : 2;
  }

  Future<void> _save({bool reset = false}) async {
    setState(() => _saving = true);
    try {
      await widget.store.save(reset ? null : _draft, roleId: widget.roleId);
      if (!mounted) return;
      Navigator.of(context).pop();
      showCenterToast(context, reset ? '已恢复默认设置' : '聊天外观已保存');
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        showCenterToast(context, '保存失败，请重试');
      }
    }
  }

  Future<void> _pickPhoto() async {
    setState(() => _picking = true);
    try {
      final result = await const MethodChannel('bingo/device_tools')
          .invokeMapMethod<String, dynamic>('pickImage');
      if (!mounted || result == null) return;
      final bytes = result['bytes'] as Uint8List?;
      if (bytes == null) return;
      final path = await widget.store.importPhoto(bytes);
      if (mounted) {
        setState(() => _draft = _draft.copyWith(
            background: 'photo', photo: path, fade: 0, x: 0, y: 0, zoom: 1));
      }
    } catch (_) {
      if (mounted) showCenterToast(context, '无法读取图片，请重试');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final skins = _tab == 1 ? ChatSkin.originals : ChatSkin.all;
    return PopScope(
        canPop: !_saving && !_picking,
        child: Scaffold(
            backgroundColor: BingoPalette.pageTop,
            appBar:
                AppBar(title: const Text('聊天外观'), centerTitle: true, actions: [
              TextButton(
                  onPressed:
                      _saving || _picking ? null : () => _save(reset: true),
                  child: Text(widget.roleId == null ? '恢复默认' : '跟随全局',
                      style: const TextStyle(fontSize: 11)))
            ]),
            body: Column(children: [
              Padding(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
                  child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: SizedBox(
                          height: 154,
                          child: AppearanceScope(
                              value: _draft,
                              child: ChatWallpaper(
                                  value: _draft,
                                  child: Padding(
                                      padding: const EdgeInsets.all(14),
                                      child: LayoutBuilder(
                                          builder: (_, bounds) => FittedBox(
                                              fit: BoxFit.scaleDown,
                                              alignment: Alignment.topCenter,
                                              child: SizedBox(
                                                  width: bounds.maxWidth,
                                                  child: Column(children: [
                                                    Row(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          const AssistantAvatar(
                                                              role: '女朋友',
                                                              size: 40),
                                                          const SizedBox(
                                                              width: 8),
                                                          Flexible(
                                                              child: BubbleSurface(
                                                                  isUser: false,
                                                                  padding: const EdgeInsets
                                                                      .symmetric(
                                                                      horizontal:
                                                                          12,
                                                                      vertical:
                                                                          9),
                                                                  child: const Text(
                                                                      '今天的心情也很棒呢～',
                                                                      style: TextStyle(
                                                                          fontSize:
                                                                              12))))
                                                        ]),
                                                    const SizedBox(height: 12),
                                                    Align(
                                                        alignment: Alignment
                                                            .centerRight,
                                                        child: BubbleSurface(
                                                            isUser: true,
                                                            padding:
                                                                const EdgeInsets
                                                                    .symmetric(
                                                                    horizontal:
                                                                        12,
                                                                    vertical:
                                                                        9),
                                                            child: const Text(
                                                                '这个气泡好可爱！✨',
                                                                style: TextStyle(
                                                                    fontSize:
                                                                        12))))
                                                  ])))))))))),
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24)),
                      child: Row(children: [
                        for (final (i, label) in [(1, '背景'), (2, '气泡')])
                          Expanded(
                              child: TextButton(
                                  onPressed: _saving || _picking
                                      ? null
                                      : () => setState(() => _tab = i),
                                  style: TextButton.styleFrom(
                                      backgroundColor: _tab == i
                                          ? BingoPalette.primary
                                          : Colors.transparent,
                                      foregroundColor: _tab == i
                                          ? Colors.white
                                          : BingoPalette.muted,
                                      minimumSize: const Size(0, 37)),
                                  child: Text(label,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700))))
                      ]))),
              const SizedBox(height: 10),
              Expanded(
                  child: IgnorePointer(
                      ignoring: _saving || _picking,
                      child: CustomScrollView(
                          key: ValueKey('appearance-catalog-$_tab'),
                          slivers: [
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                              sliver: SliverGrid.builder(
                                itemCount: skins.length,
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 2,
                                        crossAxisSpacing: 12,
                                        mainAxisSpacing: 12,
                                        childAspectRatio:
                                            _tab == 1 ? 1.5 : 1.35),
                                itemBuilder: (_, index) => _tile(skins[index]),
                              ),
                            ),
                            if (_tab == 1)
                              SliverPadding(
                                  padding:
                                      const EdgeInsets.fromLTRB(18, 0, 18, 18),
                                  sliver: SliverList.list(children: [
                                    const SizedBox(height: 14),
                                    OutlinedButton.icon(
                                        onPressed: _picking ? null : _pickPhoto,
                                        icon: const Icon(
                                            Icons.add_photo_alternate_outlined),
                                        label: const Text('从相册选择背景')),
                                    if (_draft.photo != null)
                                      TextButton(
                                          onPressed: () => setState(() =>
                                              _draft = _draft.copyWith(
                                                  background: 'photo',
                                                  fade: 0)),
                                          child: const Text('使用我的照片')),
                                    if (_draft.background == 'photo') ...[
                                      _slider(
                                          '背景淡化',
                                          _draft.fade,
                                          0,
                                          .85,
                                          (v) => _draft =
                                              _draft.copyWith(fade: v)),
                                      _slider(
                                          '照片缩放',
                                          _draft.zoom,
                                          1,
                                          2.5,
                                          (v) => _draft =
                                              _draft.copyWith(zoom: v)),
                                      _slider(
                                          '左右位置',
                                          _draft.x,
                                          -1,
                                          1,
                                          (v) =>
                                              _draft = _draft.copyWith(x: v)),
                                      _slider('上下位置', _draft.y, -1, 1,
                                          (v) => _draft = _draft.copyWith(y: v))
                                    ]
                                  ]))
                          ])))
            ]),
            bottomNavigationBar: SafeArea(
                top: false,
                child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
                    child: FilledButton(
                        onPressed: _saving || _picking ? null : () => _save(),
                        child: Text(_saving
                            ? '正在保存…'
                            : widget.roleId == null
                                ? '保存为默认外观'
                                : '应用到当前聊天'))))));
  }

  Widget _slider(String label, double value, double min, double max,
          void Function(double) change) =>
      Row(children: [
        SizedBox(
            width: 66,
            child: Text(label, style: const TextStyle(fontSize: 12))),
        Expanded(
            child: Slider(
                value: value,
                min: min,
                max: max,
                semanticFormatterCallback: (v) => label == '照片缩放'
                    ? '${v.toStringAsFixed(1)}倍'
                    : '${(v * 100).round()}%',
                onChanged: (v) => setState(() => change(v)))),
        SizedBox(
            width: 42,
            child: Text(
                label == '照片缩放'
                    ? '${value.toStringAsFixed(1)}×'
                    : '${(value * 100).round()}%',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 11, color: Color(0xFF718078))))
      ]);

  Widget _tile(ChatSkin skin) {
    final selected =
        _tab == 1 ? _draft.background == skin.id : _draft.bubble == skin.id;
    return Semantics(
        key: ValueKey('appearance-skin-${skin.id}'),
        selected: selected,
        button: true,
        label: skin.name,
        child: InkWell(
            onTap: () => setState(() => _draft = _draft.copyWith(
                background: _tab == 1 ? skin.id : null,
                bubble: _tab == 2 ? skin.id : null)),
            borderRadius: BorderRadius.circular(16),
            child: Container(
                decoration: BoxDecoration(
                    color: Color.lerp(skin.user, Colors.white, .55),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: selected
                            ? BingoPalette.primary
                            : Colors.transparent,
                        width: 1.5)),
                child: Stack(children: [
                  Column(children: [
                    Expanded(
                        child: Padding(
                            padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                            child: _tab == 1
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: ChatWallpaper(
                                        value:
                                            ChatAppearance(background: skin.id),
                                        child: const SizedBox.expand()))
                                : Center(
                                    child: SkinBubbleFrame(
                                        skin: skin,
                                        isUser: true,
                                        compact: true,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 25, vertical: 13),
                                        child: const SizedBox(
                                            width: 70, height: 9))))),
                    Padding(
                        padding: const EdgeInsets.only(bottom: 7, top: 2),
                        child: Text(skin.name,
                            maxLines: 1,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: selected
                                    ? BingoPalette.primary
                                    : BingoPalette.ink)))
                  ]),
                  if (selected)
                    const Positioned(
                        top: 4,
                        right: 4,
                        child: Icon(Icons.check_circle_rounded,
                            color: BingoPalette.primary, size: 19))
                ]))));
  }
}
