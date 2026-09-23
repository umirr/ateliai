import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storyloom/chat.dart';
import 'package:storyloom/store.dart';
import 'widget_test.dart' show settleIo;

void main() {
  testWidgets(
    'deselected documents and previous derived answers stay out of payload; reset persists',
    (tester) async {
      tester.view.physicalSize = const Size(640, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('storyloom-privacy-'),
      ))!;
      final db = WorkspaceStore(root);
      await tester.runAsync(() async {
        await db.load();
        await db.save('character', {
          'title': '공개 설정',
          'body': 'SELECTED_CONTENT',
        }, id: 'a');
        await db.save('note', {
          'title': '미선택 설정',
          'body': 'PRIVATE_CONTENT',
          'section': 'memo',
        }, id: 'b');
        await db.save('message', {
          'project': 'workspace',
          'role': 'assistant',
          'body': 'PRIVATE_CONTENT_OLD_ANSWER',
          'referenceScope': 'b',
          'chatMode': 'chat',
        });
      });
      final payloads = <List<Map<String, dynamic>>>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatPage(
              store: db,
              project: 'workspace',
              requestedReference: 'a',
              replyProvider: (p) {
                payloads.add(p);
                return Stream.value('SELECTED_CONTENT_REPLY');
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final labels = tester
          .widgetList<FilterChip>(find.byType(FilterChip))
          .map((c) => (c.label as Text).data)
          .toList();
      expect(labels, ['미선택 설정', '공개 설정']);
      Future<void> send(String text) async {
        await tester.enterText(find.byKey(const ValueKey('chat-input')), text);
        await tester.tap(find.byTooltip('메시지 전송'));
        for (var i = 0; i < 100; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(milliseconds: 50));
          if (db.all('message').any((r) => r['body'] == text) &&
              tester
                      .widgetList<IconButton>(find.byType(IconButton))
                      .firstWhere((b) => b.tooltip == '메시지 전송')
                      .onPressed !=
                  null) {
            break;
          }
        }
        expect(db.all('message').any((r) => r['body'] == text), isTrue);
        expect(
          tester
              .widgetList<IconButton>(find.byType(IconButton))
              .firstWhere((b) => b.tooltip == '메시지 전송')
              .onPressed,
          isNotNull,
        );
        await tester.pumpAndSettle();
      }

      await send('첫 요청');
      expect(payloads.last.toString(), contains('SELECTED_CONTENT'));
      expect(payloads.last.toString(), isNot(contains('PRIVATE_CONTENT')));
      await tester.tap(find.widgetWithText(FilterChip, '공개 설정'));
      await tester.pump();
      await send('두 번째 요청');
      expect(payloads.last.toString(), isNot(contains('SELECTED_CONTENT')));
      expect(payloads.last.toString(), isNot(contains('PRIVATE_CONTENT')));
      await tester.tap(find.byTooltip('현재 모드 대화 초기화'));
      await settleIo(tester, () => db.all('message').isEmpty);
      expect(find.text('SELECTED_CONTENT_REPLY'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        db.dispose();
        final reopened = WorkspaceStore(root);
        await reopened.load();
        expect(reopened.all('message'), isEmpty);
        reopened.dispose();
        await root.delete(recursive: true);
      });
    },
  );
}
