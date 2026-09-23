import 'studio_dropdown.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'store.dart';

class NotionClient {
  NotionClient(this.token, {http.Client? client})
    : client = client ?? http.Client();
  final String token;
  final http.Client client;
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.https('api.notion.com', '/v1/$path');
    final headers = {
      'Authorization': 'Bearer $token',
      'Notion-Version': '2022-06-28',
      'Content-Type': 'application/json',
    };
    for (var attempt = 0; attempt < 4; attempt++) {
      final res =
          await (body == null
                  ? client.get(uri, headers: headers)
                  : client.post(uri, headers: headers, body: jsonEncode(body)))
              .timeout(const Duration(seconds: 30));
      if (res.statusCode == 429) {
        await Future<void>.delayed(
          Duration(
            seconds:
                int.tryParse(res.headers['retry-after'] ?? '')?.clamp(1, 10) ??
                2,
          ),
        );
        continue;
      }
      if (res.statusCode != 200) {
        throw FormatException(
          'Notion 요청 실패 (${res.statusCode}). 연결 권한과 토큰을 확인하세요.',
        );
      }
      return Map<String, dynamic>.from(jsonDecode(res.body) as Map);
    }
    throw const FormatException('Notion 요청 제한입니다. 잠시 후 다시 시도하세요.');
  }

  Future<List<Record>> pages() async {
    final result = <Record>[];
    String? cursor;
    do {
      final data = await request(
        'search',
        body: {
          'filter': {'value': 'page', 'property': 'object'},
          'page_size': 100,
          'start_cursor': ?cursor,
        },
      );
      for (final raw in data['results'] as List) {
        final r = Map<String, dynamic>.from(raw as Map);
        final props = r['properties'] as Map? ?? {};
        var title = '제목 없음';
        for (final v in props.values) {
          if (v is Map && v['type'] == 'title') {
            title = (v['title'] as List)
                .map((t) => t['plain_text'] ?? t['text']?['content'] ?? '')
                .join();
          }
        }
        result.add({'id': r['id'], 'title': title, 'url': r['url']});
      }
      cursor = data['has_more'] == true ? data['next_cursor'] as String? : null;
    } while (cursor != null);
    return result;
  }

  Future<String> content(String id, {Set<String>? visited}) async {
    final seen = visited ?? <String>{};
    if (!seen.add(id)) return '';
    final output = StringBuffer();
    String? cursor;
    do {
      final suffix = cursor == null ? '' : '?start_cursor=$cursor';
      // Cursor is a Notion-generated UUID. Construct the query separately.
      final uri = Uri.https('api.notion.com', '/v1/blocks/$id/children', {
        'page_size': '100',
        'start_cursor': ?cursor,
      });
      final res = await client
          .get(
            uri,
            headers: {
              'Authorization': 'Bearer $token',
              'Notion-Version': '2022-06-28',
            },
          )
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) {
        throw FormatException('페이지 읽기 실패 (${res.statusCode})$suffix');
      }
      final data = jsonDecode(res.body) as Map;
      for (final block in data['results'] as List) {
        final type = block['type'] as String;
        final value = block[type] as Map? ?? {};
        final rich = value['rich_text'] as List? ?? [];
        final text = rich
            .map((t) => t['plain_text'] ?? t['text']?['content'] ?? '')
            .join();
        if (type.startsWith('heading_')) {
          output.writeln(
            '${'#' * (int.tryParse(type.split('_').last) ?? 1)} $text',
          );
        } else if (type == 'image' || type == 'file') {
          output.writeln('[Notion $type: 원본 페이지에서 확인]');
        } else if (type == 'child_page') {
          output.writeln('# ${value['title'] ?? ''}');
        } else if (type == 'unsupported') {
          output.writeln('[지원하지 않는 Notion 블록]');
        } else if (text.isNotEmpty) {
          output.writeln(text);
        }
        if (block['has_children'] == true || type == 'child_page') {
          output.write(await content(block['id'] as String, visited: seen));
        }
      }
      cursor = data['has_more'] == true ? data['next_cursor'] as String? : null;
    } while (cursor != null);
    return output.toString();
  }

  void close() => client.close();
}

String detectKind(String title, String text) {
  final s = '$title\n$text';
  final character = RegExp('성격|외형|나이|종족|캐릭터|인물').allMatches(s).length;
  final story = RegExp('장면|사건|스토리|줄거리|플롯|챕터').allMatches(s).length;
  return character > story
      ? 'character'
      : story > 0
      ? 'story'
      : 'memo';
}

class NotionImport extends StatefulWidget {
  const NotionImport({super.key, required this.store});
  final WorkspaceStore store;
  @override
  State<NotionImport> createState() => _NotionImportState();
}

