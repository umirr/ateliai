import 'studio_dropdown.dart';
import 'selection_scroll.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'ai.dart';
import 'ai_modes.dart';
import 'store.dart';
import 'studio_widgets.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.root});
  final String root;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final endpoint = TextEditingController(),
      model = TextEditingController(),
      keyInput = TextEditingController();
  String status = '';
  bool loading = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final c = await AiConnection.load();
      if (!mounted) return;
      endpoint.text = c.endpoint;
      model.text = c.model;
      keyInput.text = c.key;
    } catch (_) {
      status = '보안 저장소를 읽을 수 없습니다.';
    }
    if (mounted) {
      setState(() {
        loading = false;
      });
    }
  }

  @override
  void dispose() {
    endpoint.dispose();
    model.dispose();
    keyInput.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('AI 연결', style: TextStyle(fontSize: 24)),
      SizedBox(height: 8),
      Text(
        'Chat Completions 호환 API를 연결하세요. API 키는 이 기기의 보안 저장소에 보관됩니다. 기기마다 별도로 입력합니다.',
      ),
      SizedBox(height: 16),
      TextField(
        controller: endpoint,
        enabled: !loading,
        decoration: InputDecoration(
          labelText: '대화 API 전체 주소',
          hintText: 'https://provider.example/v1/chat/completions',
        ),
      ),
      SizedBox(height: 12),
      TextField(
        controller: model,
        enabled: !loading,
        decoration: InputDecoration(labelText: '모델 ID'),
      ),
      SizedBox(height: 12),
      TextField(
        controller: keyInput,
        enabled: !loading,
        obscureText: true,
        enableSuggestions: false,
        autocorrect: false,
        decoration: InputDecoration(labelText: 'API 키'),
      ),
      SizedBox(height: 12),
      Wrap(
        spacing: 8,
        children: [
          FilledButton(
            onPressed: loading
                ? null
                : () async {
                    try {
                      await AiConnection(
                        endpoint.text,
                        model.text,
                        keyInput.text,
                      ).save();
                      if (mounted) {
                        setState(() {
                          status = '설정을 저장했습니다. 연결 검증은 대화 요청 시 진행합니다.';
                        });
                      }
                    } catch (_) {
                      if (mounted) {
                        setState(() {
                          status = '저장 실패: HTTPS 전체 주소·모델·키와 보안 저장소를 확인하세요.';
                        });
                      }
                    }
                  },
            child: Text('연결 설정 저장'),
          ),
          TextButton(
            onPressed: loading
                ? null
                : () async {
                    try {
                      await AiConnection.clear();
                      if (mounted) {
                        setState(() {
                          keyInput.clear();
                          status = '이 기기의 AI 연결 정보를 삭제했습니다.';
                        });
                      }
                    } catch (_) {
                      if (mounted) {
                        setState(() {
                          status = '보안 저장소 삭제에 실패했습니다.';
                        });
                      }
                    }
                  },
            child: Text('연결 정보 삭제'),
          ),
        ],
      ),
      Text(status),
      Divider(height: 40),
      Text('로컬 데이터 위치'),
      SizedBox(height: 8),
      SelectableText(widget.root),
      SizedBox(height: 8),
      Text('앱 종료 후 이 폴더 전체를 복사하면 원본 이미지와 수정 이력을 백업할 수 있습니다. 앱을 삭제하기 전에 백업하세요.'),
    ],
  );
}

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.store,
    required this.project,
    this.beforeSend,
    this.requestedReference,
    this.referenceRequest = 0,
    this.replyProvider,
  });
  final WorkspaceStore store;
  final String project;
  final Future<bool> Function()? beforeSend;
  final String? requestedReference;
  final int referenceRequest;
  final Stream<String> Function(List<Map<String, dynamic>>)? replyProvider;
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ModeDraft {
  TextEditingValue input = TextEditingValue.empty;
  final refs = <String>{};
  final attachments = <File>[];
  bool includeImages = false;
  double scroll = 0;
  String? latestId;
}

