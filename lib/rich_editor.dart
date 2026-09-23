import 'studio_dropdown.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter_quill/quill_delta.dart' as delta;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as q;
import 'store.dart';
import 'emoji_picker.dart';
import 'studio_widgets.dart';

q.Document plainDocument(String text) {
  final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  return q.Document.fromJson([
    {'insert': normalized.endsWith('\n') ? normalized : '$normalized\n'},
  ]);
}

q.QuillController documentController(Record? record) {
  try {
    return SelectionQuillController(
      document: record?['document'] is List
          ? q.Document.fromJson(record!['document'] as List)
          : plainDocument(record?['body'] as String? ?? ''),
      selection: TextSelection.collapsed(offset: 0),
    );
  } catch (_) {
    return SelectionQuillController(
      document: plainDocument(record?['body'] as String? ?? ''),
      selection: TextSelection.collapsed(offset: 0),
    );
  }
}

class DocumentSearchIntent extends Intent {
  const DocumentSearchIntent();
}

class DocumentCopyIntent extends Intent {
  const DocumentCopyIntent(this.cut);
  final bool cut;
}

class DocumentSelectAllIntent extends Intent {
  const DocumentSelectAllIntent();
}

class DocumentPasteIntent extends Intent {
  const DocumentPasteIntent();
}

class SelectionQuillController extends q.QuillController {
  SelectionQuillController({required super.document, required super.selection});
  bool closed = false;
  @override
  void dispose() {
    closed = true;
    super.dispose();
  }

  @override
  Future<bool> clipboardPaste({void Function()? updateEditor}) async {
    if (clipboardWrite != null) await clipboardWrite;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (closed || readOnly || !selection.isValid || data?.text == null) {
      return false;
    }
    final value = data!.text!.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final start = selection.start, length = selection.end - selection.start;
    document.history.lastRecorded = 0;
    if (value == copiedText && copiedDelta != null) {
      replaceText(
        start,
        length,
        copiedDelta!,
        TextSelection.collapsed(offset: start + value.length),
      );
    } else {
      replaceText(
        start,
        length,
        value,
        TextSelection.collapsed(offset: start + value.length),
      );
    }
    document.history.lastRecorded = 0;
    updateEditor?.call();
    return true;
  }

  static String copiedText = '';
  static delta.Delta? copiedDelta;
  static Future<void>? clipboardWrite;
  @override
  bool clipboardSelection(bool copy) {
    final sel = selection;
    if (!sel.isValid || sel.isCollapsed) return false;
    copiedText = document.getPlainText(sel.start, sel.end - sel.start);
    copiedDelta = document.toDelta().slice(sel.start, sel.end);
    final text = copiedText;
    final pending = Clipboard.setData(ClipboardData(text: text));
    clipboardWrite = pending;
    pending.then(
      (_) {
        if (identical(clipboardWrite, pending)) clipboardWrite = null;
      },
      onError: (Object error, StackTrace stack) {
        if (identical(clipboardWrite, pending)) clipboardWrite = null;
      },
    );
    if (!copy && !readOnly) {
      replaceText(
        sel.start,
        sel.end - sel.start,
        '',
        TextSelection.collapsed(offset: sel.start),
      );
    }
    return true;
  }
}

class RichEditor extends StatefulWidget {
  const RichEditor({
    super.key,
    required this.controller,
    required this.onChanged,
    this.lineHeight = 1.8,
    this.expanded = false,
  });
  final q.QuillController controller;
  final VoidCallback onChanged;
  final double lineHeight;
  final bool expanded;
  @override
  State<RichEditor> createState() => _RichEditorState();
}

class _RichEditorState extends State<RichEditor> {
  StreamSubscription? changes;
  bool applying = false, searching = false;
  final editorFocus = FocusNode(debugLabel: 'document-editor');
  final editorScroll = ScrollController();
  final rawEditorKey = GlobalKey<q.EditorState>();
  final viewportKey = GlobalKey();
  Timer? dragScrollTimer;
  Offset? dragOrigin, dragPosition;
  int? dragPointer;

  void stopDragScroll() {
    dragScrollTimer?.cancel();
    dragScrollTimer = null;
    dragPointer = null;
    dragOrigin = dragPosition = null;
  }

