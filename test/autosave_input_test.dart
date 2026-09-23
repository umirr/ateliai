import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart' as q;
import 'package:storyloom/main.dart';
import 'package:storyloom/store.dart';
import 'package:storyloom/rich_editor.dart';
import 'widget_test.dart' show settleIo;

Iterable<String> compositionSteps(String char) sync* {
  final cp = char.runes.single;
  if (cp < 0xac00 || cp > 0xd7a3) {
    yield char;
    return;
  }
  final n = cp - 0xac00;
  const leading = [
    'ㄱ',
    'ㄲ',
    'ㄴ',
    'ㄷ',
    'ㄸ',
    'ㄹ',
    'ㅁ',
    'ㅂ',
    'ㅃ',
    'ㅅ',
    'ㅆ',
    'ㅇ',
    'ㅈ',
    'ㅉ',
    'ㅊ',
    'ㅋ',
    'ㅌ',
    'ㅍ',
    'ㅎ',
  ];
  yield leading[n ~/ 588];
  yield String.fromCharCode(cp - n % 28);
  if (n % 28 != 0) yield char;
}

void main() {
  const sentence = '오늘은 새로운 캐릭터의 성격과 이야기를 차분하게 정리합니다.';
  for (final autosave in [true, false]) {
    testWidgets(
      'fixed Korean sentence 5 repetitions at 40ms per composition step, autosave=$autosave',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        tester.view.physicalSize = const Size(1440, 960);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final root = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('ateliai-input-'),
        ))!;
        final db = WorkspaceStore(root);
        final initial = List.filled(
          80,
          List.filled(32, '긴 문장 english. ').join(),
        ).join('\n');
        await tester.runAsync(() async {
          await db.load();
          await db.setPreferences({'autosave': autosave});
          await db.save('character', {
            'title': '입력 검증',
            'body': initial,
            'directory': '',
            'tags': <String>[],
          }, id: 'c');
        });
        await tester.pumpWidget(StoryloomApp(store: db));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('folder-card-c')));
        await tester.pumpAndSettle();
        final editor = tester.widget<q.QuillEditor>(find.byType(q.QuillEditor));
        editor.focusNode.requestFocus();
        await tester.pump();
        final parent = tester.widget<RichEditor>(find.byType(RichEditor));
        final revision = db.get('c')!['revision'];
        var committed = initial;
        tester.testTextInput.log.clear();
        for (var repeat = 0; repeat < 5; repeat++) {
          for (final cp in sentence.runes) {
            final char = String.fromCharCode(cp);
            for (final step in compositionSteps(char)) {
              final text = committed + step;
              tester.testTextInput.updateEditingValue(
                TextEditingValue(
                  text: '$text\n',
                  selection: TextSelection.collapsed(offset: text.length),
                  composing: TextRange(
                    start: committed.length,
                    end: text.length,
                  ),
                ),
              );
              await tester.pump(const Duration(milliseconds: 40));
              expect(editor.controller.document.toPlainText(), '$text\n');
              expect(editor.focusNode.hasFocus, isTrue);
              expect(
                identical(
                  parent,
                  tester.widget<RichEditor>(find.byType(RichEditor)),
                ),
                isTrue,
              );
              expect(
                db.get('c')!['revision'],
                revision,
                reason: 'No save or history revision during continuous input',
              );
            }
            committed += char;
          }
          expect(committed, initial + List.filled(repeat + 1, sentence).join());
          debugPrint('Verified repetition ${repeat + 1}, autosave=$autosave');
        }
        expect(
          tester.testTextInput.log.where(
            (c) =>
                c.method == 'TextInput.setClient' ||
                c.method == 'TextInput.clearClient' ||
                c.method == 'TextInput.setEditingState',
          ),
          isEmpty,
        );
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: '$committed\n',
            selection: TextSelection.collapsed(offset: committed.length),
          ),
        );
        // Last edit was 40ms ago. No write until the 2-second idle boundary.
        await tester.pump(const Duration(milliseconds: 1959));
        expect(db.get('c')!['revision'], revision);
        await tester.pump(const Duration(milliseconds: 1));
        if (!autosave) {
          expect(db.get('c')!['revision'], revision);
          await tester.tap(find.text('변경 저장'));
        }
        debugPrint('Waiting for idle save, autosave=$autosave');
        await settleIo(tester, () => db.get('c')!['body'] == '$committed\n');
        debugPrint('Saved, autosave=$autosave');
        var flushed = false;
        db.flush().then((_) => flushed = true);
        await settleIo(tester, () => flushed);
        await tester.pumpWidget(const SizedBox());
        debugDefaultTargetPlatformOverride = null;
        await tester.runAsync(() async {
          db.dispose();
          final reopened = WorkspaceStore(root);
          await reopened.load();
          expect(reopened.get('c')!['body'], '$committed\n');
          reopened.dispose();
          await root.delete(recursive: true);
        });
      },
    );
  }
}
