import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart' as q;
import 'package:flutter_quill/src/editor/widgets/text/text_line.dart';
import 'package:flutter_quill/src/editor/widgets/proxy.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/gestures.dart';
import 'package:storyloom/rich_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late q.QuillController controller;
  var changes = 0;
  Future<void> setup(
    WidgetTester tester, {
    String text = '',
    double lineHeight = 1.8,
  }) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.view.physicalSize = const Size(1000, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    controller = documentController({'body': text});
    changes = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        localizationsDelegates: const [q.FlutterQuillLocalizations.delegate],
        supportedLocales: const [Locale('en')],
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SizedBox.expand(
              child: RichEditor(
                controller: controller,
                lineHeight: lineHeight,
                expanded: true,
                onChanged: () => setState(() => changes++),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    tester
        .widget<q.QuillEditor>(find.byType(q.QuillEditor))
        .focusNode
        .requestFocus();
    await tester.pump();
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    debugDefaultTargetPlatformOverride = null;
    await tester.pump();
  }

  Future<void> key(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pump();
  }

  void select(int start, int end) {
    controller.updateSelection(
      TextSelection(baseOffset: start, extentOffset: end),
      q.ChangeSource.local,
    );
  }

  testWidgets(
    'drag into unfocused editor attaches selected range and native typing replaces it',
    (tester) async {
      await setup(tester, text: '앞부분 선택할글 뒷부분');
      final editor = tester.widget<q.QuillEditor>(find.byType(q.QuillEditor));
      editor.focusNode.unfocus();
      await tester.pumpAndSettle();
      expect(editor.focusNode.hasFocus, isFalse);
      final line = tester.allRenderObjects
          .whereType<RenderEditableTextLine>()
          .first;
      final from = line.localToGlobal(
        line.getLocalRectForCaret(const TextPosition(offset: 4)).center,
      );
      final to = line.localToGlobal(
        line.getLocalRectForCaret(const TextPosition(offset: 8)).center,
      );
      final drag = await tester.startGesture(
        from,
        kind: PointerDeviceKind.mouse,
      );
      await drag.moveTo(to);
      await tester.pump(const Duration(milliseconds: 80));
      await drag.up();
      await tester.pump();
      expect(editor.focusNode.hasFocus, isTrue);
      expect(tester.testTextInput.hasAnyClients, isTrue);
      expect(controller.selection.isCollapsed, isFalse);
      final old = controller.document.toPlainText();
      final selected = controller.selection;
      for (final inserted in ['ㅎ', '하', '한']) {
        final next = old.replaceRange(selected.start, selected.end, inserted);
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: next,
            selection: TextSelection.collapsed(
              offset: selected.start + inserted.length,
            ),
            composing: TextRange(
              start: selected.start,
              end: selected.start + inserted.length,
            ),
          ),
        );
        await tester.pump();
        expect(controller.document.toPlainText(), next);
      }
      await dispose(tester);
    },
  );

  testWidgets(
    'list markers share first text baseline across font sizes and line spacing',
    (tester) async {
      for (final type in ['ordered', 'bullet', 'unchecked']) {
        await setup(tester, text: '첫 번째 항목의 내용', lineHeight: 2.4);
        controller.formatText(
          0,
          controller.document.length,
          q.Attribute.fromKeyValue('list', type),
        );
        for (final size in [12.0, 24.0, 53.333]) {
          controller.formatText(
            0,
            controller.document.length - 1,
            q.Attribute.fromKeyValue('size', '$size'),
          );
          await tester.pump();
          final line = tester.allRenderObjects
              .whereType<RenderEditableTextLine>()
              .first;
          final children = <RenderBox>[];
          line.visitChildren((c) {
            children.add(c as RenderBox);
          });
          final body = children.whereType<RenderParagraphProxy>().single;
          final leading = children.firstWhere((c) => c != body);
          if (type != 'unchecked') {
            final a = leading
                .localToGlobal(
                  Offset(
                    0,
                    leading.getDryBaseline(
                      leading.constraints,
                      TextBaseline.alphabetic,
                    )!,
                  ),
                )
                .dy;
            final b = body
                .localToGlobal(
                  Offset(
                    0,
                    body.getDryBaseline(
                      body.constraints,
                      TextBaseline.alphabetic,
                    )!,
                  ),
                )
                .dy;
            expect(a, closeTo(b, .5), reason: '$type $size');
          } else {
            final box = body
                .getBoxesForSelection(
                  const TextSelection(baseOffset: 0, extentOffset: 1),
                )
                .first;
            final center = body
                .localToGlobal(Offset(0, (box.top + box.bottom) / 2))
                .dy;
            expect(
              leading.localToGlobal(leading.size.center(Offset.zero)).dy,
              closeTo(center, .5),
            );
          }
        }
        await dispose(tester);
      }
    },
  );

  testWidgets(
    'caret center follows actual Pretendard glyph bounds at every size and line spacing',
    (tester) async {
      await (FontLoader('Pretendard')
            ..addFont(rootBundle.load('assets/fonts/PretendardVariable.ttf')))
          .load();
      for (final spacing in [1.4, 1.8, 2.4]) {
        await setup(tester, text: '한글 English', lineHeight: spacing);
        for (final pt in [8, 12, 14, 18, 24, 32, 40]) {
          controller.formatText(
            0,
            10,
            q.Attribute.fromKeyValue('size', '${pt * 4 / 3}'),
          );
          select(1, 1);
          await tester.pump();
          final line = tester.allRenderObjects
              .whereType<RenderEditableTextLine>()
              .first;
          final proxy = tester.allRenderObjects
              .whereType<RenderParagraphProxy>()
              .first;
          final glyph = proxy
              .getBoxesForSelection(
                const TextSelection(baseOffset: 0, extentOffset: 1),
              )
              .first;
          final glyphCenter = proxy
              .localToGlobal(Offset(0, (glyph.top + glyph.bottom) / 2))
              .dy;
          final caret = line.getLocalRectForCaret(
            const TextPosition(offset: 1),
          );
          final caretCenter = line.localToGlobal(caret.center).dy;
          expect(
            caretCenter,
            closeTo(glyphCenter, .5),
            reason: '$pt pt, spacing $spacing',
          );
        }
        await dispose(tester);
      }
    },
  );

  testWidgets(
    'IME owns backspace enter and arrows during active Korean composition',
    (tester) async {
      await setup(tester, text: '앞 한');
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '앞 한\n',
          selection: TextSelection.collapsed(offset: 3),
          composing: TextRange(start: 2, end: 3),
        ),
      );
      await tester.pump();
      for (final keyCode in [
        LogicalKeyboardKey.backspace,
        LogicalKeyboardKey.enter,
        LogicalKeyboardKey.arrowLeft,
      ]) {
        await key(tester, keyCode);
        expect(
          controller.document.toPlainText(),
          '앞 한\n',
          reason: 'Native IME must apply $keyCode exactly once',
        );
        expect(controller.selection.extentOffset, 3);
      }
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '앞 하\n',
          selection: TextSelection.collapsed(offset: 3),
          composing: TextRange(start: 2, end: 3),
        ),
      );
      await tester.pump();
      expect(controller.document.toPlainText(), '앞 하\n');
      await dispose(tester);
    },
  );

  testWidgets(
    'desktop local deletion synchronizes native buffer before the next IME edit',
    (tester) async {
      await setup(tester, text: '앞문장 삭제할글 뒷문장');
      select(4, 8);
      await tester.pump();
      tester.testTextInput.log.clear();
      await key(tester, LogicalKeyboardKey.backspace);
      final expected = controller.document.toPlainText();
      final updates = tester.testTextInput.log
          .where((c) => c.method == 'TextInput.setEditingState')
          .toList();
      expect(updates, isNotEmpty);
      expect((updates.last.arguments as Map)['text'], expected);
      final at = controller.selection.extentOffset;
      for (final composing in ['ㅎ', '하', '한']) {
        final next =
            expected.substring(0, at) + composing + expected.substring(at);
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: next,
            selection: TextSelection.collapsed(offset: at + composing.length),
            composing: TextRange(start: at, end: at + composing.length),
          ),
        );
        await tester.pump();
        expect(controller.document.toPlainText(), next);
      }
      await dispose(tester);
    },
  );

  testWidgets(
    'editor drag selection scrolls down and up while pointer stays at edge',
    (tester) async {
      await setup(
        tester,
        text: List.generate(70, (i) => '줄 $i 긴 문장 선택 시험').join('\n'),
      );
      final editor = tester.widget<q.QuillEditor>(find.byType(q.QuillEditor));
      final rect = tester.getRect(find.byKey(const ValueKey('rich-body')));
      final pointer = await tester.startGesture(
        rect.topLeft + const Offset(20, 26),
        kind: PointerDeviceKind.mouse,
      );
      await pointer.moveTo(Offset(rect.left + 80, rect.bottom - 3));
      for (var i = 0; i < 150; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(editor.scrollController.offset, greaterThan(300));
      expect(controller.selection.end, greaterThan(100));
      final down = editor.scrollController.offset;
      await pointer.moveTo(Offset(rect.left + 80, rect.top + 2));
      for (var i = 0; i < 100; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(editor.scrollController.offset, lessThan(down - 100));
      await pointer.up();
      final stopped = editor.scrollController.offset;
      await tester.pump(const Duration(milliseconds: 200));
      expect(editor.scrollController.offset, stopped);
      await dispose(tester);
    },
  );

  testWidgets(
    'IME composition does not echo intermediate state and Korean-layout Ctrl copy works',
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
      await setup(tester);
      for (final text in ['ㅎ', '하', '한', '한ㄱ', '한그', '한글']) {
        tester.testTextInput.log.clear();
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length),
            composing: TextRange(start: text.length - 1, end: text.length),
          ),
        );
        await tester.pump();
        expect(controller.document.toPlainText(), '$text\n');
        expect(
          tester.testTextInput.log.where(
            (c) => c.method == 'TextInput.setEditingState',
          ),
          isEmpty,
        );
      }
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '한글',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      await tester.pump();
      select(0, 2);
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      final keyCallback = tester
          .widget<q.QuillEditor>(find.byType(q.QuillEditor))
          .config
          // ignore: experimental_member_use
          .onKeyPressed!;
      // The Windows simulator has no keyCode for Hangul labels; dispatch the
      // physical key event to the same editor handler directly.
      expect(
        keyCallback(
          const KeyDownEvent(
            physicalKey: PhysicalKeyboardKey.keyC,
            logicalKey: LogicalKeyboardKey(0x314a),
            timeStamp: Duration.zero,
          ),
          null,
        ),
        KeyEventResult.handled,
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect((await Clipboard.getData(Clipboard.kTextPlain))?.text, '한글');
      await dispose(tester);
    },
  );
  testWidgets(
    'typing and Korean IME keep the same editor focus across rebuilds',
    (tester) async {
      await setup(tester);
      final focus = tester
          .widget<q.QuillEditor>(find.byType(q.QuillEditor))
          .focusNode;
      for (final value in ['ㅎ', '하', '한', '한글', '한글 입력']) {
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: '$value\n',
            selection: TextSelection.collapsed(offset: value.length),
            composing: TextRange(start: 0, end: value.length),
          ),
        );
        await tester.pump();
        expect(focus.hasFocus, isTrue);
        expect(
          identical(
            focus,
            tester.widget<q.QuillEditor>(find.byType(q.QuillEditor)).focusNode,
          ),
          isTrue,
        );
      }
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '한글 입력\n',
          selection: TextSelection.collapsed(offset: 5),
        ),
      );
      await tester.pump();
      expect(controller.document.toPlainText(), '한글 입력\n');
      expect(changes, greaterThan(0));
      await key(tester, LogicalKeyboardKey.backspace);
      expect(controller.document.toPlainText(), '한글 입\n');
      expect(focus.hasFocus, isTrue);
      await dispose(tester);
    },
  );
  testWidgets(
    'backspace delete enter arrows and space stay inside the document',
    (tester) async {
      await setup(tester, text: 'abc\ndef');
      select(3, 3);
      await tester.pump();
      await key(tester, LogicalKeyboardKey.backspace);
      expect(controller.document.toPlainText(), 'ab\ndef\n');
      await key(tester, LogicalKeyboardKey.enter);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'ab\n\ndef\n',
          selection: TextSelection.collapsed(offset: 3),
        ),
      );
      await tester.pump();
      expect(controller.document.toPlainText(), 'ab\n\ndef\n');
      await key(tester, LogicalKeyboardKey.arrowDown);
      expect(controller.selection.baseOffset, greaterThan(3));
      await key(tester, LogicalKeyboardKey.arrowLeft);
      await key(tester, LogicalKeyboardKey.arrowRight);
      await key(tester, LogicalKeyboardKey.space);
      expect(
        tester
            .widget<q.QuillEditor>(find.byType(q.QuillEditor))
            .focusNode
            .hasFocus,
        isTrue,
      );
      select(0, 0);
      await key(tester, LogicalKeyboardKey.delete);
      expect(controller.document.toPlainText(), startsWith('b'));
      final cursor = tester.allRenderObjects
          .whereType<RenderEditableTextLine>()
          .first
          .cursorCont;
      final before = cursor.blink.value;
      await tester.pump(const Duration(milliseconds: 500));
      expect(cursor.blink.value, isNot(before));
      await tester.pump(const Duration(milliseconds: 500));
      expect(cursor.blink.value, before);
      expect(
        tester
            .widget<q.QuillEditor>(find.byType(q.QuillEditor))
            .config
            .showCursor,
        isTrue,
      );
      await dispose(tester);
    },
  );
  testWidgets(
    'multiline selection replacement and emoji deletion preserve boundaries',
    (tester) async {
      await setup(tester, text: '첫째\n둘째\n셋째');
      select(0, 6);
      await tester.pump();
      await key(tester, LogicalKeyboardKey.backspace);
      expect(controller.document.toPlainText(), '셋째\n');
      controller.replaceText(
        0,
        0,
        '😀',
        const TextSelection.collapsed(offset: 2),
      );
      await tester.pump();
      await key(tester, LogicalKeyboardKey.backspace);
      expect(controller.document.toPlainText(), '셋째\n');
      await dispose(tester);
    },
  );
  testWidgets(
    'external paste preserves CRLF blank lines and selected replacement',
    (tester) async {
      await setup(tester, text: '기존');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.getData') {
            return {'text': '첫째\r\n\r\n둘째\n셋째'};
          }
          return null;
        },
      );
      select(0, 2);
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await key(tester, LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(controller.document.toPlainText(), '첫째\n\n둘째\n셋째\n');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
      await dispose(tester);
    },
  );
  testWidgets(
    'formatting toggles selection and supports insertion style with point sizes',
    (tester) async {
      await setup(tester, text: 'alpha beta');
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == '굵게',
              ),
            )
            .onPressed,
        isNotNull,
      );
      controller.formatSelection(q.Attribute.bold);
      expect(
        controller.document.toDelta().toJson().first['attributes'],
        isNull,
      );
      controller.formatSelection(q.Attribute.clone(q.Attribute.bold, null));
      select(0, 5);
      await tester.pump();
      await tester.tap(find.byTooltip('굵게'));
      await tester.pump();
      expect(
        controller.document.toDelta().toJson().first['attributes'],
        containsPair('bold', true),
      );
      expect(controller.document.toDelta().toJson()[1]['attributes'], isNull);
      final menu = find.byType(DropdownButton<int>).first;
      await tester.tap(menu);
      await tester.pumpAndSettle();
      for (final n in [8, 12, 14, 18, 24, 32, 40]) {
        expect(find.text('$n pt'), findsWidgets);
      }
      await tester.tap(find.text('24 pt').last);
      await tester.pumpAndSettle();
      expect(
        controller.document.toDelta().toJson().first['attributes'],
        containsPair('size', '32.0'),
      );
      await dispose(tester);
    },
  );
  testWidgets('search is inline and toolbar has fixed height', (tester) async {
    await setup(tester, text: 'alpha beta alpha');
    final y = tester.getTopLeft(find.byKey(const ValueKey('rich-body'))).dy;
    expect(
      tester.getSize(find.byKey(const ValueKey('text-toolbar'))).height,
      96,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('text-toolbar')),
        matching: find.byType(SingleChildScrollView),
      ),
      findsNothing,
    );
    select(0, 5);
    await tester.pump();
    expect(tester.getTopLeft(find.byKey(const ValueKey('rich-body'))).dy, y);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await key(tester, LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.byType(Dialog), findsNothing);
    expect(find.byKey(const ValueKey('document-search')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('document-search')),
      'alpha',
    );
    await tester.pump();
    expect(
      controller.selection,
      const TextSelection(baseOffset: 0, extentOffset: 5),
    );
    await tester.tap(find.byTooltip('다음 결과'));
    await tester.pump();
    expect(
      controller.selection,
      const TextSelection(baseOffset: 11, extentOffset: 16),
    );
    await dispose(tester);
  });
  testWidgets(
    'numbered marker follows centered paragraph and selection remains valid',
    (tester) async {
      await setup(tester, text: 'Centered item');
      select(0, 13);
      await tester.pump();
      await tester.tap(find.byTooltip('가운데 정렬'));
      await tester.pump();
      await tester.tap(find.byTooltip('번호 목록'));
      await tester.pump();
      final render = tester.allRenderObjects
          .whereType<RenderEditableTextLine>()
          .firstWhere((r) => r.children.containsKey(TextLineSlot.leading));
      final marker = render.children[TextLineSlot.leading]!;
      expect((marker.parentData as BoxParentData).offset.dx, greaterThan(100));
      expect(
        controller.document.toDelta().toJson().last['attributes'],
        containsPair('align', 'center'),
      );
      expect(
        controller.document.toDelta().toJson().last['attributes'],
        containsPair('list', 'ordered'),
      );
      await dispose(tester);
    },
  );
  testWidgets(
    'context paste keeps blank lines and undo redo restores pasted text',
    (tester) async {
      await setup(tester, text: 'start');
      select(0, 5);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.getData') return {'text': 'A\r\n\r\nB'};
          return null;
        },
      );
      await (controller as SelectionQuillController).clipboardPaste();
      await tester.pump();
      expect(controller.document.toPlainText(), 'A\n\nB\n');
      controller.undo();
      await tester.pump();
      expect(controller.document.toPlainText(), 'start\n');
      controller.redo();
      await tester.pump();
      expect(controller.document.toPlainText(), 'A\n\nB\n');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
      await dispose(tester);
    },
  );
  testWidgets(
    'repeated deletion stops at an empty document without losing focus',
    (tester) async {
      await setup(tester, text: '가나다 abc');
      select(7, 7);
      await tester.pump();
      for (var i = 0; i < 12; i++) {
        await key(tester, LogicalKeyboardKey.backspace);
        expect(
          tester
              .widget<q.QuillEditor>(find.byType(q.QuillEditor))
              .focusNode
              .hasFocus,
          isTrue,
        );
      }
      expect(controller.document.toPlainText(), '\n');
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '다시 입력\n',
          selection: TextSelection.collapsed(offset: 5),
        ),
      );
      await tester.pump();
      expect(controller.document.toPlainText(), '다시 입력\n');
      await dispose(tester);
    },
  );
  testWidgets(
    'mouse dragged selection deletes and right click preserves selection',
    (tester) async {
      await setup(tester, text: 'alpha beta gamma');
      final line = tester.allRenderObjects
          .whereType<RenderEditableTextLine>()
          .first;
      final start = line.localToGlobal(
        line.getOffsetForCaret(const TextPosition(offset: 0)) +
            const Offset(2, 12),
      );
      final end = line.localToGlobal(
        line.getOffsetForCaret(const TextPosition(offset: 10)) +
            const Offset(2, 12),
      );
      final mouse = await tester.startGesture(
        start,
        kind: PointerDeviceKind.mouse,
      );
      await mouse.moveTo(end);
      await mouse.up();
      await tester.pump();
      expect(controller.selection.isCollapsed, isFalse);
      final selection = controller.selection;
      final expected = controller.document.toPlainText().replaceRange(
        selection.start,
        selection.end,
        '',
      );
      await key(tester, LogicalKeyboardKey.backspace);
      expect(controller.document.toPlainText(), expected);
      select(0, 2);
      await tester.pump();
      await tester.tapAt(start, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(find.text('복사  Ctrl+C'), findsOneWidget);
      await tester.tap(find.text('굵게  Ctrl+B'));
      await tester.pumpAndSettle();
      expect(
        controller.document.toDelta().toJson().first['attributes'],
        containsPair('bold', true),
      );
      await dispose(tester);
    },
  );
  testWidgets('Ctrl C X V roundtrip preserves formatting and blank lines', (
    tester,
  ) async {
    await setup(tester, text: 'alpha\n\nbeta');
    String clipboard = '';
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
    select(0, 5);
    controller.formatSelection(q.Attribute.bold);
    select(0, 11);
    await tester.pump();
    Future<void> shortcut(LogicalKeyboardKey k) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await key(tester, k);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    }

    await shortcut(LogicalKeyboardKey.keyC);
    expect(clipboard, 'alpha\n\nbeta');
    await shortcut(LogicalKeyboardKey.keyX);
    expect(controller.document.toPlainText(), '\n');
    await shortcut(LogicalKeyboardKey.keyV);
    expect(controller.document.toPlainText(), 'alpha\n\nbeta\n');
    expect(
      controller.document.toDelta().toJson().first['attributes'],
      containsPair('bold', true),
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
    await dispose(tester);
  });
  testWidgets(
    'hash titles remain ordinary editable text with distinct colors and sized caret',
    (tester) async {
      await setup(tester, text: '# purple\n## red\n### green\nnormal');
      final colors = tester.allRenderObjects
          .whereType<RenderParagraph>()
          .map((r) => r.text.style?.color)
          .toSet();
      expect(
        colors,
        containsAll([
          const Color(0xffb88ae8),
          const Color(0xffed7777),
          const Color(0xff72c698),
        ]),
      );
      expect(controller.document.toPlainText(), startsWith('# purple\n## red'));
      select(1, 1);
      await tester.pump();
      await key(tester, LogicalKeyboardKey.backspace);
      expect(controller.document.toPlainText(), startsWith(' purple'));
      select(0, 2);
      controller.formatSelection(q.Attribute.fromKeyValue('size', '16.0'));
      select(1, 1);
      await tester.pump();
      final line = tester.allRenderObjects
          .whereType<RenderEditableTextLine>()
          .first;
      expect(line.cursorHeight, closeTo(18.4, .1));
      await dispose(tester);
    },
  );
  testWidgets(
    'inline Markdown and collapsed formatting use ordinary insertion semantics',
    (tester) async {
      await setup(tester);
      for (final char in '**bold**'.split('')) {
        final at = controller.selection.end;
        controller.replaceText(
          at,
          0,
          char,
          TextSelection.collapsed(offset: at + 1),
        );
        await tester.pump();
      }
      expect(controller.document.toPlainText(), 'bold\n');
      expect(
        controller.document.toDelta().toJson().first['attributes'],
        containsPair('bold', true),
      );
      select(4, 4);
      await tester.pump();
      await tester.tap(find.byTooltip('밑줄'));
      await tester.pump();
      controller.replaceText(
        4,
        0,
        'X',
        const TextSelection.collapsed(offset: 5),
      );
      await tester.pump();
      expect(
        controller.document
            .toDelta()
            .toJson()
            .where((r) => r['insert'] == 'X')
            .first['attributes'],
        containsPair('underline', true),
      );
      await dispose(tester);
    },
  );
  testWidgets('typing follows caret in long body while toolbar remains fixed', (
    tester,
  ) async {
    await setup(tester, text: List.generate(200, (i) => 'line $i').join('\n'));
    final editor = tester.widget<q.QuillEditor>(find.byType(q.QuillEditor));
    final toolbarY = tester
        .getTopLeft(find.byKey(const ValueKey('text-toolbar')))
        .dy;
    final end = controller.document.length - 1;
    select(end, end);
    await tester.pump();
    controller.replaceText(
      end,
      0,
      'typing',
      TextSelection.collapsed(offset: end + 6),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(editor.scrollController.offset, greaterThan(1000));
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('text-toolbar'))).dy,
      toolbarY,
    );
    final scroll = editor.scrollController;
    scroll.jumpTo(scroll.position.maxScrollExtent / 2);
    await tester.pump();
    final before = scroll.offset;
    await tester.pump();
    expect(scroll.offset, before);
    await dispose(tester);
  });
}
