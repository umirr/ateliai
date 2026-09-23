import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storyloom/ai.dart';
import 'package:storyloom/chat.dart';
import 'package:storyloom/store.dart';

void main() {
  test(
    'SSE preserves split Unicode events and rejects provider errors',
    () async {
      const raw =
          'data: {"choices":[{"delta":{"content":"안녕"}}]}\n\ndata: {"choices":[{"delta":{"content":"\\n세계"}}]}\n\ndata: [DONE]\n\n';
      expect(
        await decodeAiEvents(Stream.fromIterable(raw.split(''))).join(),
        '안녕\n세계',
      );
      await expectLater(
        decodeAiEvents(Stream.value('data: {"error":{}}\n\n')).toList(),
        throwsFormatException,
      );
    },
  );
  test(
    'immediate writes survive restart and local history obeys limit and restores',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'storyloom-v8-history-',
      );
      final db = WorkspaceStore(root);
      await db.load();
      try {
        await db.setPreferences({'historyCount': 10});
        await db.save('note', {
          'title': '노트',
          'body': '0',
          'section': 'memo',
        }, id: 'n');
        for (var i = 1; i <= 25; i++) {
          await db.save('note', {'body': '$i'}, id: 'n', silent: true);
        }
        await db.flush();
        expect(db.get('n')!['body'], '25');
        final rows = await db.recentChanges();
        expect(rows.length, 10);
        expect(rows.first['body'], '24');
        final restart = WorkspaceStore(root);
        await restart.load();
        expect(restart.get('n')!['body'], '25');
        expect((await restart.recentChanges()).length, 10);
        await restart.restoreChange(rows.last);
        expect(restart.get('n')!['body'], '15');
        restart.dispose();
      } finally {
        db.dispose();
        await root.delete(recursive: true);
      }
    },
  );
  test(
    'startup cache is invalidated by a new revision and corrupt cache falls back',
    () async {
      final root = await Directory.systemTemp.createTemp('storyloom-v8-cache-');
      final db = WorkspaceStore(root);
      await db.load();
      try {
        await db.save('character', {'title': '유나', 'body': 'cached'}, id: 'c');
        await db.load();
        final fast = WorkspaceStore(root);
        await fast.load(fast: true);
        expect(fast.get('c')!['body'], 'cached');
        fast.dispose();
        final incoming = {
          ...db.get('c')!,
          'revision': 'incoming',
          'parentRevision': db.get('c')!['revision'],
          'generation': 10,
          'body': 'remote',
          'updated': DateTime.now().toUtc().toIso8601String(),
        };
        await File(
          '${root.path}/revisions/incoming.json',
        ).writeAsString(jsonEncode(incoming));
        final remote = WorkspaceStore(root);
        await remote.load(fast: true);
        expect(remote.get('c')!['body'], 'remote');
        remote.dispose();
        await File('${root.path}/index.json').writeAsString('{broken');
        final repaired = WorkspaceStore(root);
        await repaired.load(fast: true);
        expect(repaired.get('c')!['body'], 'remote');
        repaired.dispose();
      } finally {
        db.dispose();
        await root.delete(recursive: true);
      }
    },
  );
  test(
    'measure cold revision scan versus warm index with 1000 revisions',
    () async {
      final root = await Directory.systemTemp.createTemp('storyloom-v8-perf-');
      final db = WorkspaceStore(root);
      await db.load();
      try {
        for (var i = 0; i < 1000; i++) {
          await File('${root.path}/revisions/bench-$i.json').writeAsString(
            jsonEncode({
              'schema': 1,
              'type': 'character',
              'id': 'char-${i % 100}',
              'revision': 'bench-$i',
              'generation': i,
              'title': '캐릭터 $i',
              'body': '설정 ' * 50,
              'created': '2026-01-01T00:00:00Z',
              'updated': DateTime.utc(
                2026,
                1,
                1,
              ).add(Duration(seconds: i)).toIso8601String(),
            }),
          );
        }
        final cold = Stopwatch()..start();
        await db.load();
        cold.stop();
        final fast = WorkspaceStore(root);
        final warm = Stopwatch()..start();
        await fast.load(fast: true);
        warm.stop();
        expect(fast.all('character').length, 100);
        fast.dispose();
        final metric =
            '1000 revisions / 100 characters: cold ${cold.elapsedMilliseconds} ms, cached ${warm.elapsedMilliseconds} ms';
        // ignore: avoid_print
        print(metric);
        await File('docs/v8-startup-benchmark.txt').writeAsString(metric);
      } finally {
        db.dispose();
        await root.delete(recursive: true);
      }
    },
  );
  testWidgets(
    'chat immediately displays input, streams below, includes chosen cover and copies full reply',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('storyloom-v8-chat-'),
      ))!;
      final db = WorkspaceStore(root);
      await tester.runAsync(() async {
        await db.load();
        await db.save('character', {
          'title': '유나',
          'body': '설정',
          'cover': 'cover',
        }, id: 'c');
        await File(
          'android/app/src/main/res/mipmap-hdpi/ic_launcher.png',
        ).copy(db.media('cover.png').path);
        await db.save('asset', {
          'title': '대표',
          'character': 'c',
          'file': 'cover.png',
        }, id: 'cover');
      });
      final stream = StreamController<String>();
      List<Map<String, dynamic>>? payload;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatPage(
              store: db,
              project: 'workspace',
              requestedReference: 'c',
              referenceRequest: 1,
              replyProvider: (messages) {
                payload = messages;
                return stream.stream;
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('chat-input')),
        '아이디어 질문',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      for (var i = 0; i < 100 && payload == null; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(payload, isNotNull);
      expect(find.text('아이디어 질문'), findsOneWidget);
      expect(find.text('답변을 기다리는 중…'), findsOneWidget);
      expect(payload!.first['content'], contains(defaultAiSystemPrompt));
      expect(payload!.first['content'], contains('유나\n설정'));
      expect((payload!.last['content'] as List).last['type'], 'image_url');
      stream.add('첫 답변');
      await tester.pump();
      expect(find.text('첫 답변'), findsOneWidget);
      final tail = List.generate(150, (i) => '\n내용 $i').join();
      stream.add(tail);
      await tester.pump();
      unawaited(stream.close());
      for (var i = 0; i < 100 && db.all('message').length < 2; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(db.all('message').length, 2);
      expect(db.all('message').last['body'], '첫 답변$tail');
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      await tester.ensureVisible(find.byTooltip('전체 텍스트 복사').last);
      await tester.tap(find.byTooltip('전체 텍스트 복사').last);
      await tester.pump();
      expect(copied, '첫 답변$tail');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await db.flush();
        db.dispose();
        await root.delete(recursive: true);
      });
    },
  );
}