class _ChatPageState extends State<ChatPage> {
  final input = TextEditingController(), refsScroll = ScrollController();
  final messagesScroll = SelectionScrollController();
  final inputFocus = FocusNode();
  final latestUser = GlobalKey();
  ChatMode mode = ChatMode.conversation;
  final drafts = {for (final m in ChatMode.values) m: _ModeDraft()};
  _ModeDraft get draft => drafts[mode]!;
  Set<String> get refs => draft.refs;
  List<File> get attachments => draft.attachments;
  bool get includeImages => draft.includeImages;
  set includeImages(bool v) => draft.includeImages = v;
  String? get latestId => draft.latestId;
  set latestId(String? v) => draft.latestId = v;
  String novelModel = 'V4.5 Full';
  String qualityPreset = 'standard';
  bool qualityTags = true;
  bool sending = false, attaching = false;
  String? error;
  String get referenceScope => (refs.toList()..sort()).join('|');
  Future<void> resetConversation() async {
    if (sending || attaching) return;
    final messages = modeMessages(
      widget.store.all('message', project: widget.project),
      mode,
    );
    for (final message in messages) {
      await widget.store.remove(message);
    }
    if (!mounted) return;
    setState(() {
      drafts[mode] = _ModeDraft();
      input.clear();
      partial = '';
      error = null;
    });
    if (messagesScroll.hasClients) messagesScroll.jumpTo(0);
  }

