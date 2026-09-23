import 'studio_dropdown.dart';
import 'package:flutter/material.dart';
import 'store.dart';

class HistorySettings extends StatefulWidget {
  const HistorySettings({super.key, required this.store});
  final WorkspaceStore store;
  @override
  State<HistorySettings> createState() => _HistorySettingsState();
}

class _HistorySettingsState extends State<HistorySettings> {
  String status = '';
  late Future<List<Record>> changes;
  @override
  void initState() {
    super.initState();
    changes = widget.store.recentChanges();
  }

  void reload() {
    setState(() => changes = widget.store.recentChanges());
  }

  Future<void> browse() async {
    final rows = await widget.store.snapshots();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: const Text('텍스트 임시버전'),
          content: SizedBox(
            width: 720,
            height: 480,
            child: rows.isEmpty
                ? const Center(child: Text('저장된 임시버전이 없습니다.'))
                : ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (c, i) {
                      final s = rows[i];
                      final r = s['record'] as Map;
                      return ExpansionTile(
                        title: Text('${s['label']} · ${r['title']}'),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: SelectableText(r['body'] as String? ?? ''),
                          ),
                          Wrap(
                            spacing: 8,
                            children: [
                              TextButton(
                                onPressed: () async {
                                  try {
                                    await widget.store.restoreSnapshot(s);
                                    if (c.mounted) Navigator.pop(c);
                                  } catch (_) {
                                    if (mounted) {
                                      setState(() => status = '복원 실패');
                                    }
                                  }
                                },
                                child: const Text('이 버전 복원'),
                              ),
                              TextButton(
                                onPressed: () async {
                                  await widget.store.deleteSnapshot(
                                    s['id'] as String,
                                  );
                                  update(() => rows.removeAt(i));
                                },
                                child: const Text('임시버전 삭제'),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('닫기'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.store.preferences;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '자동저장과 임시버전',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('입력 종료 2초 후 자동저장'),
          value: p['autosave'] != false,
          onChanged: (v) => widget.store.setPreferences({'autosave': v}),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '변경 사항',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '변경 목록 새로고침',
                      onPressed: reload,
                      icon: const Icon(Icons.refresh, size: 24),
                    ),
                  ],
                ),
                StudioDropdownField<int>(
                  initialValue: p['historyCount'] as int? ?? 50,
                  decoration: const InputDecoration(
                    labelText: '글 하나당 이전 변경 사항 보관 개수',
                  ),
                  items: [10, 20, 50, 100, 200, 0]
                      .map(
                        (n) => DropdownMenuItem(
                          value: n,
                          child: Text(n == 0 ? '제한 없음' : '$n개'),
                        ),
                      )
                      .toList(),
                  onChanged: (n) async {
                    await widget.store.setPreferences({'historyCount': n});
                    if (mounted) reload();
                  },
                ),
                const SizedBox(height: 8),
                const Text(
                  '입력 중 저장된 이전 상태를 복원합니다. 이 목록은 이 기기에 보관됩니다. 동기화 충돌 판별용 기록과 30분 임시버전은 별도로 관리합니다.',
                  style: TextStyle(fontSize: 14),
                ),
                SizedBox(
                  height: 300,
                  child: FutureBuilder<List<Record>>(
                    future: changes,
                    builder: (c, s) {
                      if (s.hasError) {
                        return const Center(child: Text('변경 목록을 읽지 못했습니다.'));
                      }
                      if (!s.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final rows = s.data!;
                      if (rows.isEmpty) {
                        return const Center(child: Text('이전 변경 사항이 없습니다.'));
                      }
                      return ListView.builder(
                        itemCount: rows.length,
                        itemBuilder: (c, i) {
                          final r = rows[i];
                          final date =
                              DateTime.tryParse(
                                r['updated'] as String? ?? '',
                              )?.toLocal().toString() ??
                              '';
                          return ExpansionTile(
                            title: Text(
                              '${r['type'] == 'character'
                                  ? '캐릭터'
                                  : r['section'] == 'memo'
                                  ? '노트'
                                  : '스토리'} · ${r['title']}',
                            ),
                            subtitle: Text(date),
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: SelectableText(
                                  r['body'] as String? ?? '',
                                ),
                              ),
                              TextButton(
                                onPressed: () async {
                                  try {
                                    await widget.store.restoreChange(r);
                                    if (mounted) {
                                      setState(
                                        () => status = '선택한 변경 사항을 복원했습니다.',
                                      );
                                      reload();
                                    }
                                  } catch (_) {
                                    if (mounted) {
                                      setState(() => status = '복원에 실패했습니다.');
                                    }
                                  }
                                },
                                child: const Text('이 상태로 복원'),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text('변경된 텍스트는 30분마다 별도 임시버전으로 보관합니다.'),
        const SizedBox(height: 12),
        StudioDropdownField<int>(
          initialValue: p['retentionDays'] as int? ?? 30,
          decoration: const InputDecoration(labelText: '임시버전 보관 기간'),
          items: const [
            DropdownMenuItem(value: 30, child: Text('30일')),
            DropdownMenuItem(value: 7, child: Text('1주일')),
            DropdownMenuItem(value: 1, child: Text('1일')),
            DropdownMenuItem(value: 0, child: Text('삭제하지 않음')),
          ],
          onChanged: (v) => widget.store.setPreferences({'retentionDays': v}),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: browse,
          icon: const Icon(Icons.history, size: 20),
          label: const Text('임시버전 보기·복원'),
        ),
        if (status.isNotEmpty) Text(status),
      ],
    );
  }
}
