import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

typedef Record = Map<String, dynamic>;

// Snapshot mutable JSON containers without encoding large text on the UI thread.
dynamic _copyJson(dynamic value) {
  if (value is Map) {
    return value.map((k, v) => MapEntry(k as String, _copyJson(v)));
  }
  if (value is List) return value.map(_copyJson).toList();
  return value;
}

bool _sameJson(dynamic a, dynamic b) {
  if (identical(a, b)) return true;
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_sameJson(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every((k) => b.containsKey(k) && _sameJson(a[k], b[k]));
  }
  return a == b;
}

Future<String> _encodeStoredJson(Record value) {
  final records = value['records'];
  final large =
      (value['body'] as String? ?? '').length > 32768 ||
      (records is List &&
          (records.length > 100 ||
              records.any(
                (r) => ((r as Map)['body'] as String? ?? '').length > 32768,
              )));
  return large ? compute(jsonEncode, value) : Future.value(jsonEncode(value));
}

/// Immutable revision files: interrupted writes never replace a valid revision.
/// Revision IDs and parent IDs allow a future sync adapter to detect conflicts.
class WorkspaceStore extends ChangeNotifier {
  WorkspaceStore(this.root);
  final Directory root;
  final ValueNotifier<Record> settings = ValueNotifier({});
  Timer? _indexTimer;
  bool _closed = false;
  final Map<String, List<Record>> _history = {};
  bool _historyLoaded = false;
  @override
  void dispose() {
    _closed = true;
    _indexTimer?.cancel();
    settings.dispose();
    super.dispose();
  }

  Future<void> flush() => _writes;
  Future<void> _writeIndex() async {
    final stamp = (await Directory(
      '${root.path}/revisions',
    ).stat()).modified.toUtc().toIso8601String();
    final data = {
      'version': 1,
      'stamp': stamp,
      'records': _records.values.toList(),
      'conflicts': conflicts,
    };
    final file = File('${root.path}/index.json');
    await File(
      '${file.path}.tmp',
    ).writeAsString(await _encodeStoredJson(data), flush: true);
    if (await file.exists()) await file.delete();
    await File('${file.path}.tmp').rename(file.path);
  }

  void _scheduleIndex() {
    if (_closed) return;
    _indexTimer?.cancel();
    _indexTimer = Timer(const Duration(milliseconds: 500), () {
      final task = _writes.then((_) => _writeIndex());
      _writes = task.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    });
  }

  Future<void> _loadHistory() async {
    if (_historyLoaded) return;
    final folder = Directory('${root.path}/history');
    await folder.create(recursive: true);
    await for (final f in folder.list()) {
      if (f is File && f.path.endsWith('.json')) {
        try {
          final r = Map<String, dynamic>.from(
            jsonDecode(await f.readAsString()) as Map,
          );
          _history.putIfAbsent(r['id'] as String, () => []).add(r);
        } catch (_) {}
      }
    }
    for (final rows in _history.values) {
      rows.sort(
        (a, b) => (b['updated'] as String).compareTo(a['updated'] as String),
      );
    }
    _historyLoaded = true;
  }

  Future<List<Record>> recentChanges() async {
    await flush();
    await _loadHistory();
    return _history.values.expand((r) => r).toList()..sort(
      (a, b) => (b['updated'] as String).compareTo(a['updated'] as String),
    );
  }

  Future<void> _remember(Record previous) async {
    await _loadHistory();
    final rows = _history.putIfAbsent(previous['id'] as String, () => []);
    if (!rows.any((r) => r['revision'] == previous['revision'])) {
      await File(
        '${root.path}/history/${previous['revision']}.json',
      ).writeAsString(await _encodeStoredJson(previous), flush: true);
      rows.insert(0, Map<String, dynamic>.from(previous));
    }
    await _trimHistory();
  }

  Future<void> _trimHistory() async {
    final count = preferences['historyCount'] as int? ?? 50;
    if (count == 0) return;
    for (final rows in _history.values) {
      while (rows.length > count) {
        final r = rows.removeLast();
        final f = File('${root.path}/history/${r['revision']}.json');
        if (await f.exists()) await f.delete();
      }
    }
  }

