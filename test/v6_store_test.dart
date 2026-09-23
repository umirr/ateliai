import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:storyloom/store.dart';
import 'package:storyloom/chat.dart';
import 'package:storyloom/notion_import.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:storyloom/drive_sync.dart';

void main() {
  late Directory root;
  late WorkspaceStore db;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('storyloom-v6-');
    db = WorkspaceStore(root);
    await db.load();
  });
  tearDown(() async {
    db.dispose();
    await root.delete(recursive: true);
  });
  test('migration preserves work hierarchy and is idempotent', () async {
    await db.save('project', {'title': '작품'}, id: 'p');
    await db.save('character', {
      'title': '유나',
      'body': '원문',
      'project': 'p',
      'directory': '',
    }, id: 'c');
    await db.migrateFolders();
    await db.migrateFolders();
    expect(db.all('directory').length, 1);
    expect(db.get('c')!['directory'], 'work-p');
    expect(db.get('c')!['body'], '원문');
    expect(db.get('c')!['project'], 'workspace');
  });
  test(
    'snapshots skip unchanged text, retain edits, expire and restore',
    () async {
      final t = DateTime.utc(2026, 9, 16);
      await db.save('note', {
        'title': '초안',
        'body': '첫 내용',
        'section': 'memo',
      }, id: 'n');
      await db.checkpoint(now: t);
      expect((await db.snapshots()).length, 1);
      await db.checkpoint(now: t.add(const Duration(minutes: 31)));
      expect((await db.snapshots()).length, 1);
      await db.save('note', {'body': '두 번째'}, id: 'n');
      await db.checkpoint(now: t.add(const Duration(minutes: 32)));
      final versions = await db.snapshots();
      expect(versions.length, 2);
      await db.restoreSnapshot(versions.last);
      expect(db.get('n')!['body'], '첫 내용');
      await db.setPreferences({'retentionDays': 1});
      await db.checkpoint(now: t.add(const Duration(days: 40)));
      expect(
        (await db.snapshots()).where(
          (s) => DateTime.parse(
            s['savedAt'] as String,
          ).isBefore(t.add(const Duration(days: 39))),
        ),
        isEmpty,
      );
      expect(db.get('n')!['body'], '첫 내용');
    },
  );
  test(
    'concurrent revisions remain available until explicit resolution',
    () async {
      final first = await db.save('character', {
        'title': '유나',
        'body': '기본',
      }, id: 'c');
      final branch = Map<String, dynamic>.from(first)
        ..addAll({
          'revision': 'remote',
          'parentRevision': first['revision'],
          'generation': 2,
          'body': '모바일',
        });
      await db.save('character', {'body': 'PC'}, id: 'c');
      await File(
        '${root.path}/revisions/remote.json',
      ).writeAsString(jsonEncode(branch));
      await db.load();
      expect(db.conflicts['c']!.length, 2);
      await db.resolveConflict('c', branch);
      await db.load();
      expect(db.conflicts, isEmpty);
      expect(db.get('c')!['body'], '모바일');
    },
  );
  test(
    'Notion pagination and nested blocks are read before classification',
    () async {
      final client = NotionClient(
        'fake',
        client: MockClient((request) async {
          if (request.url.path.endsWith('/search')) {
            return http.Response(
              jsonEncode({
                'results': [
                  {
                    'id': 'p',
                    'properties': {
                      'title': {
                        'type': 'title',
                        'title': [
                          {'plain_text': '인물'},
                        ],
                      },
                    },
                  },
                ],
                'has_more': false,
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          if (request.url.path.contains('/p/')) {
            return http.Response(
              jsonEncode({
                'results': [
                  {
                    'id': 'b',
                    'type': 'heading_1',
                    'heading_1': {
                      'rich_text': [
                        {'plain_text': '캐릭터'},
                      ],
                    },
                    'has_children': true,
                  },
                ],
                'has_more': false,
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          return http.Response(
            jsonEncode({
              'results': [
                {
                  'type': 'paragraph',
                  'paragraph': {
                    'rich_text': [
                      {'plain_text': '성격과 외형'},
                    ],
                  },
                },
              ],
              'has_more': false,
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      expect((await client.pages()).single['title'], '인물');
      final content = await client.content('p');
      expect(content, contains('성격과 외형'));
      expect(detectKind('인물', content), 'character');
      client.close();
    },
  );
  test(
    'editing text while a remote version arrives keeps both branches',
    () async {
      final base = await db.save('note', {
        'title': '장면',
        'body': '원문',
      }, id: 'n');
      await db.save('note', {'body': '원격'}, id: 'n');
      await db.save('note', {'body': '작성 중'}, id: 'n', textBase: base);
      await db.load();
      expect(db.conflicts['n']!.map((r) => r['body']).toSet(), {'원격', '작성 중'});
    },
  );
  test(
    'Drive sync round trip excludes preferences and repeats without duplicates',
    () async {
      final remote = <String, List<int>>{};
      var sequence = 0;
      final names = <String, String>{};
      MockClient server() => MockClient((req) async {
        if (req.method == 'GET' && req.url.queryParameters['alt'] == 'media') {
          return http.Response.bytes(remote[req.url.pathSegments.last]!, 200);
        }
        if (req.method == 'GET') {
          return http.Response(
            jsonEncode({
              'files': names.entries
                  .map((e) => {'id': e.key, 'name': e.value})
                  .toList(),
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        final text = utf8.decode(req.bodyBytes);
        final boundary = req.headers['content-type']!.split('boundary=').last;
        final parts = text.split('--$boundary');
        final metadata =
            jsonDecode(parts[1].split('\r\n\r\n')[1].trim()) as Map;
        final body = parts[2].split('\r\n\r\n')[1];
        final id = 'f${sequence++}';
        names[id] = metadata['name'] as String;
        remote[id] = utf8.encode(body.substring(0, body.length - 2));
        return http.Response('{}', 200);
      });
      await db.save('note', {'title': '동기화', 'body': '보존할 글'}, id: 'n');
      await db.setPreferences({
        'theme': 3,
        'googleDesktopClient': 'private-config',
      });
      final sync = DriveSync(
        db,
        clientFactory: server,
        accessToken: () async => 'fake',
      );
      await sync.sync();
      expect(names.length, 1);
      await sync.sync();
      expect(names.length, 1);
      final otherRoot = await Directory.systemTemp.createTemp(
        'storyloom-sync-',
      );
      final other = WorkspaceStore(otherRoot);
      await other.load();
      try {
        await DriveSync(
          other,
          clientFactory: server,
          accessToken: () async => 'fake',
        ).sync();
        expect(other.get('n')!['body'], '보존할 글');
        expect(other.preferences, isEmpty);
      } finally {
        other.dispose();
        await otherRoot.delete(recursive: true);
      }
    },
  );
  test(
    'AI image payload validates input and creates inline image data',
    () async {
      final file = File('${root.path}/fake.png');
      await file.writeAsString('not an image');
      await expectLater(imageMessage('', [file]), throwsFormatException);
      await File(
        'android/app/src/main/res/mipmap-hdpi/ic_launcher.png',
      ).copy(file.path);
      final message = await imageMessage('설명', [file]);
      expect(message[1]['type'], 'image_url');
      expect(
        message[1]['image_url']['url'],
        startsWith('data:image/png;base64,'),
      );
    },
  );
}
