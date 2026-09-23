import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/src/editor/widgets/box.dart';
import 'package:flutter_quill/src/editor/widgets/cursor.dart';

class RecordingCanvas extends Fake implements Canvas {
  Rect? painted;
  @override
  void drawRect(Rect rect, Paint paint) {
    painted = rect;
  }
}

class CaretBody extends Fake implements RenderContentProxyBox {
  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) =>
      'CaretBody';
  @override
  Offset getOffsetForCaret(TextPosition position, Rect prototype) =>
      Offset.zero;
  @override
  double getFullHeightForCaret(TextPosition position) => 72;
  @override
  Offset localToGlobal(Offset point, {RenderObject? ancestor}) => point;
}

void main() {
  test(
    'Windows paint retains glyph-sized caret despite large line spacing',
    () {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final canvas = RecordingCanvas();
      CursorPainter(
        editable: CaretBody(),
        style: const CursorStyle(
          color: Colors.white,
          backgroundColor: Colors.black,
        ),
        prototype: const Rect.fromLTWH(0, 24, 2, 18),
        color: Colors.white,
        devicePixelRatio: 1,
      ).paint(canvas, Offset.zero, const TextPosition(offset: 0), false);
      expect(canvas.painted, const Rect.fromLTWH(0, 24, 2, 18));
    },
  );
}