  void changeMode(ChatMode next) {
    if (sending || attaching || mode == next) return;
    draft.input = input.value.copyWith(composing: TextRange.empty);
    if (messagesScroll.hasClients) draft.scroll = messagesScroll.offset;
    setState(() {
      mode = next;
      input.value = draft.input;
      partial = '';
      error = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && messagesScroll.hasClients) {
        messagesScroll.jumpTo(
          draft.scroll.clamp(0, messagesScroll.position.maxScrollExtent),
        );
      }
    });
  }

  String partial = '';
  @override
  void initState() {
    super.initState();
    if (widget.requestedReference != null) refs.add(widget.requestedReference!);
  }

  @override
  void didUpdateWidget(covariant ChatPage old) {
    super.didUpdateWidget(old);
    if (old.referenceRequest != widget.referenceRequest &&
        widget.requestedReference != null) {
      refs.add(widget.requestedReference!);
    }
  }

  @override
  void dispose() {
    input.dispose();
    inputFocus.dispose();
    messagesScroll.dispose();
    refsScroll.dispose();
    super.dispose();
  }

  List<Record> get selectedRefs => refs
      .map(widget.store.get)
      .whereType<Record>()
      .where((r) => r['deleted'] != true)
      .toList();
  String get referenceText =>
      selectedRefs.map((r) => '${r['title']}\n${r['body'] ?? ''}').join('\n\n');
  List<File> get coverFiles => includeImages
      ? selectedRefs
            .where((r) => r['type'] == 'character')
            .map((r) => widget.store.get(r['cover'] as String?))
            .whereType<Record>()
            .where((r) => r['deleted'] != true)
            .map((r) => widget.store.media(r['file'] as String))
            .toList()
      : [];
  Future<void> send() async {
    if (sending ||
        attaching ||
        (input.text.trim().isEmpty && attachments.isEmpty)) {
      return;
    }
    // Enter during IME composition must commit the syllable, not send it.
    if (input.value.composing.isValid && !input.value.composing.isCollapsed) {
      return;
    }
    final prompt = input.text.trim();
    final requestMode = mode;
    setState(() {
      sending = true;
      error = null;
      partial = '';
    });
    Record? user;
    try {
      if (widget.beforeSend != null && !await widget.beforeSend!()) {
        throw const FormatException('작성 중인 내용을 저장한 뒤 다시 보내세요.');
      }
      final files = {
        for (final f in [...attachments, ...coverFiles]) f.path: f,
      }.values.toList();
      if (files.length > 4) {
        throw const FormatException('대표 이미지와 첨부 이미지를 합해 최대 4장입니다.');
      }
      final history =
          modeMessages(
                widget.store.all('message', project: widget.project),
                requestMode,
              )
              .where(
                (r) =>
                    r['failed'] != true &&
                    r['referenceScope'] == referenceScope &&
                    (requestMode != ChatMode.character ||
                        r['novelModel'] == novelModel),
              )
              .toList();
      final payload = <Map<String, dynamic>>[
        {
          'role': 'system',
          'content': systemPromptFor(
            requestMode,
            references: referenceText,
            novelModel: novelModel,
            qualityTags: qualityTags,
            qualityPreset: qualityPreset,
          ),
        },
        ...history
            .skip(history.length > 20 ? history.length - 20 : 0)
            .map((r) => {'role': r['role'], 'content': r['body']}),
        {
          'role': 'user',
          'content': files.isEmpty ? prompt : await imageMessage(prompt, files),
        },
      ];
      user = await widget.store.save('message', {
        'project': widget.project,
        'role': 'user',
        'chatMode': requestMode.id,
        if (requestMode == ChatMode.character) 'novelModel': novelModel,
        'body': prompt,
        'references': refs.toList(),
        'referenceScope': referenceScope,
        'imageCount': files.length,
      });
      if (!mounted) return;
      setState(() {
        latestId = user!['id'] as String;
        input.clear();
        attachments.clear();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final c = latestUser.currentContext;
        if (c != null) {
          Scrollable.ensureVisible(
            c,
            alignment: 0,
            duration: const Duration(milliseconds: 180),
          );
        }
      });
      final stream = widget.replyProvider != null
          ? widget.replyProvider!(payload)
          : (await AiConnection.load()).streamReply(payload);
      await for (final chunk in stream) {
        partial += chunk;
        if (mounted) setState(() {});
      }
      await widget.store.save('message', {
        'project': widget.project,
        'role': 'assistant',
        'referenceScope': referenceScope,
        'chatMode': requestMode.id,
        if (requestMode == ChatMode.character) 'novelModel': novelModel,
        'body': partial,
      });
      partial = '';
    } catch (e) {
      if (user != null) {
        await widget.store.save('message', {
          'failed': true,
        }, id: user['id'] as String);
      }
      if (partial.isNotEmpty) {
        await widget.store.save('message', {
          'project': widget.project,
          'role': 'assistant',
          'chatMode': requestMode.id,
          'body': partial,
          'failed': true,
        });
        partial = '';
      }
      if (mounted) {
        setState(
          () => error = e is FormatException
              ? e.message
              : e is HttpException
              ? e.message
              : '연결 또는 대화 저장에 실패했습니다. 설정과 네트워크를 확인하세요.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => sending = false);
        inputFocus.requestFocus();
      }
    }
  }

  Future<void> attachFiles(List<String> paths) async {
    if (sending || attaching) return;
    setState(() {
      attaching = true;
      error = null;
    });
    try {
      for (final path in paths) {
        if (attachments.any((f) => f.path == path)) continue;
        if (attachments.length >= 4) {
          throw const FormatException('이미지는 최대 4장입니다.');
        }
        final file = File(path);
        await imageMessage('', [file]);
        if (!mounted) return;
        setState(() => attachments.add(file));
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException ? e.message : '이미지 파일을 읽지 못했습니다.',
        );
      }
    } finally {
      if (mounted) setState(() => attaching = false);
    }
  }

  Widget message(Record r) {
    final ai = r['role'] == 'assistant';
    final responseMode = recordMode(r);
    final blocks = generatedBlocks(r['body'] as String? ?? '');
    final warnings = ai
        ? generationWarnings(responseMode, r['body'] as String? ?? '')
        : <String>[];
    return Card(
      key: r['id'] == latestId ? latestUser : ValueKey(r['id']),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    ai ? 'AI' : '나',
                    style: TextStyle(color: StudioColors.accent),
                  ),
                ),
                IconButton(
                  tooltip: '전체 텍스트 복사',
                  onPressed: () => Clipboard.setData(
                    ClipboardData(text: r['body'] as String? ?? ''),
                  ),
                  icon: const Icon(Icons.copy_outlined, size: 20),
                ),
              ],
            ),
            Text(
              r['body'] as String? ?? '',
              style: const TextStyle(fontSize: 17, height: 1.6),
            ),
            if (ai && responseMode != ChatMode.conversation)
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final entry in blocks.entries.where(
                    (e) => [
                      '기본 프롬프트',
                      '캐릭터 프롬프트',
                      '제외 프롬프트',
                      '완성 지침',
                    ].contains(e.key),
                  ))
                    SizedBox(
                      width: 160,
                      height: 44,
                      child: TextButton(
                        style: TextButton.styleFrom(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () =>
                            Clipboard.setData(ClipboardData(text: entry.value)),
                        child: Text(
                          '${entry.key} 복사',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 14, height: 1.2),
                        ),
                      ),
                    ),
                  if (responseMode == ChatMode.character &&
                      blocks['기본 프롬프트'] != null &&
                      blocks['캐릭터 프롬프트'] != null)
                    TextButton(
                      onPressed: () => Clipboard.setData(
                        ClipboardData(
                          text: '${blocks['기본 프롬프트']}, ${blocks['캐릭터 프롬프트']}',
                        ),
                      ),
                      child: const Text(
                        '합쳐서 복사',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                ],
              ),
            for (final warning in warnings)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  warning,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 13,
                  ),
                ),
              ),
            if ((r['imageCount'] as int? ?? 0) > 0)
              Text('첨부 이미지 ${r['imageCount']}장'),
            if (r['failed'] == true) const Text('응답 중단 · 입력과 받은 내용은 보관됨'),
            if (ai)
              TextButton.icon(
                onPressed: () async {
                  await widget.store.save('note', {
                    'project': widget.project,
                    'title':
                        '${responseMode == ChatMode.conversation ? 'AI 아이디어' : responseMode.label} ${DateTime.now().toString().substring(0, 16)}',
                    'body': r['body'],
                    'kind': responseMode == ChatMode.conversation
                        ? '아이디어'
                        : '프롬프트',
                    'promptPurpose': responseMode.id,
                    'section': 'memo',
                  });
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('노트에 저장했습니다.')),
                    );
                  }
                },
                icon: const Icon(Icons.bookmark_add_outlined, size: 20),
                label: Text(
                  responseMode == ChatMode.conversation
                      ? '노트로 저장'
                      : '프롬프트 노트로 저장',
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = modeMessages(
      widget.store.all('message', project: widget.project),
      mode,
    );
    final references =
        [...widget.store.all('character'), ...widget.store.all('note')]..sort(
          (a, b) => (b['updated'] ?? b['created']).toString().compareTo(
            (a['updated'] ?? a['created']).toString(),
          ),
        );
    return DropTarget(
      enable:
          !sending && !attaching && (ModalRoute.isCurrentOf(context) ?? true),
      onDragDone: (d) => attachFiles(d.files.map((f) => f.path).toList()),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 44,
            child: Row(
              children: [
                for (final item in ChatMode.values)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: TextButton(
                        key: ValueKey('chat-mode-${item.id}'),
                        onPressed: sending || attaching
                            ? null
                            : () => changeMode(item),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          backgroundColor: mode == item
                              ? StudioColors.hover
                              : Colors.transparent,
                          foregroundColor: StudioColors.text,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color: mode == item
                                  ? StudioColors.accent
                                  : StudioColors.line,
                            ),
                          ),
                        ),
                        child: Text(
                          item.label,
                          maxLines: 1,
                          style: const TextStyle(fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (mode == ChatMode.character)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(
                    child: StudioDropdown<String>(
                      isExpanded: true,
                      value: novelModel,
                      items: const [
                        DropdownMenuItem(
                          value: 'V4.5 Full',
                          child: Text('V4.5 Full'),
                        ),
                        DropdownMenuItem(
                          value: 'V5 Full',
                          child: Text('V5 Full'),
                        ),
                      ],
                      onChanged: sending
                          ? null
                          : (v) => setState(() {
                              novelModel = v!;
                              if (!novelModel.startsWith('V5')) {
                                qualityPreset = 'standard';
                              }
                            }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StudioDropdown<String>(
                      isExpanded: true,
                      value: qualityTags ? qualityPreset : 'off',
                      items: [
                        const DropdownMenuItem(
                          value: 'off',
                          child: Text('품질: 끄기'),
                        ),
                        const DropdownMenuItem(
                          value: 'standard',
                          child: Text('품질: 표준'),
                        ),
                        if (novelModel.startsWith('V5'))
                          const DropdownMenuItem(
                            value: 'light',
                            child: Text('품질: Light'),
                          ),
                      ],
                      onChanged: sending
                          ? null
                          : (v) => setState(() {
                              qualityTags = v != 'off';
                              if (qualityTags) qualityPreset = v!;
                            }),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              mode.hint,
              style: TextStyle(fontSize: 12, color: StudioColors.muted),
            ),
          ),
          Row(
            children: [
              const Expanded(
                child: Text('선택한 글만 참고', style: TextStyle(fontSize: 14)),
              ),
              IconButton(
                tooltip: '현재 모드 대화 초기화',
                onPressed: sending || attaching ? null : resetConversation,
                icon: const Icon(Icons.restart_alt, size: 24),
              ),
            ],
          ),
          if (references.isNotEmpty)
            SizedBox(
              height: 60,
              child: Scrollbar(
                controller: refsScroll,
                thumbVisibility: true,
                child: ListView(
                  controller: refsScroll,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(bottom: 12),
                  children: references
                      .map(
                        (r) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(
                              r['title'] as String,
                              style: TextStyle(
                                color: StudioColors.text,
                                fontSize: 15,
                              ),
                            ),
                            backgroundColor: StudioColors.raised,
                            selectedColor: StudioColors.hover,
                            selected: refs.contains(r['id']),
                            onSelected: sending
                                ? null
                                : (v) => setState(() {
                                    v
                                        ? refs.add(r['id'] as String)
                                        : refs.remove(r['id']);
                                  }),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(
              '캐릭터 대표 이미지 포함 (${coverFiles.length}장)',
              style: const TextStyle(fontSize: 14),
            ),
            subtitle: const Text(
              '이미지 입력을 지원하는 모델 필요',
              style: TextStyle(fontSize: 12),
            ),
            value: includeImages,
            onChanged: sending
                ? null
                : (v) => setState(() => includeImages = v ?? false),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (c, box) => Listener(
                onPointerDown: (_) => messagesScroll.selecting = true,
                onPointerUp: (_) => messagesScroll.selecting = false,
                onPointerCancel: (_) => messagesScroll.selecting = false,
                child: SelectionArea(
                  child: Scrollbar(
                    controller: messagesScroll,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: messagesScroll,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (entries.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                '설정에서 AI API를 연결한 뒤 입력하세요. 결과는 선택한 모드에만 저장됩니다.',
                              ),
                            ),
                          ...entries.map(message),
                          if (sending)
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  partial.isEmpty ? '답변을 기다리는 중…' : partial,
                                ),
                              ),
                            ),
                          if (latestId != null)
                            SizedBox(height: box.maxHeight * .85),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (attaching) const LinearProgressIndicator(),
          if (attachments.isNotEmpty)
            SizedBox(
              height: 72,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: attachments
                    .map(
                      (f) => Stack(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Image.file(
                              f,
                              width: 64,
                              height: 64,
                              cacheWidth: 128,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            right: 0,
                            top: 0,
                            child: IconButton(
                              tooltip: '첨부 제거',
                              onPressed: sending
                                  ? null
                                  : () => setState(() => attachments.remove(f)),
                              icon: const Icon(Icons.close, size: 20),
                            ),
                          ),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ),
          TextButton.icon(
            onPressed: sending || attaching
                ? null
                : () async {
                    try {
                      final files = await FilePicker.platform.pickFiles(
                        type: FileType.image,
                        allowMultiple: true,
                      );
                      if (files != null) {
                        await attachFiles(
                          files.files
                              .where((f) => f.path != null)
                              .map((f) => f.path!)
                              .toList(),
                        );
                      }
                    } catch (_) {
                      if (mounted) {
                        setState(
                          () => error = '파일 선택기를 열지 못했습니다. 파일을 직접 드롭해 주세요.',
                        );
                      }
                    }
                  },
            icon: const Icon(Icons.add_photo_alternate_outlined, size: 20),
            label: Text(
              attaching ? '이미지 확인 중…' : '이미지 첨부 · ${attachments.length}/4',
            ),
          ),
          if (error != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 80),
              child: SingleChildScrollView(
                child: Text(
                  error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          CallbackShortcuts(
            bindings: {const SingleActivator(LogicalKeyboardKey.enter): send},
            child: TextField(
              key: const ValueKey('chat-input'),
              focusNode: inputFocus,
              controller: input,
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: switch (mode) {
                  ChatMode.conversation => '메시지 · Shift+Enter 줄바꿈',
                  ChatMode.character => '성별·연령대·장르·직업 등 기본 정보',
                },
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                suffixIconConstraints: const BoxConstraints(
                  minWidth: 56,
                  minHeight: 56,
                ),
                suffixIcon: Padding(
                  padding: const EdgeInsets.all(8),
                  child: IconButton.filled(
                    style: IconButton.styleFrom(
                      fixedSize: const Size(40, 40),
                      backgroundColor: StudioColors.accent,
                      foregroundColor:
                          ThemeData.estimateBrightnessForColor(
                                StudioColors.accent,
                              ) ==
                              Brightness.light
                          ? Colors.black
                          : Colors.white,
                      minimumSize: Size.zero,
                      padding: EdgeInsets.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    tooltip: '메시지 전송',
                    onPressed: sending || attaching ? null : send,
                    icon: sending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.arrow_upward, size: 24),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<List<Map<String, dynamic>>> imageMessage(
  String text,
  List<File> files,
) async {
  final result = <Map<String, dynamic>>[
    {'type': 'text', 'text': text.isEmpty ? '이 이미지를 참고해 주세요.' : text},
  ];
  for (final file in files) {
    if (await file.length() > 5 * 1024 * 1024) {
      throw const FormatException('첨부 이미지는 장당 5MB 이하만 가능합니다.');
    }
    final bytes = await file.readAsBytes();
    String? mime;
    if (bytes.length >= 12) {
      if (bytes[0] == 137 &&
          bytes[1] == 80 &&
          bytes[2] == 78 &&
          bytes[3] == 71) {
        mime = 'image/png';
      } else if (bytes[0] == 255 && bytes[1] == 216 && bytes[2] == 255) {
        mime = 'image/jpeg';
      } else if (ascii.decode(bytes.sublist(0, 4), allowInvalid: true) ==
              'RIFF' &&
          ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP') {
        mime = 'image/webp';
      } else if (ascii.decode(bytes.sublist(0, 3), allowInvalid: true) ==
          'GIF') {
        mime = 'image/gif';
      }
    }
    if (mime == null) {
      throw const FormatException('PNG/JPEG/WEBP/GIF 이미지 파일을 선택하세요.');
    }
    result.add({
      'type': 'image_url',
      'image_url': {'url': 'data:$mime;base64,${base64Encode(bytes)}'},
    });
  }
  return result;
}
