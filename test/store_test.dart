import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:storyloom/store.dart';
import 'package:storyloom/ai.dart';

void main() {
  test(
    'legacy unassigned images remain reachable after the character migration',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'storyloom-migration-',
      );
      final db = WorkspaceStore(root);
      await db.load();
      await db.save('project', {'title': '기존 작품'}, id: 'p');
      await db.save('character', {'title': '기존 인물', 'project': 'p'}, id: 'c');
      await db.save('asset', {
        'title': '기존 그림',
        'project': 'p',
        'character': null,
        'file': 'old.png',
        'tags': ['교복'],
      }, id: 'a');
      await db.save('asset', {
        'title': '연결된 그림',
        'project': 'p',
        'character': 'c',
        'file': 'other.png',
      }, id: 'b');
      await db.attachLegacyImages();
      await db.attachLegacyImages();
      await db.load();
      expect(db.get('a')!['character'], 'legacy-images-p');
      expect(db.get('a')!['tags'], ['교복']);
      expect(db.get('b')!['character'], 'c');
      expect(db.all('character'), hasLength(2));
      db.dispose();
      await root.delete(recursive: true);
    },
  );
  late Directory root;
  late WorkspaceStore db;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('storyloom-test-');
    db = WorkspaceStore(root);
    await db.load();
  });
  tearDown(() async {
    db.dispose();
    await root.delete(recursive: true);
  });
  test(
    'edits and deletion survive restart with original revisions retained',
    () async {
      final r = await db.save('character', {'title': '유나', 'project': 'a'});
      final edited = await db.save('character', {
        'body': '달빛 수집가',
      }, id: r['id'] as String);
      expect(edited['parentRevision'], r['revision']);
      final restored = WorkspaceStore(root);
      await restored.load();
      expect(restored.all('character', project: 'a').single['body'], '달빛 수집가');
      expect(restored.all('character', project: 'b'), isEmpty);
      await restored.remove(edited);
      await restored.load();
      expect(restored.all('character'), isEmpty);
      expect(await Directory('${root.path}/revisions').list().length, 3);
      restored.dispose();
    },
  );
  test('unfinished and corrupt writes do not hide valid records', () async {
    await db.save('note', {'title': '장면', 'project': 'a'});
    await File('${root.path}/revisions/unfinished.json.tmp').writeAsString('{');
    await File('${root.path}/revisions/corrupt.json').writeAsString('{');
    await db.load();
    expect(db.all('note'), hasLength(1));
    expect(db.warnings, hasLength(1));
  });
  test('300 image copies and tags survive restart, source untouched', () async {
    final source = File('${root.path}/source.png');
    await source.writeAsBytes([1, 2, 3]);
    for (var i = 0; i < 300; i++) {
      await db.importImage(source, 'image-$i.png', 'a', 'folder');
    }
    final first = db.all('asset').first;
    await db.save('asset', {
      'tags': ['교복', '웃음'],
      'character': 'yuna',
    }, id: first['id'] as String);
    await db.load();
    expect(db.all('asset'), hasLength(300));
    expect(await db.media(first['file'] as String).readAsBytes(), [1, 2, 3]);
    expect(await source.exists(), isTrue);
    expect(db.get(first['id'] as String)!['tags'], ['교복', '웃음']);
  });
  test('media cannot escape storage folder', () {
    expect(() => db.media('../secret'), throwsFormatException);
  });
  test('AI rejects unsafe or incomplete endpoint before transmitting key', () {
    for (final endpoint in [
      'http://example.com/chat',
      'https://name:pass@example.com/chat',
      'https://example.com/chat?key=x',
      '',
    ]) {
      expect(
        () => AiConnection(endpoint, 'model', 'secret').validate(),
        throwsFormatException,
      );
    }
    expect(
      const AiConnection(
        'https://example.com/v1/chat/completions',
        'model',
        'secret',
      ).validate().host,
      'example.com',
    );
  });
}