  Future<void> restoreChange(Record record) => save(record['type'] as String, {
    ...record,
    'deleted': false,
  }, id: record['id'] as String);

  final Map<String, Record> _records = {};
  Future<void> _writes = Future<void>.value();
  final List<String> warnings = [];
  final Map<String, List<Record>> conflicts = {};
  Record get preferences => get('preferences') ?? <String, dynamic>{};
  Future<void> setPreferences(Record fields) async {
    await save('preferences', fields, id: 'preferences');
    if (fields.containsKey('historyCount')) {
      final task = _writes.then((_) async {
        await _loadHistory();
        await _trimHistory();
      });
      _writes = task.then<void>((_) {}, onError: (Object _, StackTrace _) {});
      await task;
    }
  }

  List<Record> get liveRecords => _records.values
      .where((r) => r['deleted'] != true)
      .map((r) => Map<String, dynamic>.from(r))
      .toList();

  /// Old works become ordinary folders. Stable ids make interrupted migration resumable.
  Future<void> migrateFolders() async {
    if (get('migration-folders-v1') != null) return;
    for (final p in all('project').where((p) => p['id'] != 'workspace')) {
      final folderId = 'work-${p['id']}';
      if (get(folderId) == null) {
        await save('directory', {
          'title': p['title'],
          'directory': '',
          'project': 'workspace',
        }, id: folderId);
      }
      for (final r in liveRecords.where((r) => r['project'] == p['id'])) {
        await save(r['type'] as String, {
          'project': 'workspace',
          if ((r['directory'] ?? '') == '' &&
              ['character', 'directory', 'note'].contains(r['type']))
            'directory': folderId,
        }, id: r['id'] as String);
      }
    }
    await save('migration', {}, id: 'migration-folders-v1');
  }

  Future<List<Record>> snapshots() async {
    final dir = Directory('${root.path}/snapshots');
    await dir.create(recursive: true);
    final result = <Record>[];
    await for (final f in dir.list()) {
      if (f is File && f.path.endsWith('.json')) {
        try {
          result.add(
            Map<String, dynamic>.from(
              jsonDecode(await f.readAsString()) as Map,
            ),
          );
        } catch (_) {
          warnings.add('손상된 임시버전 파일');
        }
      }
    }
    result.sort(
      (a, b) => (b['savedAt'] as String).compareTo(a['savedAt'] as String),
    );
    return result;
  }

  Future<void> checkpoint({DateTime? now, bool force = false}) async {
    final time = (now ?? DateTime.now()).toUtc();
    final previous = await snapshots();
    for (final r in liveRecords.where(
      (r) => ['character', 'note'].contains(r['type']),
    )) {
      final old = previous.where((s) => s['sourceId'] == r['id']).firstOrNull;
      final signature = jsonEncode([
        r['title'],
        r['body'],
        r['document'],
        r['tags'],
        r['cast'],
        r['scenes'],
      ]);
      if (old?['signature'] == signature) continue;
      if (!force &&
          old != null &&
          time.difference(DateTime.parse(old['savedAt'] as String)) <
              const Duration(minutes: 30)) {
        continue;
      }
      final id = uuid.v4();
      final kind = r['type'] == 'character'
          ? '캐릭터'
          : r['section'] == 'memo'
          ? '노트'
          : '스토리';
      final value = {
        'id': id,
        'sourceId': r['id'],
        'savedAt': time.toIso8601String(),
        'label':
            '${kind}_${time.toLocal().toIso8601String().substring(0, 19).replaceAll(':', '-')}',
        'signature': signature,
        'record': r,
      };
      final f = File('${root.path}/snapshots/$id.json');
      await File('${f.path}.tmp').writeAsString(jsonEncode(value), flush: true);
      await File('${f.path}.tmp').rename(f.path);
    }
    final days = preferences['retentionDays'] as int? ?? 30;
    if (days > 0) {
      for (final s in await snapshots()) {
        if (time.difference(DateTime.parse(s['savedAt'] as String)) >
            Duration(days: days)) {
          await deleteSnapshot(s['id'] as String);
        }
      }
    }
  }

  Future<void> deleteSnapshot(String id) async {
    if (!RegExp(r'^[a-zA-Z0-9-]+$').hasMatch(id)) {
      throw const FormatException('잘못된 버전');
    }
    final f = File('${root.path}/snapshots/$id.json');
    if (await f.exists()) await f.delete();
  }

