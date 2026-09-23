import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storyloom/main.dart';
import 'package:storyloom/store.dart';
import 'package:storyloom/studio_widgets.dart';
import 'widget_test.dart' show settleIo;

void main() {
  testWidgets(
    'Ctrl toggle, Shift range and grouped drag in characters and notes',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 960);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('storyloom-multi-'),
      ))!;
      final db = WorkspaceStore(root);
      await tester.runAsync(() async {
        await db.load();
        for (final memo in [false, true]) {
          final prefix = memo ? 'n' : 'c';
          await db.save('directory', {
            'title': '${prefix}folder',
            'scope': memo ? 'memo' : 'character',
            'directory': '',
          }, id: '${prefix}folder');
          for (var i = 0; i < 3; i++) {
            await db.save(memo ? 'note' : 'character', {
              'title': '$prefix$i',
              'section': memo ? 'memo' : null,
              'directory': '',
            }, id: '$prefix$i');
          }
        }
      });
      await tester.pumpWidget(StoryloomApp(store: db));
      await tester.pumpAndSettle();
      for (final prefix in ['c', 'n']) {
        if (prefix == 'n') {
          await tester.tap(find.text('노트').first);
          await tester.pumpAndSettle();
        }
        final cards = tester
            .widgetList<FolderCard>(find.byType(FolderCard))
            .where((c) => c.record['type'] != 'directory')
            .map((c) => c.record['id'] as String)
            .toList();
        Finder card(String id) => find.byKey(ValueKey('folder-card-$id'));
        Set<String> selected() => tester
            .widgetList<FolderCard>(find.byType(FolderCard))
            .where((c) => c.selected)
            .map((c) => c.record['id'] as String)
            .toSet();
        await tester.tap(card(cards[0]));
        await tester.pumpAndSettle();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.tap(card(cards[2]));
        await tester.pumpAndSettle();
        expect(selected(), {cards[0], cards[2]});
        await tester.tap(card(cards[2]));
        await tester.pumpAndSettle();
        expect(selected(), {cards[0]});
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(card(cards[0]));
        await tester.pumpAndSettle();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.tap(card(cards[2]));
        await tester.pumpAndSettle();
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        expect(selected(), cards.toSet());
        await tester.dragFrom(
          tester.getCenter(card(cards[0])),
          tester.getCenter(card('${prefix}folder')) -
              tester.getCenter(card(cards[0])),
        );
        await settleIo(
          tester,
          () => cards.every(
            (id) => db.get(id)?['directory'] == '${prefix}folder',
          ),
        );
        expect(find.byType(FolderCard), findsOneWidget);
        await tester.tap(card('${prefix}folder'));
        await tester.pump(const Duration(milliseconds: 80));
        await tester.tap(card('${prefix}folder'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('parent-folder')), findsOneWidget);
        await tester.tap(card(cards[0]));
        await tester.pumpAndSettle();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.tap(card(cards[2]));
        await tester.pumpAndSettle();
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.dragFrom(
          tester.getCenter(card(cards[0])),
          tester.getCenter(find.byKey(const ValueKey('parent-folder'))) -
              tester.getCenter(card(cards[0])),
        );
        await settleIo(
          tester,
          () => cards.every((id) => db.get(id)?['directory'] == ''),
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        db.dispose();
        await root.delete(recursive: true);
      });
    },
  );
}
