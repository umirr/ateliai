import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storyloom/ai_modes.dart';
import 'package:storyloom/chat.dart';
import 'package:storyloom/store.dart';

const characterAnswer = '''## 캐릭터 요약
차분한 성인 사서.
## 기본 프롬프트
```text
library, soft lighting
```
## 캐릭터 프롬프트
```text
1girl, adult woman, brown hair, green eyes, glasses, cardigan
```
## 제외 프롬프트
```text
glasses, hat
```
## 고정 조건과 생성한 요소
고정: 성인 사서. 생성: 머리와 의상.
''';

void main() {
  test(
    'Full model profiles change actual prompting rules and quality presets',
    () {
      final v45 = novelPromptProfile('V4.5 Full');
      final v5 = novelPromptProfile('V5 Full');
      expect(v45, contains('512 T5'));
      expect(
        v45,
        contains('V5 전용 complexity 태그, depthness, 알파 투명도 기능을 쓰지 않는다'),
      );
      expect(v5, contains('1471'));
      expect(v5, contains('high complexity'));
      expect(v5, contains('의상 겹침'));
      expect(v5, isNot(contains('512 T5')));
      expect(
        novelPromptProfile('V5 Full', qualityPreset: 'light'),
        contains('amazing quality'),
      );
      expect(
        novelPromptProfile('V5 Full', qualityTags: false),
        contains('자동 프리셋을 임의로 다시 추가하지 않는다'),
      );
      expect(v45, isNot(contains('Curated')));
    },
  );
  test(
    'mode history preserves legacy chat and never mixes generated conversations',
    () {
      final rows = <Record>[
        {'body': 'legacy'},
        {'chatMode': 'chat', 'body': 'chat'},
        {'chatMode': 'character_prompt', 'body': 'character'},
        {'chatMode': 'instructions', 'body': 'instruction'},
        {'chatMode': 'unknown', 'body': 'unknown'},
      ];
      expect(modeMessages(rows, ChatMode.conversation).map((r) => r['body']), [
        'legacy',
        'chat',
      ]);
      expect(
        modeMessages(rows, ChatMode.character).single['body'],
        'character',
      );
      expect(ChatMode.values, [ChatMode.conversation, ChatMode.character]);
    },
  );
  test('Full model prompt contract preserves fixed character conditions', () {
    final character = systemPromptFor(
      ChatMode.character,
      references: '성인 사서',
      novelModel: 'V5',
      qualityTags: true,
      variation: randomDesignBrief(Random(5)),
    );
    expect(character, contains('선택지가 없는 단일 완성본'));
    expect(character, contains('대상 모델: V5'));
    expect(character, contains('<참고자료>\n성인 사서'));
    expect(
      List.generate(20, (i) => randomDesignBrief(Random(i))).toSet().length,
      greaterThan(10),
    );
  });
  test(
    'copy blocks exclude explanation and incomplete or randomizer answers are flagged',
    () {
      expect(
        generatedBlocks(characterAnswer)['캐릭터 프롬프트'],
        '1girl, adult woman, brown hair, green eyes, glasses, cardigan',
      );
      expect(generationWarnings(ChatMode.character, characterAnswer), isEmpty);
      expect(
        generationWarnings(ChatMode.character, '||red hair|blue hair||'),
        hasLength(2),
      );
    },
  );
  testWidgets(
    'two modes isolate drafts references payloads and saved prompt notes',
    (tester) async {
      tester.view.physicalSize = const Size(640, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('storyloom-modes-'),
      ))!;
      final db = WorkspaceStore(root);
      await tester.runAsync(() async {
        await db.load();
        await db.save('character', {
          'title': '사서 설정',
          'body': '성인 사서',
        }, id: 'ref');
        await db.save('message', {
          'project': 'workspace',
          'role': 'user',
          'body': '기존 일반 대화',
        });
      });
      final payloads = <List<Map<String, dynamic>>>[];
      final response = StreamController<String>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatPage(
              store: db,
              project: 'workspace',
              requestedReference: 'ref',
              replyProvider: (p) {
                payloads.add(p);
                return payloads.length == 1
                    ? response.stream
                    : Stream.value('일반 대화 응답');
              },
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('기존 일반 대화'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('chat-input')),
        '대화 임시 입력',
      );
      await tester.tap(
        find.byKey(const ValueKey('chat-mode-character_prompt')),
      );
      await tester.pump();
      expect(find.text('기존 일반 대화'), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('chat-input')))
            .controller!
            .text,
        isEmpty,
      );
      expect(
        tester.widget<FilterChip>(find.byType(FilterChip)).selected,
        isFalse,
      );
      await tester.enterText(
        find.byKey(const ValueKey('chat-input')),
        '성인 여성 판타지 사서',
      );
      await tester.tap(find.byKey(const ValueKey('chat-mode-chat')));
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('chat-input')))
            .controller!
            .text,
        '대화 임시 입력',
      );
      expect(
        tester.widget<FilterChip>(find.byType(FilterChip)).selected,
        isTrue,
      );
      await tester.tap(
        find.byKey(const ValueKey('chat-mode-character_prompt')),
      );
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('chat-input')))
            .controller!
            .text,
        '성인 여성 판타지 사서',
      );
      await tester.tap(find.byTooltip('메시지 전송'));
      await tester.pump();
      Future<void> until(bool Function() ready) async {
        for (var i = 0; i < 150 && !ready(); i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(ready(), isTrue);
        await tester.pump();
      }

      await until(() => payloads.length == 1);
      expect(payloads.first.length, 2);
      expect(payloads.first.first['content'], contains('NovelAI'));
      expect(payloads.first.first['content'], isNot(contains('기존 일반 대화')));
      expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('chat-mode-chat')))
            .onPressed,
        isNull,
      );
      response.add(characterAnswer);
      unawaited(response.close());
      await until(
        () => db.all('message').any((r) => r['body'] == characterAnswer),
      );
      expect(db.all('message').last['chatMode'], 'character_prompt');
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
      await tester.ensureVisible(find.text('캐릭터 프롬프트 복사'));
      await tester.tap(find.text('캐릭터 프롬프트 복사'));
      await tester.pump();
      expect(copied, generatedBlocks(characterAnswer)['캐릭터 프롬프트']);
      await tester.ensureVisible(find.text('프롬프트 노트로 저장'));
      await tester.tap(find.text('프롬프트 노트로 저장'));
      await tester.pump();
      await until(() => db.all('note').isNotEmpty);
      expect(db.all('note').single['kind'], '프롬프트');
      expect(db.all('note').single['promptPurpose'], 'character_prompt');
      expect(
        find.byKey(const ValueKey('chat-mode-instructions')),
        findsNothing,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.runAsync(() async {
        await db.flush();
        db.dispose();
        final reopened = WorkspaceStore(root);
        await reopened.load(fast: true);
        expect(
          modeMessages(reopened.all('message'), ChatMode.character).length,
          2,
        );
        reopened.dispose();
        await root.delete(recursive: true);
      });
    },
  );
}