  Future<void> restoreSnapshot(Record snapshot) async {
    final r = Map<String, dynamic>.from(snapshot['record'] as Map);
    await checkpoint(force: true);
    await save(r['type'] as String, {
      ...r,
      'deleted': false,
    }, id: r['id'] as String);
  }

  static const uuid = Uuid();
  List<Record> all(String type, {String? project}) =>
      _records.values
          .where(
            (r) =>
                r['type'] == type &&
                r['deleted'] != true &&
                (project == null || r['project'] == project),
          )
          .map((r) => Map<String, dynamic>.from(r))
          .toList()
        ..sort(
          (a, b) => (a['created'] as String).compareTo(b['created'] as String),
        );
  Record? get(String? id) =>
      _records[id] == null ? null : Map<String, dynamic>.from(_records[id]!);
  File media(String name) {
    if (name == '.' ||
        name == '..' ||
        !RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(name)) {
      throw const FormatException('잘못된 이미지 경로입니다.');
    }
    return File('${root.path}/media/$name');
  }

  Future<void> load({bool fast = false}) {
    final result = _writes.then((_) async {
      if (fast) {
        try {
          final data =
              jsonDecode(await File('${root.path}/index.json').readAsString())
                  as Map;
          final stamp = (await Directory(
            '${root.path}/revisions',
          ).stat()).modified.toUtc().toIso8601String();
          if (data['version'] == 1 && data['stamp'] == stamp) {
            _records.clear();
            for (final raw in data['records'] as List) {
              final r = Map<String, dynamic>.from(raw as Map);
              _records[r['id'] as String] = r;
            }
            conflicts.clear();
            for (final e in (data['conflicts'] as Map).entries) {
              conflicts[e.key as String] = (e.value as List)
                  .map((r) => Map<String, dynamic>.from(r as Map))
                  .toList();
            }
            settings.value = preferences;
            notifyListeners();
            return;
          }
        } catch (_) {}
      }
      await _load();
      await _writeIndex();
    });
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> _load() async {
    await Directory('${root.path}/revisions').create(recursive: true);
    await Directory('${root.path}/media').create(recursive: true);
    _records.clear();
    warnings.clear();
    conflicts.clear();
    final histories = <String, List<Record>>{};
    await for (final file in Directory('${root.path}/revisions').list()) {
      if (file is! File || !file.path.endsWith('.json')) continue;
      try {
        final r = Map<String, dynamic>.from(
          jsonDecode(await file.readAsString()) as Map,
        );
        if (r['schema'] != 1 ||
            r['id'] is! String ||
            r['revision'] is! String ||
            r['generation'] is! int ||
            r['type'] is! String ||
            r['created'] is! String) {
          throw const FormatException('Invalid revision');
        }
        final previous = _records[r['id']];
        histories.putIfAbsent(r['id'] as String, () => []).add(r);
        if (previous == null ||
            (r['generation'] as int) > (previous['generation'] as int) ||
            (r['generation'] == previous['generation'] &&
                (r['revision'] as String).compareTo(
                      previous['revision'] as String,
                    ) >
                    0)) {
          _records[r['id'] as String] = r;
        } else if (r['generation'] == previous['generation'] &&
            r['revision'] != previous['revision']) {
          warnings.add('중복된 수정 이력이 발견되었습니다: ${r['title'] ?? r['id']}');
        }
      } catch (_) {
        warnings.add('읽을 수 없는 수정 이력: ${file.uri.pathSegments.last}');
      }
    }
    for (final entry in histories.entries) {
      final ancestors = <String>{};
      for (final r in entry.value) {
        if (r['parentRevision'] is String) {
          ancestors.add(r['parentRevision'] as String);
        }
        ancestors.addAll(
          List<String>.from(r['resolvedRevisions'] as List? ?? []),
        );
      }
      final heads = entry.value
          .where((r) => !ancestors.contains(r['revision']))
          .toList();
      if (heads.length > 1) conflicts[entry.key] = heads;
    }
    settings.value = preferences;
    notifyListeners();
  }

  Future<void> resolveConflict(String id, Record chosen) async {
    await save(chosen['type'] as String, {
      ...chosen,
      'resolvedRevisions':
          conflicts[id]?.map((r) => r['revision']).toList() ?? [],
    }, id: id);
    conflicts.remove(id);
    notifyListeners();
  }

  Future<Record> save(
    String type,
    Record fields, {
    String? id,
    Record? textBase,
    bool silent = false,
  }) {
    final snapshot = Map<String, dynamic>.from(_copyJson(fields) as Map);
    final result = _writes.then(
      (_) => _save(type, snapshot, id: id, textBase: textBase, silent: silent),
    );
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<Record> _save(
    String type,
    Record fields, {
    String? id,
    Record? textBase,
    bool silent = false,
  }) async {
    final previous = _records[id];
    final diverged =
        textBase != null &&
        previous != null &&
        !_sameJson(
          [textBase['title'], textBase['body'], textBase['document']],
          [previous['title'], previous['body'], previous['document']],
        );
    final now = DateTime.now().toUtc().toIso8601String();
    final record = <String, dynamic>{
      ...?previous,
      ...fields,
      'schema': 1,
      'id': id ?? uuid.v4(),
      'type': type,
      'created': previous?['created'] ?? now,
      'updated': now,
      'revision': uuid.v4(),
      'parentRevision': diverged ? textBase['revision'] : previous?['revision'],
      'generation': ((previous?['generation'] as int?) ?? 0) + 1,
    };
    if (previous != null &&
        ['character', 'note'].contains(type) &&
        !_sameJson(
          [
            previous['title'],
            previous['body'],
            previous['document'],
            previous['tags'],
          ],
          [record['title'], record['body'], record['document'], record['tags']],
        )) {
      await _remember(previous);
    }
    final target = File('${root.path}/revisions/${record['revision']}.json');
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsString(await _encodeStoredJson(record), flush: true);
    await temporary.rename(target.path);
    _records[record['id'] as String] = record;
    if (diverged) {
      conflicts[record['id'] as String] = [...?conflicts[id], previous, record];
    }
    if (type == 'preferences') settings.value = preferences;
    _scheduleIndex();
    if (!silent && !_closed) notifyListeners();
    return Map<String, dynamic>.from(record);
  }

  Future<void> remove(Record record) async {
    await save(record['type'] as String, {
      'deleted': true,
    }, id: record['id'] as String);
  }

  /// Preserve legacy unassigned images inside a recoverable character folder.
  Future<void> attachLegacyImages() async {
    for (final p in all('project')) {
      final projectId = p['id'] as String;
      final characters = all(
        'character',
        project: projectId,
      ).map((c) => c['id']).toSet();
      final loose = all(
        'asset',
        project: projectId,
      ).where((a) => !characters.contains(a['character'])).toList();
      if (loose.isEmpty) continue;
      final recoveryId = 'legacy-images-$projectId';
      if (get(recoveryId) == null) {
        await save('character', {
          'project': projectId,
          'title': '미분류 캐릭터',
          'body': '이전 버전에서 캐릭터에 연결되지 않은 이미지입니다. 이미지를 다른 캐릭터 폴더로 끌어 옮길 수 있습니다.',
        }, id: recoveryId);
      }
      for (final a in loose) {
        await save('asset', {'character': recoveryId}, id: a['id'] as String);
      }
    }
  }

  Future<Record> importImage(
    File source,
    String name,
    String project,
    String folder, {
    String? character,
  }) async {
    final ext = name.split('.').last.toLowerCase();
    if (!['png', 'jpg', 'jpeg', 'webp', 'gif'].contains(ext)) {
      throw const FormatException('지원하는 이미지: PNG, JPG, WEBP, GIF');
    }
    final storedName = '${uuid.v4()}.$ext';
    final destination = media(storedName);
    await source.copy('${destination.path}.tmp');
    await File('${destination.path}.tmp').rename(destination.path);
    try {
      return await save('asset', {
        'project': project,
        'title': name,
        'file': storedName,
        'sourcePath': source.absolute.path,
        'folder': folder,
        'tags': <String>[],
        'character': character,
      });
    } catch (_) {
      await destination.delete();
      rethrow;
    }
  }
}
