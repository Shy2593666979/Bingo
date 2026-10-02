import 'package:flutter/material.dart';

class PartnerSwipeCard extends StatefulWidget {
  const PartnerSwipeCard(
      {required this.child,
      required this.onEdit,
      this.onDelete,
      this.enabled = true,
      super.key});

  final Widget child;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;
  final bool enabled;

  @override
  State<PartnerSwipeCard> createState() => _PartnerSwipeCardState();
}

class _PartnerSwipeCardState extends State<PartnerSwipeCard> {
  double _offset = 0;
  bool _dragging = false;
  double get _width => widget.onDelete == null ? 72 : 144;

  void _close() {
    if (_offset != 0 && mounted) setState(() => _offset = 0);
  }

  void _settle(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    setState(() {
      _dragging = false;
      _offset = velocity < -300 || (velocity <= 300 && -_offset > _width * .35)
          ? -_width
          : 0;
    });
  }

  Widget _action(String label, IconData icon, Color background,
          Color foreground, VoidCallback callback) =>
      SizedBox(
          width: 72,
          child: Material(
              color: background,
              child: InkWell(
                  onTap: widget.enabled
                      ? () {
                          _close();
                          callback();
                        }
                      : null,
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, size: 21, color: foreground),
                        const SizedBox(height: 8),
                        Text(label,
                            style: TextStyle(color: foreground, fontSize: 12)),
                      ]))));

  @override
  Widget build(BuildContext context) => TapRegion(
      onTapOutside: (_) => _close(),
      child: ClipRRect(
          borderRadius: BorderRadius.circular(25),
          child: GestureDetector(
              onHorizontalDragStart: widget.enabled
                  ? (_) => setState(() => _dragging = true)
                  : null,
              onHorizontalDragUpdate: widget.enabled
                  ? (details) => setState(() => _offset =
                      (_offset + details.delta.dx).clamp(-_width, 0).toDouble())
                  : null,
              onHorizontalDragEnd: widget.enabled ? _settle : null,
              onHorizontalDragCancel: () => setState(() {
                    _dragging = false;
                    _offset = 0;
                  }),
              child: Stack(children: [
                if (_offset < 0)
                  Positioned.fill(
                      child: Align(
                          alignment: Alignment.centerRight,
                          child: Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _action(
                                    '编辑',
                                    Icons.edit_outlined,
                                    const Color(0xFFD6ECDF),
                                    const Color(0xFF438064),
                                    widget.onEdit),
                                if (widget.onDelete != null)
                                  _action(
                                      '删除',
                                      Icons.delete_outline_rounded,
                                      const Color(0xFFF7DFE0),
                                      const Color(0xFFC3676D),
                                      widget.onDelete!),
                              ]))),
                AnimatedContainer(
                    duration: Duration(milliseconds: _dragging ? 0 : 180),
                    curve: Curves.easeOut,
                    transform: Matrix4.translationValues(_offset, 0, 0),
                    child: widget.child),
              ]))));
}
