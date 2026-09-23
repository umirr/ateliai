import 'studio_dropdown.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as q;
import 'appearance.dart';
import 'chat.dart';
import 'drive_sync.dart';
import 'editors.dart';
import 'history_settings.dart';
import 'notion_import.dart';
import 'rich_editor.dart';
import 'store.dart';
import 'studio_widgets.dart';
export 'studio_widgets.dart';

class Workspace extends StatefulWidget {
  const Workspace({super.key, required this.store});
  final WorkspaceStore store;
  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> with WidgetsBindingObserver {
  final Set<String> selectedCards = {};
  String? selectionAnchor;

  Future<void> selectCard(Record r, List<Record> visible) async {
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (!await save() || !mounted) return;
    final id = r['id'] as String;
    setState(() {
      final ids = visible
          .where((v) => !['parent', 'asset'].contains(v['type']))
          .map((v) => v['id'] as String)
          .toList();
      if (shift && ids.contains(selectionAnchor)) {
        final a = ids.indexOf(selectionAnchor!);
        final b = ids.indexOf(id);
        if (!ctrl) selectedCards.clear();
        selectedCards.addAll(ids.sublist(a < b ? a : b, (a > b ? a : b) + 1));
      } else {
        if (!ctrl) selectedCards.clear();
        if (!ctrl || !selectedCards.remove(id)) selectedCards.add(id);
        selectionAnchor = id;
      }
      if (r['type'] != 'directory' && selectedCards.contains(id)) {
        loadSelection(r);
      } else if (!selectedCards.contains(selected)) {
        selected = null;
      }
    });
  }

  bool canMoveCards(List<String> ids, String target) {
    final memo = module == '노트';
    if (!['캐릭터', '노트'].contains(module) || ids.isEmpty) return false;
    if (target.isNotEmpty) {
      final dest = db.get(target);
      if (dest == null ||
          !['directory', 'character'].contains(dest['type']) ||
          (dest['scope'] == 'memo') != memo) {
        return false;
      }
    }
    for (final id in ids) {
      final r = db.get(id);
      if (r == null ||
          (r['type'] == 'note'
                  ? r['section'] == 'memo'
                  : r['scope'] == 'memo') !=
              memo) {
        return false;
      }
      var ancestor = target;
      final seen = <String>{};
      while (ancestor.isNotEmpty && seen.add(ancestor)) {
        if (ancestor == id) return false;
        ancestor = db.get(ancestor)?['directory'] as String? ?? '';
      }
    }
    return true;
  }

  Future<void> moveCards(List<String> ids, String target) async {
    if (!canMoveCards(ids, target) || !await save()) return;
    for (final id in ids) {
      final r = db.get(id)!;
      await db.save(r['type'] as String, {'directory': target}, id: id);
    }
    if (mounted) setState(clear);
  }

  Widget cardDropTarget(String target, Widget child) =>
      DragTarget<List<String>>(
        onWillAcceptWithDetails: (d) => canMoveCards(d.data, target),
        onAcceptWithDetails: (d) => moveCards(d.data, target),
        builder: (context, candidates, rejected) => DecoratedBox(
          decoration: BoxDecoration(
            border: candidates.isEmpty
                ? null
                : Border.all(color: StudioColors.accent, width: 2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: child,
        ),
      );
  WorkspaceStore get db => widget.store;
  late final DriveSync sync = DriveSync(db);
  String directory = '', module = '캐릭터', query = '', status = '';
  String? selected;
  Record? editingBase;
  String? cutCharacter;
  String? aiReference;
  int aiReferenceRequest = 0;
  double imageTileSize = 188;
  Future<bool>? saveTask;
  int editGeneration = 0;
  final saveFeedback = ValueNotifier<int>(0);
  void markDirty() {
    if (!mounted) return;
    final wasDirty = dirty;
    dirty = true;
    editGeneration++;
    if (!wasDirty) saveFeedback.value++;
    if (db.preferences['autosave'] != false) {
      pendingAutosave?.cancel();
      pendingAutosave = Timer(const Duration(seconds: 2), save);
    }
  }

  bool dirty = false,
      saving = false,
      importing = false,
      aiOpen = false,
      menuOpen = false;
  double split = .5;
  Timer? autosave, checkpoint, pendingAutosave;
  AppLifecycleListener? lifecycle;
  final title = TextEditingController(), tags = TextEditingController();
  q.QuillController rich = documentController(null);
  final selectedImages = <String>{};
  Record? get current => db.get(selected);
  Record? get imageOwner {
    var id = directory;
    final seen = <String>{};
    while (id.isNotEmpty && seen.add(id)) {
      final r = db.get(id);
      if (r == null) break;
      if (r['type'] == 'character') return r;
      id = r['directory'] as String? ?? '';
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    db.addListener(refresh);
    WidgetsBinding.instance.addObserver(this);
    autosave = Timer.periodic(Duration(minutes: 1), (_) => periodic());
    checkpoint = Timer.periodic(Duration(minutes: 30), (_) async {
      if (await save()) {
        try {
          await db.checkpoint();
        } catch (_) {
          notice('임시버전 저장 실패');
        }
      }
    });
    lifecycle = AppLifecycleListener(
      onExitRequested: () async =>
          await save() ? AppExitResponse.exit : AppExitResponse.cancel,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (db.warnings.isNotEmpty) notice(db.warnings.join('\n'));
      if (db.preferences['driveEnabled'] == true) await synchronize();
    });
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      save();
    }
  }

  @override
  void dispose() {
    pendingAutosave?.cancel();
    autosave?.cancel();
    checkpoint?.cancel();
    lifecycle?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    db.removeListener(refresh);
    saveFeedback.dispose();
    title.dispose();
    tags.dispose();
    rich.dispose();
    super.dispose();
  }

  void notice(String text) {
    if (mounted) {
      setState(() => status = text);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> periodic() async {
    // Cloud polling only; local edits are written immediately.
    if (!dirty && db.preferences['driveEnabled'] == true) await synchronize();
  }

  Future<void> synchronize() async {
    if (sync.busy || !await save()) return;
    try {
      final message = await sync.sync();
      if (mounted) {
        setState(() {
          status = message;
          if (selected != null &&
              !dirty &&
              db.get(selected)?['revision'] != editingBase?['revision']) {
            final updated = db.get(selected);
            if (updated == null || updated['deleted'] == true) {
              clear();
            } else {
              loadSelection(updated);
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () =>
              status = e is FormatException ? e.message : '동기화 실패. 다음에 재시도합니다.',
        );
      }
    }
  }

  Future<bool> save() async {
    pendingAutosave?.cancel();
    if (saveTask != null) {
      if (!await saveTask!) return false;
      if (dirty) return save();
      return true;
    }
    if (!dirty || selected == null) return true;
    final task = _saveEdits();
    saveTask = task;
    try {
      return await task;
    } finally {
      saveTask = null;
    }
  }

  Future<bool> _saveEdits() async {
    saving = true;
    try {
      while (dirty && selected != null) {
        final id = selected!, r = current!, generation = editGeneration;
        final fields = {
          'title': title.text,
          'body': rich.document.toPlainText(),
          'document': rich.document.toDelta().toJson(),
          'tags': tags.text
              .split(',')
              .map((v) => v.trim())
              .where((v) => v.isNotEmpty)
              .toSet()
              .toList(),
        };
        final saved = await db.save(
          r['type'] as String,
          fields,
          id: id,
          textBase: editingBase,
          silent: true,
        );
        if (!mounted) return true;
        if (selected == id) {
          editingBase = saved;
          dirty = generation != editGeneration;
          // Body-only saves must not rebuild the gallery, sidebar and IME editor.
          if (r['title'] != saved['title'] ||
              r['tags'].toString() != saved['tags'].toString()) {
            setState(() {});
          }
        }
        if (dirty && pendingAutosave?.isActive == true) break;
      }
      if (mounted) {
        status = '저장됨';
        saveFeedback.value++;
      }
      return true;
    } catch (_) {
      notice('저장 실패: 작성한 내용은 유지됩니다.');
      return false;
    } finally {
      saving = false;
    }
  }

  void loadSelection(Record r) {
    editingBase = r;
    final old = rich;
    rich = documentController(r);
    title.text = r['title'] as String? ?? '';
    tags.text = (r['tags'] as List? ?? []).join(', ');
    selected = r['id'] as String;
    dirty = false;
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  Future<void> select(Record r) async {
    if (!await save() || !mounted) return;
    setState(() => loadSelection(r));
  }

  Future<void> navigate(VoidCallback action) async {
    if (!await save() || !mounted) return;
    setState(action);
  }

  void clear() {
    selectedCards.clear();
    selectionAnchor = null;
    selected = null;
    dirty = false;
    selectedImages.clear();
  }

  Future<void> open(Record r) async {
    if (!await save() || !mounted) return;
    setState(() {
      directory = r['id'] as String;
      selectedCards.clear();
      selectionAnchor = null;
      query = '';
      selectedImages.clear();
      if (r['type'] == 'character') {
        loadSelection(r);
      } else {
        clear();
      }
    });
  }

  List<Record> get path {
    final result = <Record>[];
    var id = directory;
    final seen = <String>{};
    while (id.isNotEmpty && seen.add(id)) {
      final r = db.get(id);
      if (r == null) break;
      result.insert(0, r);
      id = r['directory'] as String? ?? '';
    }
    return result;
  }

  Future<void> create(String type) async {
    if (!await save() || !mounted) return;
    final data = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => EditDialog(type: type == 'directory' ? 'folder' : type),
    );
    if (data == null) return;
    try {
      final r = await db.save(type, {
        ...data,
        'project': 'workspace',
        'directory': module == '스토리' ? '' : directory,
        if (type == 'directory') 'scope': module == '노트' ? 'memo' : 'character',
        if (type == 'note') 'section': module == '노트' ? 'memo' : 'story',
      });
      if (type != 'directory' && mounted) await select(r);
    } catch (_) {
      notice('항목을 만들지 못했습니다.');
    }
  }

  Widget contextArea(Widget child, [Record? r]) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onSecondaryTapUp: (d) => menu(d.globalPosition, r),
    onLongPressStart: (d) => menu(d.globalPosition, r),
    child: child,
  );
  Future<void> menu(Offset position, [Record? r]) async {
    if (menuOpen || importing) return;
    menuOpen = true;
    String? action;
    try {
      final box = Overlay.of(context).context.findRenderObject() as RenderBox;
      action = await showMenu<String>(
        context: context,
        position: RelativeRect.fromRect(
          Rect.fromLTWH(position.dx, position.dy, 1, 1),
          Offset.zero & box.size,
        ),
        color: StudioColors.raised,
        elevation: 4,
        shadowColor: Colors.black38,
        surfaceTintColor: Colors.transparent,
        popUpAnimationStyle: AnimationStyle.noAnimation,
        constraints: BoxConstraints(minWidth: 240, maxWidth: 320),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: StudioColors.line),
        ),
        items: [
          PopupMenuItem<String>(
            enabled: false,
            height: 44,
            child: Text(
              r?['title'] as String? ?? '현재 폴더',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          PopupMenuDivider(),
          if (module == '캐릭터' || module == '노트') ...[
            studioMenuItem(
              'directory',
              '새 폴더',
              Icons.create_new_folder_outlined,
            ),
            if (module == '캐릭터')
              studioMenuItem('character', '새 캐릭터', Icons.person_add_alt),
            if (r?['type'] == 'character' || r?['type'] == 'note')
              studioMenuItem('cut', '잘라내기', Icons.content_cut),
            if (cutCharacter != null &&
                (module == '노트'
                    ? (db.get(cutCharacter)?['section'] == 'memo')
                    : (db.get(cutCharacter)?['type'] == 'character')))
              studioMenuItem(
                'paste',
                module == '캐릭터' ? '캐릭터 붙여넣기' : '노트 붙여넣기',
                Icons.content_paste,
              ),
          ],
          if (module != '캐릭터')
            studioMenuItem(
              'note',
              module == '노트' ? '새 노트' : '새 스토리',
              Icons.note_add_outlined,
            ),
          if (imageOwner != null)
            studioMenuItem(
              'import',
              '이미지 추가',
              Icons.add_photo_alternate_outlined,
            ),
          if (r != null && ['directory', 'character'].contains(r['type'])) ...[
            PopupMenuDivider(),
            studioMenuItem('open', '폴더 열기', Icons.folder_open),
            studioMenuItem('color', '분류 색상', Icons.palette_outlined),
            studioMenuItem('rename', '이름 변경', Icons.edit_outlined),
          ],
          if (r != null && ['character', 'note'].contains(r['type']))
            studioMenuItem('ai', 'AI 채팅으로 연결', Icons.auto_awesome),
          if (r?['type'] == 'asset') ...[
            studioMenuItem('cover', '대표 이미지로 지정', Icons.portrait_outlined),
            studioMenuItem('source', '원본 경로 열기', Icons.folder_open),
          ],
          if (r != null) ...[
            PopupMenuDivider(),
            studioMenuItem(
              'delete',
              '삭제',
              Icons.delete_outline,
              destructive: true,
            ),
          ],
        ],
      );
    } finally {
      menuOpen = false;
    }
    if (!mounted || action == null) return;
    switch (action) {
      case 'ai':
        await save();
        if (mounted) {
          setState(() {
            aiReference = r!['id'] as String;
            aiReferenceRequest++;
            aiOpen = true;
          });
        }
      case 'source':
        final original = r!['sourcePath'] as String?;
        final file = original != null && await File(original).exists()
            ? File(original)
            : db.media(r['file'] as String);
        if (Platform.isWindows) {
          await Process.start('explorer.exe', [file.parent.path]);
          if (original == null || !await File(original).exists()) {
            notice('이전 이미지에는 원본 경로가 없어 보관 경로를 열었습니다.');
          }
        }

      case 'cut':
        if (await save()) {
          setState(() => cutCharacter = r!['id'] as String);
          notice('이동할 폴더에서 붙여넣기를 선택하세요.');
        }
      case 'paste':
        final cut = db.get(cutCharacter);
        if (cut != null && cut['deleted'] != true) {
          await moveCharacter(
            cut,
            r?['type'] == 'directory' ? r!['id'] as String : directory,
          );
          if (mounted) setState(() => cutCharacter = null);
        }
      case 'open':
        await open(r!);
      case 'color':
        await chooseColor(r!);
      case 'rename':
        await rename(r!);
      case 'delete':
        await deleteRecord(r!);
      case 'import':
        await pickImages();
      case 'cover':
        await db.save('character', {
          'cover': r!['id'],
        }, id: r['character'] as String);
      default:
        await create(action);
    }
  }

  Future<String?> prompt(String label, {String value = ''}) async {
    final c = TextEditingController(text: value);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        content: TextField(
          controller: c,
          autofocus: true,
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) Navigator.pop(context, v.trim());
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('취소')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: Text('저장'),
          ),
        ],
      ),
    );
    await Future<void>.delayed(Duration(milliseconds: 250));
    c.dispose();
    return result;
  }

  Future<void> rename(Record r) async {
    if (!await save() || !mounted) return;
    final value = await prompt('이름 변경', value: r['title'] as String);
    if (value != null && value.isNotEmpty) {
      await db.save(r['type'] as String, {
        'title': value,
      }, id: r['id'] as String);
      if (selected == r['id']) title.text = value;
    }
  }

  Future<void> chooseColor(Record r) async {
    if (!await save() || !mounted) return;
    final value = await showDialog<int>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('분류 색상'),
        content: SizedBox(
          width: 300,
          child: GridView.count(
            shrinkWrap: true,
            crossAxisCount: 5,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            children: [
              for (var i = 0; i < classificationColors.length; i++)
                InkWell(
                  key: ValueKey('classification-color-$i'),
                  onTap: () =>
                      Navigator.pop(c, classificationColors[i].toARGB32()),
                  child: Container(
                    decoration: BoxDecoration(
                      color: classificationColors[i],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: r['color'] == classificationColors[i].toARGB32()
                        ? Icon(Icons.check, color: Colors.black87, size: 24)
                        : null,
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, -1),
            child: Text('색상 지우기'),
          ),
          TextButton(onPressed: () => Navigator.pop(c), child: Text('취소')),
        ],
      ),
    );
    if (value != null) {
      try {
        await db.save(r['type'] as String, {
          'color': value == -1 ? null : value,
        }, id: r['id'] as String);
      } catch (_) {
        notice('색상 저장 실패');
      }
    }
  }

  Future<void> deleteRecord(Record r) async {
    if (!await save() || !mounted) return;
    final ids = <String>{r['id'] as String};
    bool added = true;
    while (added) {
      added = false;
      for (final item in db.liveRecords) {
        if ((item['type'] != 'note' || r['scope'] == 'memo') &&
            (ids.contains(item['directory']) ||
                ids.contains(item['character']) ||
                ids.contains(item['folder']))) {
          if (ids.add(item['id'] as String)) {
            added = true;
          }
        }
      }
    }
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('${r['title']} 삭제'),
        content: Text('${ids.length}개 항목을 삭제합니다. 원본 파일과 수정 이력은 유지됩니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text('삭제'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    try {
      for (final id in ids) {
        await db.remove(db.get(id)!);
      }
      if (mounted) {
        setState(() {
          if (ids.contains(selected)) clear();
          if (ids.contains(directory)) directory = '';
        });
      }
    } catch (_) {
      notice('삭제 실패');
    }
  }

  Future<void> importPaths(List<String> files, String owner) async {
    if (importing || saving) return;
    setState(() => importing = true);
    int done = 0;
    try {
      for (final file in files) {
        await db.importImage(
          File(file),
          File(file).uri.pathSegments.last,
          'workspace',
          directory == owner ? '' : directory,
          character: owner,
        );
        done++;
      }
    } catch (_) {
      notice('일부 이미지를 추가하지 못했습니다.');
    } finally {
      if (mounted) {
        setState(() {
          importing = false;
          status = '$done장 추가됨';
        });
      }
    }
  }

  Future<void> pickImages() async {
    final owner = imageOwner;
    if (owner == null) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );
    if (result != null) {
      await importPaths(
        result.files.where((f) => f.path != null).map((f) => f.path!).toList(),
        owner['id'] as String,
      );
    }
  }

  Future<void> moveCharacter(Record r, String target) async {
    if (!await save() || r['id'] == target) return;
    final note = r['type'] == 'note';
    if (target.isNotEmpty && (db.get(target)?['scope'] == 'memo') != note) {
      return;
    }
    var ancestor = target;
    final seen = <String>{};
    while (ancestor.isNotEmpty && seen.add(ancestor)) {
      if (ancestor == r['id']) return;
      ancestor = db.get(ancestor)?['directory'] as String? ?? '';
    }
    await db.save(r['type'] as String, {
      'directory': target,
    }, id: r['id'] as String);
  }

  Future<void> zoom(Record a) async => showDialog<void>(
    context: context,
    builder: (c) => Dialog(
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: InteractiveViewer(
                minScale: .5,
                maxScale: 8,
                child: Image.file(
                  db.media(a['file'] as String),
                  errorBuilder: (_, _, _) =>
                      Center(child: Text('이미지를 읽을 수 없습니다.')),
                ),
              ),
            ),
          ),
          Positioned(
            right: 8,
            top: 8,
            child: IconButton(
              tooltip: '닫기',
              onPressed: () => Navigator.pop(c),
              icon: Icon(Icons.close, size: 24),
            ),
          ),
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 760;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 72,
              child: Center(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SlidingTabs(
                        selected: module,
                        onSelected: (m) => navigate(() {
                          module = m;
                          directory = '';
                          query = '';
                          clear();
                        }),
                      ),
                      SizedBox(width: 8),
                      SizedBox(
                        width: 56,
                        height: 56,
                        child: IconButton(
                          tooltip: 'AI 대화',
                          isSelected: aiOpen,
                          style: IconButton.styleFrom(
                            backgroundColor: aiOpen
                                ? StudioColors.accent
                                : StudioColors.raised,
                            foregroundColor: aiOpen
                                ? (ThemeData.estimateBrightnessForColor(
                                            StudioColors.accent,
                                          ) ==
                                          Brightness.light
                                      ? Colors.black
                                      : Colors.white)
                                : StudioColors.text,
                            shape: CircleBorder(
                              side: BorderSide(color: StudioColors.line),
                            ),
                          ),
                          icon: const Icon(
                            Icons.auto_awesome_outlined,
                            size: 24,
                          ),
                          onPressed: () => setState(() => aiOpen = !aiOpen),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    if (wide || !aiOpen)
                      Expanded(
                        child: module == '설정'
                            ? StudioPanel(child: settings())
                            : wide
                            ? LayoutBuilder(
                                builder: (c, b) => Row(
                                  children: [
                                    SizedBox(
                                      width: (b.maxWidth - 8) * split,
                                      child: StudioPanel(child: library()),
                                    ),
                                    MouseRegion(
                                      cursor: SystemMouseCursors.resizeColumn,
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onHorizontalDragUpdate: (d) => setState(
                                          () => split =
                                              (split +
                                                      d.delta.dx /
                                                          (b.maxWidth - 8))
                                                  .clamp(.4, .6),
                                        ),
                                        child: SizedBox(
                                          key: ValueKey('center-divider'),
                                          width: 8,
                                          child: Center(
                                            child: Container(
                                              width: 2,
                                              height: 32,
                                              color: StudioColors.line,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: StudioPanel(child: details()),
                                    ),
                                  ],
                                ),
                              )
                            : StudioPanel(
                                child: selected == null ? library() : details(),
                              ),
                      ),
                    if (aiOpen) ...[
                      if (wide) SizedBox(width: 8),
                      SizedBox(
                        width: wide
                            ? (MediaQuery.sizeOf(context).width * .364).clamp(
                                374.4,
                                546,
                              )
                            : MediaQuery.sizeOf(context).width - 16,
                        child: StudioPanel(
                          child: Column(
                            children: [
                              StudioBar(
                                icon: Icons.auto_awesome_outlined,
                                title: '창작 파트너',
                                trailing: IconButton(
                                  tooltip: '대화 닫기',
                                  onPressed: () =>
                                      setState(() => aiOpen = false),
                                  icon: Icon(Icons.close, size: 20),
                                ),
                              ),
                              Expanded(
                                child: Padding(
                                  padding: EdgeInsets.all(16),
                                  child: ChatPage(
                                    store: db,
                                    project: 'workspace',
                                    beforeSend: save,
                                    requestedReference: aiReference,
                                    referenceRequest: aiReferenceRequest,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            SizedBox(
              height: 32,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: ValueListenableBuilder<int>(
                        valueListenable: saveFeedback,
                        builder: (_, _, _) => Text(
                          dirty
                              ? '저장하지 않은 변경 사항'
                              : status.isEmpty
                              ? '로컬 작업 공간'
                              : status,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: StudioColors.muted,
                          ),
                        ),
                      ),
                    ),
                    if (db.conflicts.isNotEmpty)
                      TextButton(
                        onPressed: () => navigate(() => module = '설정'),
                        child: Text('충돌 ${db.conflicts.length}개'),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget settings() => ListView(
    padding: EdgeInsets.all(24),
    children: [
      HistorySettings(store: db),
      SizedBox(height: 16),
      StudioDropdownField<double>(
        initialValue: (db.preferences['lineHeight'] as num? ?? 1.8).toDouble(),
        decoration: InputDecoration(labelText: '본문 행간'),
        items: [
          1.4,
          1.6,
          1.8,
          2.0,
          2.4,
        ].map((n) => DropdownMenuItem(value: n, child: Text('$n 배'))).toList(),
        onChanged: (n) => db.setPreferences({'lineHeight': n}),
      ),
      Divider(height: 48),
      AppearanceSettings(store: db),
      Divider(height: 48),
      if (db.conflicts.isNotEmpty) ...[
        Text('동기화 충돌', style: TextStyle(fontSize: 22)),
        for (final entry in db.conflicts.entries)
          ExpansionTile(
            title: Text(db.get(entry.key)?['title'] as String? ?? entry.key),
            children: [
              for (final v in entry.value)
                ListTile(
                  title: Text('${v['updated']}'),
                  subtitle: Text(
                    v['body'] as String? ?? '',
                    maxLines: 8,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: TextButton(
                    onPressed: () => db.resolveConflict(entry.key, v),
                    child: Text('이 버전 사용'),
                  ),
                ),
            ],
          ),
        Divider(height: 48),
      ],
      DriveSettings(sync: sync),
      Divider(height: 48),
      OutlinedButton.icon(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (c) => Dialog(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 900, maxHeight: 720),
              child: Column(
                children: [
                  ListTile(
                    title: Text('Notion 가져오기'),
                    trailing: IconButton(
                      onPressed: () => Navigator.pop(c),
                      icon: Icon(Icons.close),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(24),
                      child: NotionImport(store: db),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        icon: Icon(Icons.cloud_download_outlined),
        label: Text('Notion 연결·가져오기'),
      ),
      Divider(height: 48),
      SettingsPage(root: db.root.path),
    ],
  );
  Widget library() {
    final owner = module == '캐릭터' ? imageOwner : null;
    final folders = db
        .all('directory')
        .where(
          (r) =>
              module != '스토리' &&
              (r['scope'] ?? 'character') ==
                  (module == '노트' ? 'memo' : 'character') &&
              (r['directory'] ?? '') == directory,
        );
    final records = db
        .all(module == '캐릭터' ? 'character' : 'note')
        .where(
          (r) =>
              (module == '스토리' ||
                  (module == '캐릭터'
                          ? (r['directory'] ?? '')
                          : (db.get(r['directory'] as String?)?['scope'] ==
                                    'memo'
                                ? r['directory']
                                : '')) ==
                      directory) &&
              (module == '캐릭터' ||
                  (module == '노트'
                      ? r['section'] == 'memo'
                      : r['section'] != 'memo')),
        );
    final assets = owner == null
        ? <Record>[]
        : db
              .all('asset')
              .where(
                (a) =>
                    a['character'] == owner['id'] &&
                    (a['folder'] ?? '') ==
                        (directory == owner['id'] ? '' : directory),
              )
              .toList();
    final items = [...folders, ...records, ...assets]
        .where(
          (r) =>
              query.isEmpty ||
              '${r['title']} ${r['tags'] ?? ''}'.toLowerCase().contains(
                query.toLowerCase(),
              ),
        )
        .toList();
    if (directory.isNotEmpty) {
      items.insert(0, {'id': '..', 'type': 'parent', 'title': '상위 폴더'});
    }
    final order = db.preferences['sort-$module'] as String? ?? 'created-asc';
    items.sort((a, b) {
      if (a['type'] == 'parent') return -1;
      if (b['type'] == 'parent') return 1;
      if ((a['type'] == 'directory') != (b['type'] == 'directory')) {
        return a['type'] == 'directory' ? -1 : 1;
      }
      final field = order.startsWith('name') ? 'title' : 'created';
      final result = (a[field] ?? '').toString().toLowerCase().compareTo(
        (b[field] ?? '').toString().toLowerCase(),
      );
      return (order.endsWith('desc') ? -1 : 1) * result;
    });
    final counts = <String, int>{};
    for (final a in db.all('asset')) {
      final id = a['character'] as String?;
      if (id != null) counts.update(id, (n) => n + 1, ifAbsent: () => 1);
    }
    for (final c in db.all('character')) {
      var parent = c['directory'] as String? ?? '';
      final seen = <String>{};
      while (parent.isNotEmpty && seen.add(parent)) {
        final folder = db.get(parent);
        if (folder == null) break;
        if (folder['type'] == 'directory') {
          counts.update(parent, (n) => n + 1, ifAbsent: () => 1);
        }
        parent = folder['directory'] as String? ?? '';
      }
    }
    if (module == '노트') {
      for (final n in db.all('note').where((r) => r['section'] == 'memo')) {
        var parent = n['directory'] as String? ?? '';
        final seen = <String>{};
        while (parent.isNotEmpty && seen.add(parent)) {
          final folder = db.get(parent);
          if (folder?['scope'] != 'memo') break;
          counts.update(parent, (n) => n + 1, ifAbsent: () => 1);
          parent = folder?['directory'] as String? ?? '';
        }
      }
    }
    Widget content = Column(
      key: ValueKey('left-pane'),
      children: [
        StudioBar(
          icon: Icons.folder_open_outlined,
          title: directory.isEmpty
              ? module
              : db.get(directory)?['title'] as String? ?? module,
          trailing: Text(
            '${items.length} 항목',
            style: TextStyle(fontSize: 14, color: StudioColors.muted),
          ),
        ),
        Padding(
          padding: EdgeInsets.all(16),
          child: TextField(
            key: ValueKey('search-$module-$directory'),
            onChanged: (v) => setState(() => query = v),
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.search, size: 20),
              hintText: '이름 또는 태그 검색',
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: 196,
              child: StudioDropdown<String>(
                key: ValueKey('sort-$module'),
                isExpanded: true,
                value: order,
                items: const [
                  DropdownMenuItem(value: 'name-asc', child: Text('이름 · 오름차순')),
                  DropdownMenuItem(
                    value: 'name-desc',
                    child: Text('이름 · 내림차순'),
                  ),
                  DropdownMenuItem(
                    value: 'created-asc',
                    child: Text('만든 날짜 · 오름차순'),
                  ),
                  DropdownMenuItem(
                    value: 'created-desc',
                    child: Text('만든 날짜 · 내림차순'),
                  ),
                ],
                onChanged: (v) => db.setPreferences({'sort-$module': v}),
              ),
            ),
          ),
        ),
        if (module != '스토리')
          SizedBox(
            height: 48,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => navigate(() {
                      directory = '';
                      clear();
                    }),
                    child: Text('전체'),
                  ),
                  for (final r in path) ...[
                    Icon(Icons.chevron_right, size: 16),
                    TextButton(
                      onPressed: () => open(r),
                      child: Text(r['title'] as String),
                    ),
                  ],
                ],
              ),
            ),
          ),
        if (owner != null)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text('이미지 보기'),
                SizedBox(width: 12),
                StudioDropdown<double>(
                  value: imageTileSize,
                  items: const [
                    DropdownMenuItem(value: 140, child: Text('작게')),
                    DropdownMenuItem(value: 188, child: Text('기본')),
                    DropdownMenuItem(value: 300, child: Text('크게')),
                    DropdownMenuItem(value: 9999, child: Text('패널 너비')),
                  ],
                  onChanged: (v) => setState(() => imageTileSize = v!),
                ),
              ],
            ),
          ),
        if (selectedImages.isNotEmpty)
          Wrap(
            spacing: 8,
            children: [
              SquareButton(
                label: '${selectedImages.length}장 태그',
                onTap: editImageTags,
              ),
              SquareButton(
                label: '선택 해제',
                onTap: () => setState(selectedImages.clear),
              ),
            ],
          ),
        if (importing) LinearProgressIndicator(),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Text(
                    query.isEmpty
                        ? (module == '캐릭터'
                              ? '우클릭하여 폴더나 캐릭터를 만드세요.'
                              : '우클릭하여 새 $module 항목을 만드세요.')
                        : '검색 결과가 없습니다.',
                    style: TextStyle(color: StudioColors.muted),
                  ),
                )
              : LayoutBuilder(
                  builder: (c, b) => GridView.builder(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount:
                          (b.maxWidth / (owner == null ? 188 : imageTileSize))
                              .floor()
                              .clamp(1, 6),
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: items.length,
                    itemBuilder: (c, i) {
                      final r = items[i];
                      if (r['type'] == 'parent') {
                        return cardDropTarget(
                          db.get(directory)?['directory'] as String? ?? '',
                          Card(
                            key: ValueKey('parent-folder'),
                            child: InkWell(
                              onTap: () => navigate(() {
                                directory =
                                    db.get(directory)?['directory']
                                        as String? ??
                                    '';
                                query = '';
                                clear();
                              }),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.drive_folder_upload_outlined,
                                    size: 40,
                                  ),
                                  SizedBox(height: 12),
                                  Text('상위 폴더'),
                                ],
                              ),
                            ),
                          ),
                        );
                      }
                      if (r['type'] == 'asset') {
                        return contextArea(
                          ImageCard(
                            record: r,
                            store: db,
                            cacheWidth: imageTileSize == 9999
                                ? 1600
                                : (imageTileSize * 2).round(),
                            selected: selectedImages.contains(r['id']),
                            onTap: () => setState(
                              () => selectedImages.contains(r['id'])
                                  ? selectedImages.remove(r['id'])
                                  : selectedImages.add(r['id'] as String),
                            ),
                            onDoubleTap: () => zoom(r),
                          ),
                          r,
                        );
                      }
                      Widget tile = FolderCard(
                        key: ValueKey('card-$module-${r['id']}-$directory'),
                        record: r,
                        store: db,
                        count: counts[r['id']] ?? 0,
                        cover: db.get(r['cover'] as String?),
                        selected:
                            selectedCards.contains(r['id']) ||
                            (selectedCards.isEmpty && selected == r['id']),
                        onMenu: (p) => menu(p, r),
                        onTap: () {
                          selectCard(r, items);
                        },
                        onDoubleTap: () =>
                            ['character', 'directory'].contains(r['type'])
                            ? open(r)
                            : select(r),
                      );
                      if (['캐릭터', '노트'].contains(module)) {
                        if (['character', 'directory'].contains(r['type'])) {
                          tile = cardDropTarget(r['id'] as String, tile);
                        }
                        final dragIds = selectedCards.contains(r['id'])
                            ? selectedCards.toList()
                            : [r['id'] as String];
                        final target = tile;
                        tile = Draggable<List<String>>(
                          data: dragIds,
                          maxSimultaneousDrags: saving ? 0 : 1,
                          feedback: Material(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: Text(
                                dragIds.length == 1
                                    ? r['title'] as String
                                    : '${dragIds.length}개 항목 이동',
                              ),
                            ),
                          ),
                          child: target,
                        );
                      }
                      return contextArea(tile, r);
                    },
                  ),
                ),
        ),
      ],
    );
    if (owner != null) {
      content = DropSurface(
        key: ValueKey('gallery-drop'),
        enabled: !importing && selectedImages.isEmpty,
        onFiles: (files) => importPaths(files, owner['id'] as String),
        onAsset: (_) {},
        child: content,
      );
    }
    return contextArea(content);
  }

  String dateLabel(Object? v) {
    final d = DateTime.tryParse(v?.toString() ?? '')?.toLocal();
    return d == null ? '—' : d.toString().substring(0, 16);
  }

  Widget details() {
    final r = current;
    if (r == null || r['deleted'] == true) {
      return SizedBox.expand(key: ValueKey('empty-detail'));
    }
    final isStory = r['type'] == 'note' && r['section'] != 'memo';
    return Padding(
      key: ValueKey('right-pane'),
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: ValueKey('detail-title'),
                  controller: title,
                  onChanged: (_) => markDirty(),
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    hintText: '제목',
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              SizedBox(width: 8),
              SizedBox(
                width: 136,
                child: ValueListenableBuilder<int>(
                  valueListenable: saveFeedback,
                  builder: (_, _, _) => SquareButton(
                    label: dirty ? '변경 저장' : '저장됨',
                    icon: dirty ? Icons.save_outlined : Icons.check,
                    onTap: save,
                  ),
                ),
              ),
              IconButton(
                tooltip: '선택 닫기',
                onPressed: () => navigate(clear),
                icon: Icon(Icons.close, size: 20),
              ),
            ],
          ),
          Wrap(
            spacing: 16,
            children: [
              Text(
                '최초 작성 ${dateLabel(r['created'])}',
                key: ValueKey('created-date'),
                style: TextStyle(fontSize: 12, color: StudioColors.muted),
              ),
              ValueListenableBuilder<int>(
                valueListenable: saveFeedback,
                builder: (_, _, _) => Text(
                  '마지막 수정 ${dateLabel(current?['updated'])}',
                  key: ValueKey('updated-date'),
                  style: TextStyle(fontSize: 12, color: StudioColors.muted),
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Expanded(
            child: RichEditor(
              key: ValueKey('editor-$selected'),
              controller: rich,
              expanded: true,
              lineHeight: (db.preferences['lineHeight'] as num? ?? 1.8)
                  .toDouble(),
              onChanged: markDirty,
            ),
          ),
          SizedBox(height: 8),
          SizedBox(
            height: 56,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: ValueKey('detail-tags'),
                    controller: tags,
                    onChanged: (_) => markDirty(),
                    decoration: InputDecoration(
                      labelText: '태그',
                      hintText: '쉼표로 구분',
                    ),
                  ),
                ),
                if (r['type'] == 'note' && !isStory) ...[
                  SizedBox(width: 8),
                  SizedBox(
                    width: 108,
                    child: StudioDropdown<String>(
                      isExpanded: true,
                      value: r['kind'] as String? ?? '아이디어',
                      items: ['아이디어', '유저노트', '프롬프트', '스토리라인', '장면', '세계관']
                          .map(
                            (v) => DropdownMenuItem(
                              value: v,
                              child: Text(v, overflow: TextOverflow.ellipsis),
                            ),
                          )
                          .toList(),
                      onChanged: (v) =>
                          db.save('note', {'kind': v}, id: selected),
                    ),
                  ),
                ],
                if (isStory)
                  IconButton(
                    tooltip: '등장인물·장면',
                    onPressed: () => storyCast(r),
                    icon: Icon(Icons.people_outline, size: 24),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> storyCast(Record r) async {
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: Text('등장인물·장면'),
          content: SizedBox(
            width: 560,
            height: 400,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Text('스토리 전체와 장면별로 캐릭터 이름을 연결합니다.'),
                  Wrap(
                    spacing: 8,
                    children: db
                        .all('character')
                        .map(
                          (ch) => FilterChip(
                            label: Text(ch['title'] as String),
                            selected: (db.get(r['id'])?['cast'] as List? ?? [])
                                .contains(ch['id']),
                            onSelected: (v) async {
                              await setCast(
                                db.get(r['id'])!,
                                ch['id'] as String,
                                v,
                              );
                              update(() {});
                            },
                          ),
                        )
                        .toList(),
                  ),
                  OutlinedButton(
                    onPressed: () async {
                      await scene(db.get(r['id'])!);
                      update(() {});
                    },
                    child: Text('장면별 등장인물 추가'),
                  ),
                  for (final raw in db.get(r['id'])?['scenes'] as List? ?? [])
                    ListTile(
                      title: Text(raw['title'] as String),
                      subtitle: Text(
                        (raw['cast'] as List)
                            .map((id) => db.get(id)?['title'] ?? '삭제된 캐릭터')
                            .join(', '),
                      ),
                      trailing: IconButton(
                        icon: Icon(Icons.close, size: 20),
                        onPressed: () async {
                          final scenes = List<dynamic>.from(
                            db.get(r['id'])!['scenes'] as List,
                          )..remove(raw);
                          await db.save('note', {
                            'scenes': scenes,
                          }, id: r['id']);
                          update(() {});
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: Text('닫기')),
          ],
        ),
      ),
    );
  }

  Future<void> setCast(Record r, String id, bool v) async {
    if (!await save()) return;
    final cast = List<String>.from(r['cast'] as List? ?? []);
    v ? cast.add(id) : cast.remove(id);
    await db.save('note', {
      'cast': cast.toSet().toList(),
    }, id: r['id'] as String);
  }

  Future<void> scene(Record r) async {
    if (!await save() || !mounted) return;
    final c = TextEditingController();
    final cast = <String>{};
    final result = await showDialog<Record>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text('장면별 등장인물'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: c,
                    onSubmitted: (_) {
                      if (c.text.trim().isNotEmpty) {
                        Navigator.pop(ctx, {
                          'title': c.text.trim(),
                          'cast': cast.toList(),
                        });
                      }
                    },
                    decoration: InputDecoration(
                      labelText: '장면 이름',
                      helperText: '예: 1장 도서관 — 이 장면에 나오는 캐릭터를 연결합니다.',
                    ),
                  ),
                  for (final ch in db.all('character'))
                    CheckboxListTile(
                      title: Text(ch['title'] as String),
                      value: cast.contains(ch['id']),
                      onChanged: (v) => update(
                        () => v == true
                            ? cast.add(ch['id'] as String)
                            : cast.remove(ch['id']),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('취소')),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(ctx, {'title': c.text, 'cast': cast.toList()}),
              child: Text('추가'),
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(Duration(milliseconds: 250));
    c.dispose();
    if (result != null && result['title'].toString().trim().isNotEmpty) {
      await db.save('note', {
        'scenes': [...(r['scenes'] as List? ?? []), result],
      }, id: r['id'] as String);
    }
  }

  Future<void> editImageTags() async {
    final text = await prompt('이미지 태그 · 쉼표로 구분');
    if (text == null) return;
    for (final id in selectedImages) {
      final r = db.get(id)!;
      await db.save('asset', {
        'tags': {
          ...List<String>.from(r['tags'] as List? ?? []),
          ...text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty),
        }.toList(),
      }, id: id);
    }
  }
}

class ImageCard extends StatefulWidget {
  const ImageCard({
    super.key,
    required this.record,
    required this.store,
    required this.selected,
    required this.onTap,
    required this.onDoubleTap,
    this.cacheWidth = 384,
  });
  final int cacheWidth;
  final Record record;
  final WorkspaceStore store;
  final bool selected;
  final VoidCallback onTap, onDoubleTap;
  @override
  State<ImageCard> createState() => _ImageCardState();
}

class _ImageCardState extends State<ImageCard> {
  Timer? click;
  @override
  void dispose() {
    click?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    key: ValueKey('image-${widget.record['id']}'),
    onTap: () {
      if (click?.isActive ?? false) {
        click?.cancel();
        widget.onDoubleTap();
      } else {
        widget.onTap();
        click = Timer(Duration(milliseconds: 350), () {});
      }
    },
    child: Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: StudioColors.raised,
        borderRadius: BorderRadius.circular(8),
      ),
      foregroundDecoration: BoxDecoration(
        border: Border.all(
          color: widget.selected ? StudioColors.accent : StudioColors.line,
          width: widget.selected ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Expanded(
            child: Image.file(
              widget.store.media(widget.record['file'] as String),
              fit: BoxFit.contain,
              width: double.infinity,
              cacheWidth: widget.cacheWidth,
              errorBuilder: (_, _, _) =>
                  Icon(Icons.broken_image_outlined, size: 32),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(8),
            child: Text(
              widget.record['title'] as String,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    ),
  );
}

class DropSurface extends StatelessWidget {
  const DropSurface({
    super.key,
    required this.child,
    required this.onFiles,
    required this.onAsset,
    this.enabled = true,
  });
  final Widget child;
  final ValueChanged<List<String>> onFiles;
  final ValueChanged<Record> onAsset;
  final bool enabled;
  @override
  Widget build(BuildContext context) => DropTarget(
    enable: enabled && (ModalRoute.isCurrentOf(context) ?? true),
    onDragDone: (d) {
      if (enabled && (ModalRoute.isCurrentOf(context) ?? true)) {
        onFiles(d.files.map((f) => f.path).toList());
      }
    },
    child: child,
  );
}