class _NotionImportState extends State<NotionImport> {
  final token = TextEditingController();
  final chosen = <String>{};
  List<Record> pages = [], candidates = [];
  bool busy = false;
  String status = '';
  static const storage = FlutterSecureStorage();
  @override
  void dispose() {
    token.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function(NotionClient) task) async {
    setState(() => busy = true);
    NotionClient? client;
    try {
      final key = token.text.trim().isNotEmpty
          ? token.text.trim()
          : await storage.read(key: 'storyloom.notion');
      if (key == null || key.isEmpty) {
        throw const FormatException('Notion 연결 토큰을 입력하세요.');
      }
      await storage.write(key: 'storyloom.notion', value: key);
      client = NotionClient(key);
      await task(client);
    } catch (e) {
      if (mounted) {
        setState(
          () =>
              status = e is FormatException ? e.message : '연결 또는 가져오기에 실패했습니다.',
        );
      }
    } finally {
      client?.close();
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> review(NotionClient c) async {
    final result = <Record>[];
    for (final page in pages.where((p) => chosen.contains(p['id']))) {
      final text = await c.content(page['id'] as String);
      result.add({
        ...page,
        'body': text,
        'kind': detectKind(page['title'] as String, text),
        'include': true,
      });
    }
    if (mounted) setState(() => candidates = result);
  }

  Future<void> import() async {
    setState(() => busy = true);
    var count = 0;
    try {
      for (final row in candidates.where((r) => r['include'] == true)) {
        final kind = row['kind'];
        final existing = widget.store.liveRecords
            .where((r) => r['notionId'] == row['id'])
            .firstOrNull;
        if (existing != null) continue;
        await widget.store.save(kind == 'character' ? 'character' : 'note', {
          'project': 'workspace',
          'directory': '',
          'title': row['title'],
          'body': row['body'],
          'section': kind == 'memo' ? 'memo' : 'story',
          'notionId': row['id'],
          'sourceUrl': row['url'],
        });
        count++;
      }
      if (mounted) {
        setState(() => status = '$count개 가져왔습니다. 이미 가져온 페이지는 건너뛰었습니다.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => status = '일부 항목을 저장하지 못했습니다. 다시 시도하면 중복은 건너뜁니다.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Notion 가져오기',
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      const Text(
        'Notion 연결에 공유한 페이지를 읽습니다. 페이지와 하위 내용을 검토한 뒤 가져옵니다. 복잡한 서식과 첨부 파일은 원본 링크로 확인하세요.',
      ),
      const SizedBox(height: 12),
      TextField(
        controller: token,
        obscureText: true,
        decoration: const InputDecoration(
          labelText: 'Notion 연결 토큰 (기기 보안 저장소 보관)',
        ),
      ),
      Wrap(
        spacing: 8,
        children: [
          OutlinedButton(
            onPressed: busy
                ? null
                : () => run((c) async {
                    final p = await c.pages();
                    if (mounted) setState(() => pages = p);
                  }),
            child: const Text('페이지 목록'),
          ),
          OutlinedButton(
            onPressed: busy || chosen.isEmpty ? null : () => run(review),
            child: const Text('선택 페이지 검토'),
          ),
        ],
      ),
      if (busy) const LinearProgressIndicator(),
      if (pages.isNotEmpty)
        SizedBox(
          height: 200,
          child: ListView(
            children: pages
                .map(
                  (p) => CheckboxListTile(
                    value: chosen.contains(p['id']),
                    title: Text(p['title'] as String),
                    onChanged: busy
                        ? null
                        : (v) => setState(
                            () => v == true
                                ? chosen.add(p['id'] as String)
                                : chosen.remove(p['id']),
                          ),
                  ),
                )
                .toList(),
          ),
        ),
      for (final row in candidates)
        Card(
          child: ExpansionTile(
            title: Text(row['title'] as String),
            subtitle: const Text('자동 추정 결과 · 분류와 내용을 확인하세요'),
            children: [
              CheckboxListTile(
                value: row['include'] as bool,
                title: const Text('가져오기'),
                onChanged: busy
                    ? null
                    : (v) => setState(() => row['include'] = v),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextFormField(
                  initialValue: row['title'] as String,
                  onChanged: (v) => row['title'] = v,
                  decoration: const InputDecoration(labelText: '제목'),
                ),
              ),
              StudioDropdown<String>(
                value: row['kind'] as String,
                items: const [
                  DropdownMenuItem(value: 'character', child: Text('캐릭터')),
                  DropdownMenuItem(value: 'story', child: Text('스토리')),
                  DropdownMenuItem(value: 'memo', child: Text('노트')),
                ],
                onChanged: busy ? null : (v) => setState(() => row['kind'] = v),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: SelectableText(row['body'] as String),
              ),
            ],
          ),
        ),
      if (candidates.isNotEmpty)
        FilledButton(
          onPressed: busy ? null : import,
          child: const Text('검토한 항목 일괄 가져오기'),
        ),
      Text(status),
    ],
  );
}
