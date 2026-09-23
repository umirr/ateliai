import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storyloom/selection_scroll.dart';

void main() {
  testWidgets(
    'drag selection reaches long text end with bounded scrolling and copies across paragraphs',
    (tester) async {
      var clipboard = '';
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          if (call.method == 'Clipboard.getData') return {'text': clipboard};
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final scroll = SelectionScrollController();
      final body = List.generate(40, (i) => 'line $i text').join('\n');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                height: 180,
                child: Listener(
                  onPointerDown: (_) => scroll.selecting = true,
                  onPointerUp: (_) => scroll.selecting = false,
                  child: SelectionArea(
                    child: SingleChildScrollView(
                      key: const ValueKey('viewport'),
                      controller: scroll,
                      child: Text(
                        body,
                        style: const TextStyle(fontSize: 18, height: 1.5),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final rect = tester.getRect(find.byKey(const ValueKey('viewport')));
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: rect.topLeft + const Offset(1, 10));
      await gesture.down(rect.topLeft + const Offset(1, 10));
      await gesture.moveTo(rect.bottomRight + const Offset(-10, 30));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(scroll.offset, lessThanOrEqualTo(25));
      for (var i = 0; i < 70; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(scroll.offset, closeTo(scroll.position.maxScrollExtent, 1));
      await gesture.up();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      final copied = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
      expect(copied, contains('line 0 text\nline 1 text'));
      expect(copied, contains('line 39 text'));
      await gesture.removePointer();
      await tester.pumpWidget(const SizedBox());
      scroll.dispose();
    },
  );
}
