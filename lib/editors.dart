import 'studio_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'store.dart';

class EditDialog extends StatefulWidget {
  const EditDialog({super.key, required this.type, this.record, this.store});
  final String type;
  final Record? record;
  final WorkspaceStore? store;
  @override
  State<EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<EditDialog> {
  late final title = TextEditingController(
    text: widget.record?['title'] as String? ?? '',
  );
  late final body = TextEditingController(
    text: widget.record?['body'] as String? ?? '',
  );
  late String kind = widget.record?['kind'] as String? ?? '아이디어';
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    title.dispose();
    body.dispose();
    super.dispose();
  }

  void submit() {
    if (form.currentState!.validate()) {
      Navigator.pop(context, {
        'title': title.text.trim(),
        'body': body.text,
        'kind': kind,
      });
    }
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.enter, control: true): submit,
    },
    child: AlertDialog(
      title: Text(
        '${{'project': '작품', 'character': '캐릭터', 'note': '노트', 'folder': '폴더'}[widget.type]} ${widget.record == null ? '만들기' : '편집'}',
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.type == 'character' &&
                    widget.record != null &&
                    widget.store != null)
                  SizedBox(
                    height: 140,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: widget.store!
                          .all(
                            'asset',
                            project: widget.record!['project'] as String?,
                          )
                          .where((a) => a['character'] == widget.record!['id'])
                          .map(
                            (a) => Padding(
                              padding: EdgeInsets.only(right: 8, bottom: 12),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.file(
                                  widget.store!.media(a['file'] as String),
                                  width: 110,
                                  fit: BoxFit.cover,
                                  cacheWidth: 240,
                                  errorBuilder: (_, _, _) =>
                                      Icon(Icons.broken_image_outlined),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                TextFormField(
                  controller: title,
                  autofocus: true,
                  onFieldSubmitted: (_) => submit(),
                  decoration: InputDecoration(labelText: '이름 / 제목'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? '제목을 입력하세요.' : null,
                ),
                if (widget.type == 'note') ...[
                  SizedBox(height: 16),
                  StudioDropdownField<String>(
                    initialValue: kind,
                    decoration: InputDecoration(labelText: '종류'),
                    items: ['아이디어', '유저노트', '프롬프트', '스토리라인', '장면', '세계관']
                        .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                        .toList(),
                    onChanged: (v) {
                      kind = v!;
                    },
                  ),
                ],
                if (widget.type != 'folder') ...[
                  SizedBox(height: 16),
                  TextField(
                    controller: body,
                    minLines: 6,
                    maxLines: 12,
                    decoration: InputDecoration(
                      labelText: widget.type == 'character' ? '설정' : '내용',
                      hintText: widget.type == 'character'
                          ? '성격, 외형, 배경, 관계, 비밀…'
                          : '떠오른 생각을 자유롭게 적어보세요.',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text('취소')),
        FilledButton(onPressed: submit, child: Text('저장')),
      ],
    ),
  );
}

class ClassificationDialog extends StatefulWidget {
  const ClassificationDialog({
    super.key,
    required this.characters,
    required this.folders,
  });
  final List<Record> characters, folders;
  @override
  State<ClassificationDialog> createState() => _ClassificationDialogState();
}

class _ClassificationDialogState extends State<ClassificationDialog> {
  final tags = TextEditingController();
  String? folder, character;
  @override
  void dispose() {
    tags.dispose();
    super.dispose();
  }

  Widget dropdown(
    String label,
    List<Record> items,
    ValueChanged<String?> changed,
  ) => StudioDropdownField<String>(
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    initialValue: 'keep',
    items: [
      DropdownMenuItem(value: 'keep', child: Text('기존 분류 유지')),
      DropdownMenuItem(value: '', child: Text('지정 해제')),
      ...items.map(
        (r) => DropdownMenuItem(
          value: r['id'] as String,
          child: Text(r['title'] as String),
        ),
      ),
    ],
    onChanged: changed,
  );
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('선택 이미지 일괄 분류'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: tags,
              decoration: InputDecoration(
                labelText: '추가할 태그',
                hintText: '교복, 웃음, 전투',
              ),
            ),
            SizedBox(height: 16),
            dropdown('폴더', widget.folders, (v) {
              folder = v;
            }),
            SizedBox(height: 16),
            dropdown('캐릭터', widget.characters, (v) {
              character = v;
            }),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: Text('취소')),
      FilledButton(
        onPressed: () => Navigator.pop(context, <String, dynamic>{
          'tags': tags.text
              .split(',')
              .map((t) => t.trim())
              .where((t) => t.isNotEmpty)
              .toSet()
              .toList(),
          if (folder != null && folder != 'keep') 'folder': folder,
          if (character != null && character != 'keep')
            'character': character == '' ? null : character,
        }),
        child: Text('적용'),
      ),
    ],
  );
}
