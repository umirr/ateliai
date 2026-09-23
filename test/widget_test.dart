import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storyloom/main.dart';
import 'package:storyloom/store.dart';
import 'package:storyloom/workspace.dart';
import 'package:flutter/gestures.dart';
import 'package:storyloom/rich_editor.dart';

Future<void> settleIo(WidgetTester tester, bool Function() ready) async {
  await tester.pump(const Duration(milliseconds: 2200));
  for (var i = 0; i < 100 && !ready(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  expect(ready(), isTrue);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

Future<void> capture(
  WidgetTester tester,
  GlobalKey boundary,
  String name,
) async {
  if (!const bool.fromEnvironment('CAPTURE')) return;
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
  final render =
      boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await render.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('docs/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  testWidgets(
    'desktop editor, color menu, autosave, image cover and responsive layout',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 960);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('storyloom-ui-'),
      ))!;
      late WorkspaceStore db;
      await tester.runAsync(() async {
        db = WorkspaceStore(root);
        await db.load();
        await db.save('directory', {
          'title': '조연',
          'directory': '',
        }, id: 'folder');
        for (final id in ['유나', '노아']) {
          await db.save('character', {
            'title': id,
            'body': '달빛이 사라진 도시에서 기억을 수집하는 기록자.\n',
            'directory': '',
          }, id: id);
        }
        await File(
          'android/app/src/main/res/mipmap-hdpi/ic_launcher.png',
        ).copy(db.media('test.png').path);
        await db.save('asset', {
          'title': '대표 이미지',
          'file': 'test.png',
          'character': '유나',
          'folder': '',
        }, id: 'image');
        for (final name in ['Pretendard', 'Roboto']) {
          await (FontLoader(name)..addFont(
                Future.value(
                  ByteData.sublistView(
                    await File(
                      'assets/fonts/PretendardVariable.ttf',
                    ).readAsBytes(),
                  ),
                ),
              ))
              .load();
        }
        final icons = File(
          '${Platform.environment['FLUTTER_ROOT'] ?? '../../work/flutter'}/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
        );
        if (await icons.exists()) {
          await (FontLoader('MaterialIcons')..addFont(
                Future.value(ByteData.sublistView(await icons.readAsBytes())),
              ))
              .load();
        }
      });
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: StoryloomApp(store: db),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('empty-detail')), findsOneWidget);
      expect(
        tester.getCenter(find.byKey(const ValueKey('center-divider'))).dx,
        720,
      );
      await capture(tester, boundary, 'v8-desktop');
      final card = find.byKey(const ValueKey('folder-card-유나'));
      await tester.tap(card);
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byType(RichEditor), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('created-date')), findsOneWidget);
      await tester.tap(card, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('분류 색상'));
      await tester.pumpAndSettle();
      await capture(tester, boundary, 'v8-colors');
      await tester.tap(find.byKey(const ValueKey('classification-color-2')));
      await settleIo(tester, () => db.get('유나')!['color'] != null);
      final editor = tester.widget<RichEditor>(find.byType(RichEditor));
      editor.controller.replaceText(
        0,
        editor.controller.document.length - 1,
        '## ',
        const TextSelection.collapsed(offset: 3),
      );
      await tester.pump();
      await tester.pump();
      expect(
        editor.controller.document.toDelta().toJson().last['attributes'],
        isNull,
      );
      editor.controller.replaceText(
        0,
        0,
        '새로운 설정',
        const TextSelection.collapsed(offset: 6),
      );
      await tester.pump();
      expect(editor.controller.document.toPlainText(), contains('## '));
      await settleIo(
        tester,
        () => db.get('유나')!['body'].toString().contains('새로운 설정'),
      );
      expect(db.get('유나')!['document'], isNotNull);
      await capture(tester, boundary, 'v8-editor');
      await tester.tap(card);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(card);
      await tester.pumpAndSettle();
      final image = find.byKey(const ValueKey('image-image'));
      expect(image, findsOneWidget);
      await tester.tap(image);
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        tester
            .widget<DropSurface>(find.byKey(const ValueKey('gallery-drop')))
            .enabled,
        isFalse,
      );
      await tester.tap(image, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('대표 이미지로 지정'));
      await settleIo(tester, () => db.get('유나')!['cover'] == 'image');
      await capture(tester, boundary, 'v8-gallery');
      await tester.tap(image);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(image);
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
      await tester.tap(find.byTooltip('닫기'));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byTooltip('AI 대화')).height, 56);
      expect(find.text('AI 대화'), findsNothing);
      await tester.tap(find.byTooltip('AI 대화'));
      await tester.pumpAndSettle();
      final sendButton = tester
          .widgetList<IconButton>(find.byType(IconButton))
          .firstWhere((b) => b.tooltip == '메시지 전송');
      final bg = sendButton.style!.backgroundColor!.resolve({})!;
      final fg = sendButton.style!.foregroundColor!.resolve({})!;
      final light = bg.computeLuminance() > fg.computeLuminance() ? bg : fg;
      final dark = bg.computeLuminance() > fg.computeLuminance() ? fg : bg;
      expect(
        (light.computeLuminance() + .05) / (dark.computeLuminance() + .05),
        greaterThanOrEqualTo(4.5),
      );
      await capture(tester, boundary, 'v8-ai');
      for (final size in [
        const Size(1000, 680),
        const Size(390, 844),
        const Size(1440, 960),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        for (final mode in ['character_prompt', 'chat']) {
          await tester.tap(find.byKey(ValueKey('chat-mode-$mode')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        expect(tester.takeException(), isNull);
      }
      await tester.tap(
        find.byKey(const ValueKey('chat-mode-character_prompt')),
      );
      await tester.pumpAndSettle();
      await capture(tester, boundary, 'v8-character-prompt');
      await tester.tap(find.byTooltip('대화 닫기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('설정').first);
      await tester.pump();
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      await capture(tester, boundary, 'v8-settings');
      for (var theme = 0; theme < 11; theme++) {
        await tester.runAsync(() => db.setPreferences({'theme': theme}));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await capture(tester, boundary, 'v8-light');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.runAsync(() async {
        db.dispose();
        await root.delete(recursive: true);
      });
    },
  );
  testWidgets(
    'cut paste updates folder counts and modules contain only their own records',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 960);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('storyloom-modules-'),
      ))!;
      late WorkspaceStore db;
      await tester.runAsync(() async {
        db = WorkspaceStore(root);
        await db.load();
        await db.save('directory', {'title': '주연', 'directory': ''}, id: 'f');
        await db.save('character', {'title': '유나', 'directory': ''}, id: 'c');
        await db.save('directory', {
          'title': '노트 전용',
          'scope': 'memo',
          'directory': '',
        }, id: 'nf');
        await db.save('note', {
          'title': '안쪽 노트',
          'section': 'memo',
          'directory': 'nf',
        }, id: 'inside');
        await db.save('note', {
          'title': '1장',
          'section': 'story',
          'directory': 'f',
        }, id: 's');
        await db.save('note', {
          'title': '아이디어',
          'section': 'memo',
          'directory': 'f',
        }, id: 'n');
      });
      await tester.pumpWidget(StoryloomApp(store: db));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('folder-card-c')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('잘라내기'));
      await tester.pumpAndSettle();
      expect(db.get('c')!['directory'], '');
      await tester.tap(
        find.byKey(const ValueKey('folder-card-f')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('캐릭터 붙여넣기'));
      await settleIo(tester, () => db.get('c')!['directory'] == 'f');
      expect(find.text('1 캐릭터'), findsOneWidget);
      expect(find.byKey(const ValueKey('folder-card-c')), findsNothing);
      await tester.tap(find.text('스토리').first);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('folder-card-s')), findsOneWidget);
      expect(find.byKey(const ValueKey('folder-card-f')), findsNothing);
      expect(find.byKey(const ValueKey('folder-card-n')), findsNothing);
      await tester.tapAt(const Offset(80, 600), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(find.text('새 폴더'), findsNothing);
      expect(find.text('새 캐릭터'), findsNothing);
      await tester.tapAt(const Offset(1200, 800));
      await tester.pumpAndSettle();
      await tester.tap(find.text('노트').first);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('folder-card-n')), findsOneWidget);
      expect(find.byKey(const ValueKey('folder-card-s')), findsNothing);
      expect(find.byKey(const ValueKey('folder-card-f')), findsNothing);
      final noteFolder = find.byKey(const ValueKey('folder-card-nf'));
      expect(noteFolder, findsOneWidget);
      expect(find.text('1 노트'), findsOneWidget);
      await tester.tap(noteFolder);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(noteFolder);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('parent-folder')), findsOneWidget);
      expect(find.byKey(const ValueKey('folder-card-inside')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('parent-folder')));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(80, 600), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('새 노트'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '엔터 생성');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settleIo(
        tester,
        () => db.all('note').any((r) => r['title'] == '엔터 생성'),
      );
      expect(
        db.all('note').firstWhere((r) => r['title'] == '엔터 생성')['section'],
        'memo',
      );
      await tester.tap(find.text('캐릭터').first);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('folder-card-f')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '삭제'));
      await settleIo(
        tester,
        () =>
            db.get('f')!['deleted'] == true && db.get('c')!['deleted'] == true,
      );
      expect(db.get('s')!['deleted'], isNot(true));
      expect(db.get('n')!['deleted'], isNot(true));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.runAsync(() async {
        db.dispose();
        await root.delete(recursive: true);
      });
    },
  );
}
