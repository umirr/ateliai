import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'store.dart';

class StudioPalette {
  const StudioPalette(
    this.name,
    this.base,
    this.panel,
    this.accent, {
    this.light = false,
  });
  final String name;
  final Color base, panel, accent;
  final bool light;
}

const palettes = [
  StudioPalette('숲', Color(0xff141615), Color(0xff191c1a), Color(0xffd6eea8)),
  StudioPalette('흑연', Color(0xff17181b), Color(0xff24262b), Color(0xffc5ccd8)),
  StudioPalette(
    '미드나이트',
    Color(0xff111827),
    Color(0xff1b2940),
    Color(0xff94bfff),
  ),
  StudioPalette('라벤더', Color(0xff201c29), Color(0xff2c273b), Color(0xffcfb3fa)),
  StudioPalette('로즈', Color(0xff271d22), Color(0xff372832), Color(0xffefb0c5)),
  StudioPalette('바다', Color(0xff12272b), Color(0xff1c3439), Color(0xff9bdedc)),
  StudioPalette('모카', Color(0xff27221d), Color(0xff373029), Color(0xffe9c29a)),
  StudioPalette('앰버', Color(0xff252219), Color(0xff363025), Color(0xfff0d28e)),
  StudioPalette(
    '종이',
    Color(0xfff1eee7),
    Color(0xfffaf8f2),
    Color(0xff46583a),
    light: true,
  ),
  StudioPalette(
    '눈',
    Color(0xffe9edf2),
    Color(0xfff8faff),
    Color(0xff355c90),
    light: true,
  ),
  StudioPalette(
    '민트',
    Color(0xffe7f0eb),
    Color(0xfff4faf6),
    Color(0xff286951),
    light: true,
  ),
];

class AppearanceSettings extends StatefulWidget {
  const AppearanceSettings({super.key, required this.store});
  final WorkspaceStore store;
  @override
  State<AppearanceSettings> createState() => _AppearanceSettingsState();
}

class _AppearanceSettingsState extends State<AppearanceSettings> {
  String status = '';
  double? opacity, blur;
  Future<void> wallpaper() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      if (result?.files.single.path == null) return;
      final source = File(result!.files.single.path!);
      if (await source.length() > 32 * 1024 * 1024) {
        throw const FormatException('32MB 이하 이미지를 선택하세요.');
      }
      final bytes = await source.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 64);
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      final buckets = <int, List<int>>{};
      if (data != null) {
        final b = data.buffer.asUint8List();
        for (var i = 0; i < b.length; i += 4) {
          if (b[i + 3] < 128) continue;
          final key = (b[i] ~/ 32) * 64 + (b[i + 1] ~/ 32) * 8 + b[i + 2] ~/ 32;
          final v = buckets.putIfAbsent(key, () => [0, 0, 0, 0]);
          v[0] += b[i];
          v[1] += b[i + 1];
          v[2] += b[i + 2];
          v[3]++;
        }
      }
      frame.image.dispose();
      codec.dispose();
      final ranked = buckets.values.toList()
        ..sort((a, b) => b[3].compareTo(a[3]));
      final extracted = ranked
          .take(5)
          .map(
            (v) =>
                Color.fromARGB(255, v[0] ~/ v[3], v[1] ~/ v[3], v[2] ~/ v[3]),
          )
          .toList();
      final dominant =
          extracted
              .where((c) => HSLColor.fromColor(c).saturation > .15)
              .firstOrNull ??
          extracted.firstOrNull ??
          const Color(0xff808080);
      final accent = HSLColor.fromColor(
        dominant,
      ).withSaturation(.45).withLightness(.76).toColor();
      final name =
          'wallpaper-${WorkspaceStore.uuid.v4()}.${result.files.single.extension ?? 'png'}';
      await source.copy(widget.store.media(name).path);
      await widget.store.setPreferences({
        'wallpaper': name,
        'wallpaperAccent': accent.toARGB32(),
        'wallpaperPalette': extracted.map((c) => c.toARGB32()).toList(),
      });
    } catch (e) {
      if (mounted) setState(() => status = '배경을 불러오지 못했습니다: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.store.preferences;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '테마와 배경',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < palettes.length; i++)
              ChoiceChip(
                label: Text(palettes[i].name),
                selected: (p['theme'] ?? 0) == i,
                onSelected: (_) => widget.store.setPreferences({'theme': i}),
              ),
            if (p['wallpaperAccent'] != null)
              ChoiceChip(
                label: const Text('배경 맞춤'),
                selected: p['theme'] == 11,
                onSelected: (_) => widget.store.setPreferences({'theme': 11}),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: wallpaper,
              icon: const Icon(Icons.wallpaper, size: 20),
              label: const Text('배경 이미지 업로드'),
            ),
            TextButton(
              onPressed: () => widget.store.setPreferences({'wallpaper': null}),
              child: const Text('배경 지우기'),
            ),
          ],
        ),
        const Text('배경 불투명도'),
        Slider(
          value: opacity ?? (p['wallpaperOpacity'] as num? ?? .25).toDouble(),
          onChanged: (v) => setState(() => opacity = v),
          onChangeEnd: (v) =>
              widget.store.setPreferences({'wallpaperOpacity': v}),
          min: 0,
          max: 1,
          divisions: 20,
          label: '${((p['wallpaperOpacity'] as num? ?? .25) * 100).round()}%',
        ),
        const Text('배경 블러'),
        Slider(
          value: blur ?? (p['wallpaperBlur'] as num? ?? 8).toDouble(),
          onChanged: (v) => setState(() => blur = v),
          onChangeEnd: (v) => widget.store.setPreferences({'wallpaperBlur': v}),
          min: 0,
          max: 24,
          divisions: 12,
        ),
        if (status.isNotEmpty) Text(status),
      ],
    );
  }
}

class WallpaperLayer extends StatelessWidget {
  const WallpaperLayer({super.key, required this.store});
  final WorkspaceStore store;
  @override
  Widget build(BuildContext context) {
    final p = store.preferences;
    final file = p['wallpaper'] as String?;
    if (file == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: RepaintBoundary(
        child: Opacity(
          opacity: (p['wallpaperOpacity'] as num? ?? .25).toDouble(),
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
              sigmaX: (p['wallpaperBlur'] as num? ?? 8).toDouble(),
              sigmaY: (p['wallpaperBlur'] as num? ?? 8).toDouble(),
            ),
            child: Image.file(
              store.media(file),
              width: double.infinity,
              height: double.infinity,
              fit: BoxFit.cover,
              cacheWidth: 1600,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }
}