  void trackDrag(PointerMoveEvent event) {
    if (event.pointer != dragPointer) return;
    dragPosition = event.position;
    if ((event.position - dragOrigin!).distance < 6) return;
    dragScrollTimer ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
      final box = viewportKey.currentContext?.findRenderObject() as RenderBox?;
      final point = dragPosition;
      if (!mounted ||
          box == null ||
          point == null ||
          !editorScroll.hasClients) {
        return;
      }
      final rect = box.localToGlobal(Offset.zero) & box.size;
      const edge = 32.0;
      final localY = point.dy - rect.top;
      final speed = localY < edge
          ? -((edge - localY) / edge).clamp(0.0, 1.0) * 240
          : localY > rect.height - edge
          ? ((localY - rect.height + edge) / edge).clamp(0.0, 1.0) * 240
          : 0.0;
      if (speed == 0) return;
      final scroll = editorScroll.position;
      final next = (scroll.pixels + speed * .016).clamp(
        scroll.minScrollExtent,
        scroll.maxScrollExtent,
      );
      if (next == scroll.pixels) return;
      editorScroll.jumpTo(next);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || dragPointer == null) return;
        rawEditorKey.currentState?.renderEditor.extendSelection(
          Offset(
            point.dx.clamp(rect.left + 16, rect.right - 20),
            point.dy.clamp(rect.top + 2, rect.bottom - 2),
          ),
          cause: SelectionChangedCause.drag,
        );
      });
    });
  }

  final search = TextEditingController();
  final searchFocus = FocusNode();
  String searchStatus = '';
  void restoreIme() {
    if (Platform.isWindows && editorFocus.hasFocus) {
      const MethodChannel(
        'storyloom/ime',
      ).invokeMethod<void>('restore').catchError((_) {});
    }
  }

  String? toolbarSignature;
  void selectionChanged() {
    final c = widget.controller;
    final signature = jsonEncode([
      c.getSelectionStyle().toJson(),
      c.selection.isCollapsed,
      c.hasUndo,
      c.hasRedo,
    ]);
    if (mounted && signature != toolbarSignature) {
      toolbarSignature = signature;
      setState(() {});
    }
  }

  bool get hasSelection =>
      widget.controller.selection.isValid &&
      !widget.controller.selection.isCollapsed;
  void apply(String key, dynamic value) {
    if (!widget.controller.selection.isValid) return;
    widget.controller.formatSelection(q.Attribute.fromKeyValue(key, value));
    editorFocus.requestFocus();
  }

  void toggle(String key, dynamic value) {
    final existing = widget.controller
        .getSelectionStyle()
        .attributes[key]
        ?.value;
    apply(key, existing == value ? null : value);
  }

  void findNext({bool first = false}) {
    final text = widget.controller.document.toPlainText().toLowerCase(),
        needle = search.text.toLowerCase();
    if (needle.isEmpty) {
      setState(() => searchStatus = '');
      return;
    }
    var at = text.indexOf(
      needle,
      first ? 0 : widget.controller.selection.end.clamp(0, text.length),
    );
    if (at < 0) at = text.indexOf(needle);
    if (at >= 0) {
      widget.controller.updateSelection(
        TextSelection(baseOffset: at, extentOffset: at + needle.length),
        q.ChangeSource.local,
      );
    }
    setState(
      () =>
          searchStatus = at < 0 ? '결과 없음' : '${text.split(needle).length - 1}개',
    );
    searchFocus.requestFocus();
  }

  void showSearch() {
    setState(() => searching = true);
    searchFocus.requestFocus();
  }

  Future<void> pasteText() async {
    // ignore: experimental_member_use
    await widget.controller.clipboardPaste();
    if (mounted) editorFocus.requestFocus();
  }

  bool active(String key, dynamic value) =>
      widget.controller.getSelectionStyle().attributes[key]?.value == value;
  Widget tool(
    String label,
    IconData icon,
    VoidCallback action, {
    bool selection = false,
    bool selected = false,
    double extent = 44,
  }) => SizedBox(
    width: extent,
    height: 44,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Material(
        type: MaterialType.transparency,
        child: IconButton(
          tooltip: label,
          isSelected: selected,
          onPressed: action,
          style: IconButton.styleFrom(
            minimumSize: Size.zero,
            maximumSize: Size(extent, 44),
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            backgroundColor: selected
                ? StudioColors.accent.withValues(alpha: .25)
                : Colors.transparent,
          ),
          icon: Icon(icon, size: 20),
        ),
      ),
    ),
  );
  Widget toolbar() => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final attributes = widget.controller.getSelectionStyle().attributes;
      final size = double.tryParse('${attributes['size']?.value}') ?? 24;
      final pt = size * 72 / 96;
      final heading = attributes['header']?.value;
      final wide = width >= 620, medium = width >= 420, tiny = width < 280;
      final extent = wide
          ? 44.0
          : medium
          ? 40.0
          : 36.0;
      Widget button(
        String label,
        IconData icon,
        VoidCallback action, {
        bool selected = false,
      }) => tool(label, icon, action, selected: selected, extent: extent);
      final more = <(String, IconData, VoidCallback)>[
        if (!medium) ...[
          ('실행 취소', Icons.undo, () => widget.controller.undo()),
          ('다시 실행', Icons.redo, () => widget.controller.redo()),
        ],
        if (tiny) ...[
          ('기울임', Icons.format_italic, () => toggle('italic', true)),
          ('취소선', Icons.strikethrough_s, () => toggle('strike', true)),
        ],
        if (!wide) ...[
          ('글자 색상', Icons.format_color_text, () => colorMenu('color')),
          ('강조 색상', Icons.format_color_fill, () => colorMenu('background')),
        ],
        if (!wide && width < 500) ...[
          ('왼쪽 정렬', Icons.format_align_left, () => apply('align', null)),
          ('오른쪽 정렬', Icons.format_align_right, () => apply('align', 'right')),
        ],
        if (tiny) ...[
          (
            '글머리 목록',
            Icons.format_list_bulleted,
            () => toggle('list', 'bullet'),
          ),
          ('본문 검색', Icons.search, showSearch),
        ],
        if (!wide) ...[
          ('체크 목록', Icons.checklist, () => toggle('list', 'unchecked')),
          ('인용', Icons.format_quote, () => toggle('blockquote', true)),
          ('코드 블록', Icons.code, () => toggle('code-block', true)),
          ('링크', Icons.link, linkMenu),
          ('이모티콘', Icons.emoji_emotions_outlined, emojis),
        ],
      ];
      return SizedBox(
        key: const ValueKey('text-toolbar'),
        height: 96,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 48,
              child: Row(
                children: [
                  if (medium) ...[
                    button('실행 취소', Icons.undo, () => widget.controller.undo()),
                    button('다시 실행', Icons.redo, () => widget.controller.redo()),
                  ],
                  SizedBox(
                    width: wide
                        ? 100
                        : tiny
                        ? 76
                        : 84,
                    child: StudioDropdown<int>(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      borderRadius: BorderRadius.circular(8),
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontFamilyFallback: const ['NotoEmoji'],
                        fontSize: 14,
                        color: StudioColors.text,
                      ),
                      isExpanded: true,
                      underline: const SizedBox(),
                      hint: Text(
                        '${pt == pt.roundToDouble() ? pt.toInt() : pt.toStringAsFixed(1)} pt',
                        style: const TextStyle(fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                      items: [8, 12, 14, 18, 24, 32, 40]
                          .map(
                            (n) => DropdownMenuItem(
                              value: n,
                              child: Text('$n pt'),
                            ),
                          )
                          .toList(),
                      onChanged: (n) =>
                          apply('size', (n! * 96 / 72).toString()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  button(
                    '굵게',
                    Icons.format_bold,
                    () => toggle('bold', true),
                    selected: active('bold', true),
                  ),
                  if (!tiny)
                    button(
                      '기울임',
                      Icons.format_italic,
                      () => toggle('italic', true),
                      selected: active('italic', true),
                    ),
                  button(
                    '밑줄',
                    Icons.format_underlined,
                    () => toggle('underline', true),
                    selected: active('underline', true),
                  ),
                  if (!tiny)
                    button(
                      '취소선',
                      Icons.strikethrough_s,
                      () => toggle('strike', true),
                      selected: active('strike', true),
                    ),
                  if (wide) ...[
                    button(
                      '글자 색상',
                      Icons.format_color_text,
                      () => colorMenu('color'),
                    ),
                    button(
                      '강조 색상',
                      Icons.format_color_fill,
                      () => colorMenu('background'),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(
              height: 48,
              child: Row(
                children: [
                  SizedBox(
                    width: wide
                        ? 96
                        : tiny
                        ? 64
                        : 80,
                    child: StudioDropdown<int>(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      borderRadius: BorderRadius.circular(8),
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontFamilyFallback: const ['NotoEmoji'],
                        fontSize: 14,
                        color: StudioColors.text,
                      ),
                      isExpanded: true,
                      underline: const SizedBox(),
                      hint: Text(
                        heading == null ? '본문' : '제목 $heading',
                        style: const TextStyle(fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                      items: List.generate(
                        7,
                        (n) => DropdownMenuItem(
                          value: n,
                          child: Text(n == 0 ? '본문' : '제목 $n'),
                        ),
                      ),
                      onChanged: (n) => apply('header', n == 0 ? null : n),
                    ),
                  ),
                  if (wide || width >= 500)
                    button(
                      '왼쪽 정렬',
                      Icons.format_align_left,
                      () => apply('align', null),
                    ),
                  button(
                    '가운데 정렬',
                    Icons.format_align_center,
                    () => apply('align', 'center'),
                    selected: active('align', 'center'),
                  ),
                  if (wide || width >= 500)
                    button(
                      '오른쪽 정렬',
                      Icons.format_align_right,
                      () => apply('align', 'right'),
                      selected: active('align', 'right'),
                    ),
                  button(
                    '번호 목록',
                    Icons.format_list_numbered,
                    () => toggle('list', 'ordered'),
                    selected: active('list', 'ordered'),
                  ),
                  if (!tiny)
                    button(
                      '글머리 목록',
                      Icons.format_list_bulleted,
                      () => toggle('list', 'bullet'),
                      selected: active('list', 'bullet'),
                    ),
                  if (wide) ...[
                    button(
                      '체크 목록',
                      Icons.checklist,
                      () => toggle('list', 'unchecked'),
                    ),
                    button(
                      '인용',
                      Icons.format_quote,
                      () => toggle('blockquote', true),
                    ),
                    button(
                      '코드 블록',
                      Icons.code,
                      () => toggle('code-block', true),
                    ),
                    button('링크', Icons.link, linkMenu),
                    button('이모티콘', Icons.emoji_emotions_outlined, emojis),
                  ],
                  if (!tiny) button('본문 검색', Icons.search, showSearch),
                  if (more.isNotEmpty)
                    SizedBox(
                      width: extent,
                      child: PopupMenuButton<int>(
                        tooltip: '서식 더보기',
                        icon: const Icon(Icons.more_horiz, size: 20),
                        onSelected: (i) => more[i].$3(),
                        itemBuilder: (_) => [
                          for (var i = 0; i < more.length; i++)
                            PopupMenuItem(
                              value: i,
                              child: Row(
                                children: [
                                  Icon(more[i].$2, size: 20),
                                  const SizedBox(width: 12),
                                  Text(more[i].$1),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
  void copyText(bool cut) {
    // ignore: experimental_member_use
    widget.controller.clipboardSelection(!cut);
    editorFocus.requestFocus();
  }

  void selectAll() {
    widget.controller.updateSelection(
      TextSelection(
        baseOffset: 0,
        extentOffset: widget.controller.document.length - 1,
      ),
      q.ChangeSource.local,
    );
    editorFocus.requestFocus();
  }

  bool deleteSelection() {
    final c = widget.controller, sel = widget.controller.selection;
    if (!sel.isValid || sel.isCollapsed) return false;
    final end = sel.end.clamp(0, c.document.length - 1);
    c.replaceText(
      sel.start,
      end - sel.start,
      '',
      TextSelection.collapsed(offset: sel.start),
    );
    return true;
  }

  Future<void> contextMenu(Offset point, TextSelection selection) async {
    if (!mounted) return;
    widget.controller.updateSelection(selection, q.ChangeSource.local);
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(point.dx, point.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: 'cut',
          enabled: !selection.isCollapsed,
          child: const Text('잘라내기  Ctrl+X'),
        ),
        PopupMenuItem(
          value: 'copy',
          enabled: !selection.isCollapsed,
          child: const Text('복사  Ctrl+C'),
        ),
        const PopupMenuItem(value: 'paste', child: Text('붙여넣기  Ctrl+V')),
        const PopupMenuItem(value: 'all', child: Text('전체 선택  Ctrl+A')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'bold', child: Text('굵게  Ctrl+B')),
        const PopupMenuItem(value: 'underline', child: Text('밑줄  Ctrl+U')),
        const PopupMenuItem(value: 'search', child: Text('본문 검색  Ctrl+F')),
      ],
    );
    if (!mounted) return;
    widget.controller.updateSelection(selection, q.ChangeSource.local);
    switch (result) {
      case 'cut':
        copyText(true);
      case 'copy':
        copyText(false);
      case 'paste':
        await pasteText();
      case 'all':
        selectAll();
      case 'bold':
        toggle('bold', true);
      case 'underline':
        toggle('underline', true);
      case 'search':
        showSearch();
      default:
        editorFocus.requestFocus();
    }
  }

  Future<void> colorMenu(String key) async {
    final value = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('색상'),
        content: SizedBox(
          width: 280,
          height: 180,
          child: GridView.count(
            crossAxisCount: 5,
            children: classificationColors
                .map(
                  (c) => InkWell(
                    onTap: () => Navigator.pop(ctx, c.toARGB32()),
                    child: Container(margin: const EdgeInsets.all(4), color: c),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
    if (value != null && mounted) {
      apply(key, '#${(value & 0xffffff).toRadixString(16).padLeft(6, '0')}');
    }
  }

  Future<void> linkMenu() async {
    final field = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('링크 주소'),
        content: TextField(controller: field),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, field.text),
            child: const Text('적용'),
          ),
        ],
      ),
    );
    field.dispose();
    if (value != null && mounted) {
      apply('link', value.trim().isEmpty ? null : value.trim());
    }
  }

  @override
  void initState() {
    super.initState();
    attach();
    widget.controller.addListener(selectionChanged);
    editorFocus.addListener(restoreIme);
  }

  @override
  void didUpdateWidget(RichEditor old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      changes?.cancel();
      old.controller.removeListener(selectionChanged);
      widget.controller.addListener(selectionChanged);
      attach();
    }
  }

  void attach() {
    changes = widget.controller.document.changes.listen((event) {
      if (applying) return;
      widget.onChanged();
      // Conventional inline Markdown shortcut. Never rewrite pasted text or hash headings.
      final inserted = event.change
          .toJson()
          .where((op) => op['insert'] is String)
          .map((op) => op['insert'] as String)
          .join();
      if (inserted != '*' && inserted != '~' && inserted != '`') return;
      scheduleMicrotask(() {
        if (!mounted || applying) return;
        final c = widget.controller, caret = widget.controller.selection;
        if (!caret.isCollapsed || !caret.isValid) return;
        final text = c.document.toPlainText().substring(
          0,
          caret.start.clamp(0, c.document.length - 1),
        );
        for (final rule in [
          (r'\*\*([^*\n]+)\*\*$', 'bold', 2),
          (r'(?<!\*)\*([^*\n]+)\*$', 'italic', 1),
          (r'~~([^~\n]+)~~$', 'strike', 2),
          (r'`([^`\n]+)`$', 'code', 1),
        ]) {
          final match = RegExp(rule.$1).firstMatch(text);
          if (match == null) continue;
          applying = true;
          c.replaceText(
            match.start,
            match[0]!.length,
            match[1]!,
            TextSelection.collapsed(offset: match.start + match[1]!.length),
          );
          c.formatText(
            match.start,
            match[1]!.length,
            q.Attribute.fromKeyValue(rule.$2, true),
          );
          applying = false;
          widget.onChanged();
          break;
        }
      });
    });
  }

  @override
  void dispose() {
    stopDragScroll();
    changes?.cancel();
    widget.controller.removeListener(selectionChanged);
    editorFocus.dispose();
    editorScroll.dispose();
    search.dispose();
    searchFocus.dispose();
    super.dispose();
  }

  Future<void> emojis() async {
    final selection = widget.controller.selection;
    final emoji = await showDialog<String>(
      context: context,
      builder: (_) => const EmojiPicker(),
    );
    if (emoji == null || !mounted) return;
    final c = widget.controller;
    final start = selection.isValid ? selection.start : c.document.length - 1;
    final length = selection.isValid ? selection.end - selection.start : 0;
    c.replaceText(
      start,
      length,
      emoji,
      TextSelection.collapsed(offset: start + emoji.length),
    );
    editorFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    q.DefaultTextBlockStyle heading(int n) => q.DefaultTextBlockStyle(
      TextStyle(
        fontFamily: 'Pretendard',
        fontFamilyFallback: const ['NotoEmoji'],
        fontWeight: FontWeight.w700,
        fontSize: 34.0 - n * 2,
        height: widget.lineHeight,
        color:
            [
                  StudioColors.accent,
                  Color(0xff90cbed),
                  Color(0xffc5a9ed),
                  Color(0xffedbc91),
                  Color(0xffa2d7bc),
                  Color(0xffe9a6bd),
                ]
                .map(
                  (c) => StudioColors.palette.light
                      ? HSLColor.fromColor(c).withLightness(.34).toColor()
                      : c,
                )
                .toList()[n - 1],
      ),
      q.HorizontalSpacing(0, 0),
      q.VerticalSpacing(12, 8),
      q.VerticalSpacing(0, 0),
      null,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: StudioColors.raised,
            borderRadius: BorderRadius.circular(8),
          ),
          child: toolbar(),
        ),
        if (searching)
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('document-search'),
                  controller: search,
                  focusNode: searchFocus,
                  onChanged: (_) => findNext(first: true),
                  onSubmitted: (_) => findNext(),
                  decoration: InputDecoration(
                    hintText: '이 문서에서 검색',
                    suffixText: searchStatus,
                  ),
                ),
              ),
              IconButton(
                tooltip: '다음 결과',
                onPressed: findNext,
                icon: const Icon(Icons.arrow_downward, size: 20),
              ),
              IconButton(
                tooltip: '검색 닫기',
                onPressed: () {
                  setState(() => searching = false);
                  editorFocus.requestFocus();
                },
                icon: const Icon(Icons.close, size: 20),
              ),
            ],
          ),
        SizedBox(height: 8),
        Flexible(
          fit: widget.expanded ? FlexFit.tight : FlexFit.loose,
          child: SizedBox(
            height: widget.expanded ? null : 500,
            child: Container(
              decoration: BoxDecoration(
                color: StudioColors.base,
                border: Border.all(color: StudioColors.line),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Listener(
                key: viewportKey,
                onPointerMove: trackDrag,
                onPointerUp: (_) => stopDragScroll(),
                onPointerCancel: (_) => stopDragScroll(),
                onPointerDown: (event) {
                  final box =
                      viewportKey.currentContext?.findRenderObject()
                          as RenderBox?;
                  if (event.kind == PointerDeviceKind.mouse &&
                      event.buttons == kPrimaryMouseButton &&
                      box != null &&
                      box.globalToLocal(event.position).dx <
                          box.size.width - 20) {
                    dragPointer = event.pointer;
                    dragOrigin = dragPosition = event.position;
                  }
                  if (event.buttons == kSecondaryMouseButton) {
                    final selected = widget.controller.selection;
                    scheduleMicrotask(
                      () => contextMenu(event.position, selected),
                    );
                  }
                },
                child: Scrollbar(
                  controller: editorScroll,
                  thumbVisibility: true,
                  child: CallbackShortcuts(
                    bindings: {
                      const SingleActivator(
                        LogicalKeyboardKey.keyF,
                        control: true,
                      ): showSearch,
                      const SingleActivator(
                        LogicalKeyboardKey.keyV,
                        control: true,
                      ): pasteText,
                    },
                    child: q.QuillEditor.basic(
                      focusNode: editorFocus,
                      scrollController: editorScroll,
                      key: ValueKey('rich-body'),
                      controller: widget.controller,
                      config: q.QuillEditorConfig(
                        editorKey: rawEditorKey,
                        scrollable: true,
                        expands: true,
                        contextMenuBuilder: (_, _) => const SizedBox.shrink(),
                        // Pinned vendored Quill callback; intercept selected deletion before default actions.
                        // ignore: experimental_member_use
                        onKeyPressed: (event, node) {
                          final raw = rawEditorKey.currentState;
                          final composing = raw is TextInputClient
                              ? (raw as TextInputClient)
                                    .currentTextEditingValue
                                    ?.composing
                              : null;
                          if (composing != null &&
                              composing.isValid &&
                              !composing.isCollapsed &&
                              !HardwareKeyboard.instance.isControlPressed &&
                              {
                                LogicalKeyboardKey.backspace,
                                LogicalKeyboardKey.delete,
                                LogicalKeyboardKey.enter,
                                LogicalKeyboardKey.numpadEnter,
                                LogicalKeyboardKey.arrowLeft,
                                LogicalKeyboardKey.arrowRight,
                                LogicalKeyboardKey.arrowUp,
                                LogicalKeyboardKey.arrowDown,
                                LogicalKeyboardKey.home,
                                LogicalKeyboardKey.end,
                              }.contains(event.logicalKey)) {
                            // Let Windows IME finish/update its active composition. Applying
                            // document shortcuts here would edit the same keystroke twice.
                            return KeyEventResult.skipRemainingHandlers;
                          }
                          if (event is KeyDownEvent &&
                              HardwareKeyboard.instance.isControlPressed) {
                            if (event.physicalKey == PhysicalKeyboardKey.keyC) {
                              copyText(false);
                              return KeyEventResult.handled;
                            }
                            if (event.physicalKey == PhysicalKeyboardKey.keyX) {
                              copyText(true);
                              return KeyEventResult.handled;
                            }
                            if (event.physicalKey == PhysicalKeyboardKey.keyV) {
                              pasteText();
                              return KeyEventResult.handled;
                            }
                          }
                          if ((event is KeyDownEvent ||
                                  event is KeyRepeatEvent) &&
                              (event.logicalKey ==
                                      LogicalKeyboardKey.backspace ||
                                  event.logicalKey ==
                                      LogicalKeyboardKey.delete) &&
                              deleteSelection()) {
                            return KeyEventResult.handled;
                          }
                          return null;
                        },
                        customShortcuts: const {
                          SingleActivator(
                            LogicalKeyboardKey.keyC,
                            control: true,
                          ): DocumentCopyIntent(
                            false,
                          ),
                          SingleActivator(
                            LogicalKeyboardKey.keyX,
                            control: true,
                          ): DocumentCopyIntent(
                            true,
                          ),
                          SingleActivator(
                            LogicalKeyboardKey.keyA,
                            control: true,
                          ): DocumentSelectAllIntent(),
                          SingleActivator(
                            LogicalKeyboardKey.keyF,
                            control: true,
                          ): DocumentSearchIntent(),
                          SingleActivator(
                            LogicalKeyboardKey.keyV,
                            control: true,
                          ): DocumentPasteIntent(),
                        },
                        customActions: {
                          DocumentCopyIntent:
                              CallbackAction<DocumentCopyIntent>(
                                onInvoke: (i) {
                                  copyText(i.cut);
                                  return null;
                                },
                              ),
                          DocumentSelectAllIntent:
                              CallbackAction<DocumentSelectAllIntent>(
                                onInvoke: (_) {
                                  selectAll();
                                  return null;
                                },
                              ),
                          DocumentSearchIntent:
                              CallbackAction<DocumentSearchIntent>(
                                onInvoke: (_) {
                                  showSearch();
                                  return null;
                                },
                              ),
                          DocumentPasteIntent:
                              CallbackAction<DocumentPasteIntent>(
                                onInvoke: (_) {
                                  pasteText();
                                  return null;
                                },
                              ),
                        },
                        showCursor: true,
                        onTapOutsideEnabled: false,
                        padding: EdgeInsets.all(16),
                        placeholder: '내용을 작성하세요. 줄 앞에 #을 쓰면 제목으로 표시합니다.',
                        customStyles: q.DefaultStyles(
                          lists: q.DefaultListBlockStyle(
                            TextStyle(
                              fontFamily: 'Pretendard',
                              fontFamilyFallback: const ['NotoEmoji'],
                              fontSize: 24,
                              height: widget.lineHeight,
                              color: StudioColors.text,
                            ),
                            const q.HorizontalSpacing(0, 0),
                            const q.VerticalSpacing(0, 8),
                            const q.VerticalSpacing(0, 0),
                            null,
                            null,
                          ),
                          paragraph: q.DefaultTextBlockStyle(
                            TextStyle(
                              fontFamily: 'Pretendard',
                              fontFamilyFallback: const ['NotoEmoji'],
                              fontSize: 18 * 96 / 72,
                              height: widget.lineHeight,
                              color: StudioColors.text,
                            ),
                            const q.HorizontalSpacing(0, 0),
                            const q.VerticalSpacing(0, 8),
                            const q.VerticalSpacing(0, 0),
                            null,
                          ),
                          h1: heading(1),
                          h2: heading(2),
                          h3: heading(3),
                          h4: heading(4),
                          h5: heading(5),
                          h6: heading(6),
                        ),
                        enableInteractiveSelection: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
