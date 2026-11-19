import 'dart:math' as math;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A panel and the system keyboard share one bottom slot during IME transitions.
/// Reserving the larger height prevents briefly stacking both under the chat.
class ComposerPanelSpace extends SingleChildRenderObjectWidget {
  const ComposerPanelSpace(
      {required this.keyboardInset, required super.child, super.key});
  final double keyboardInset;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _PanelSpace(keyboardInset);
  @override
  void updateRenderObject(
      BuildContext context, covariant RenderObject renderObject) {
    (renderObject as _PanelSpace).keyboardInset = keyboardInset;
  }
}

class _PanelSpace extends RenderProxyBox {
  _PanelSpace(this._keyboardInset);
  double _keyboardInset;
  set keyboardInset(double value) {
    if (value == _keyboardInset) return;
    _keyboardInset = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    child?.layout(constraints.loosen(), parentUsesSize: true);
    final panel = child?.size ?? Size.zero;
    size = constraints
        .constrain(Size(panel.width, math.max(panel.height, _keyboardInset)));
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final panel = child?.getDryLayout(constraints.loosen()) ?? Size.zero;
    return constraints
        .constrain(Size(panel.width, math.max(panel.height, _keyboardInset)));
  }
}
