import 'studio_dropdown.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const emojiGroups = {
  'Smileys & Emotion': '표정·감정',
  'People & Body': '인물·몸짓',
  'Animals & Nature': '동물·자연',
  'Food & Drink': '음식·음료',
  'Travel & Places': '여행·장소',
  'Activities': '활동·운동',
  'Objects': '사물',
  'Symbols': '기호',
  'Flags': '깃발',
};

class EmojiPicker extends StatefulWidget {
  const EmojiPicker({super.key});
  @override
  State<EmojiPicker> createState() => _EmojiPickerState();
}

class _EmojiPickerState extends State<EmojiPicker> {
  static Future<List<dynamic>>? catalog;
  final search = TextEditingController();
  String group = '전체';
  int tone = 0;
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('이모티콘'),
    content: SizedBox(
      width: 640,
      height: 520,
      child: Column(
        children: [
          TextField(
            key: const ValueKey('emoji-search'),
            controller: search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: '이름으로 검색 · 고양이, 하트, smile',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: StudioDropdown<String>(
                  isExpanded: true,
                  value: group,
                  items: ['전체', ...emojiGroups.values]
                      .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                      .toList(),
                  onChanged: (g) => setState(() => group = g!),
                ),
              ),
              const SizedBox(width: 16),
              StudioDropdown<int>(
                value: tone,
                items: [
                  const DropdownMenuItem(value: 0, child: Text('기본 피부색')),
                  const DropdownMenuItem(value: -1, child: Text('모든 피부색')),
                  for (var i = 1; i <= 5; i++)
                    DropdownMenuItem(
                      value: i,
                      child: Text(
                        '✋${String.fromCharCode(0x1f3fa + i)}',
                        style: const TextStyle(
                          fontFamily: 'NotoEmoji',
                          fontSize: 24,
                        ),
                      ),
                    ),
                ],
                onChanged: (t) => setState(() => tone = t!),
              ),
            ],
          ),
          Expanded(
            child: FutureBuilder<List<dynamic>>(
              future: catalog ??= rootBundle
                  .loadString('assets/emoji/catalog.json')
                  .then((s) => jsonDecode(s) as List<dynamic>),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('이모티콘 목록을 읽지 못했습니다.'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final query = search.text.trim().toLowerCase();
                final items = snapshot.data!.where((e) {
                  final emoji = e['emoji'] as String;
                  final tones = emoji.runes.where(
                    (r) => r >= 0x1f3fb && r <= 0x1f3ff,
                  );
                  return (group == '전체' || emojiGroups[e['group']] == group) &&
                      (tone == -1 ||
                          tones.isEmpty ||
                          tone > 0 &&
                              tones.every((r) => r == 0x1f3fa + tone)) &&
                      (query.isEmpty ||
                          '${e['ko']} ${e['name']} $emoji'
                              .toLowerCase()
                              .contains(query));
                }).toList();
                if (items.isEmpty) {
                  return const Center(child: Text('검색 결과가 없습니다.'));
                }
                return GridView.builder(
                  key: ValueKey('$group-$tone-$query'),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 64,
                    mainAxisExtent: 56,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final e = items[i];
                    return Tooltip(
                      message: (e['ko'] as String).isEmpty
                          ? e['name']
                          : e['ko'],
                      child: TextButton(
                        style: TextButton.styleFrom(
                          minimumSize: Size.zero,
                          padding: EdgeInsets.zero,
                        ),
                        onPressed: () =>
                            Navigator.pop(context, e['emoji'] as String),
                        child: Text(
                          e['emoji'],
                          style: const TextStyle(
                            fontFamily: 'NotoEmoji',
                            fontSize: 28,
                            height: 1.2,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('닫기'),
      ),
    ],
  );
}
