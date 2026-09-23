import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart' as q;
import 'package:flutter_quill/src/editor/widgets/proxy.dart';
import 'package:storyloom/emoji_picker.dart';
import 'package:storyloom/rich_editor.dart';

void main() {
  testWidgets(
    'offline emoji catalog searches Korean and inserts selection with undo',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final catalog =
          jsonDecode(
                (await tester.runAsync(
                  () => rootBundle.loadString('assets/emoji/catalog.json'),
                ))!,
              )
              as List;
      expect(catalog.length, 3944);
      expect(catalog.map((e) => e['group']).toSet(), emojiGroups.keys.toSet());
      for (final pair in [
        ('Pretendard', 'PretendardVariable.ttf'),
        ('NotoEmoji', 'NotoColorEmoji.ttf'),
      ]) {
        await tester.runAsync(
          () => (FontLoader(
            pair.$1,
          )..addFont(rootBundle.load('assets/fonts/${pair.$2}'))).load(),
        );
      }
      await tester.runAsync(() async {
        final flutterRoot =
            Platform.environment['FLUTTER_ROOT'] ?? '../../work/flutter';
        final bytes = await File(
          '$flutterRoot/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
        ).readAsBytes();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      });
      final c = documentController({'body': "기본적인 구조 : '선택지를 제한한다'"});
      final boundary = GlobalKey();
      final overlayBoundary = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) =>
              RepaintBoundary(key: overlayBoundary, child: child!),
          theme: ThemeData(
            brightness: Brightness.dark,
            fontFamily: 'Pretendard',
          ),
          localizationsDelegates: const [q.FlutterQuillLocalizations.delegate],
          home: Scaffold(
            body: RepaintBoundary(
              key: boundary,
              child: RichEditor(
                controller: c,
                onChanged: () {},
                expanded: true,
                lineHeight: 2.5,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      c.updateSelection(
        const TextSelection(baseOffset: 0, extentOffset: 4),
        q.ChangeSource.local,
      );
      await tester.pump();
      final proxy = tester.allRenderObjects
          .whereType<RenderParagraphProxy>()
          .first;
      final tight = proxy
          .getBoxesForSelection(
            const TextSelection(baseOffset: 0, extentOffset: 4),
          )
          .first;
      final full = proxy.child!
          .getBoxesForSelection(
            const TextSelection(baseOffset: 0, extentOffset: 4),
            boxHeightStyle: ui.BoxHeightStyle.max,
          )
          .first;
      expect(tight.bottom - tight.top, lessThan(full.bottom - full.top));
      await tester.tap(find.byTooltip('이모티콘'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('emoji-search')), '고양이');
      await tester.pumpAndSettle();
      expect(find.text('🐱'), findsOneWidget);
      if (const bool.fromEnvironment('CAPTURE')) {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        // Capture the full dialog including the offline emoji font.
        final root =
            overlayBoundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await root.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            'docs/v8.1-emoji.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        expect(render.hasSize, isTrue);
      }
      await tester.tap(find.text('🐱'));
      await tester.pumpAndSettle();
      expect(c.document.toPlainText(), startsWith('🐱 구조'));
      c.undo();
      expect(c.document.toPlainText(), startsWith('기본적인 구조'));
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      expect(tester.takeException(), isNull);
    },
  );
}
