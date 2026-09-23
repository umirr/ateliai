import 'package:flutter/widgets.dart';

/// Keep framework selection auto-scroll at a readable maximum of 240 px/s.
class SelectionScrollController extends ScrollController {
  bool selecting = false;
  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _SelectionPosition(
    this,
    physics: physics,
    context: context,
    oldPosition: oldPosition,
  );
}

class _SelectionPosition extends ScrollPositionWithSingleContext {
  _SelectionPosition(
    this.owner, {
    required super.physics,
    required super.context,
    super.oldPosition,
  });
  final SelectionScrollController owner;
  @override
  Future<void> animateTo(
    double to, {
    required Duration duration,
    required Curve curve,
  }) {
    if (owner.selecting) {
      final minimum = Duration(
        microseconds: ((to - pixels).abs() / 240 * 1000000).ceil(),
      );
      if (minimum > duration) duration = minimum;
      curve = Curves.linear;
    }
    return super.animateTo(to, duration: duration, curve: curve);
  }
}
