import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'store.dart';
import 'appearance.dart';

abstract final class StudioColors {
  static StudioPalette palette = palettes.first;
  static bool wallpaper = false;
  static Color get base => palette.base;
  static Color get panel =>
      palette.panel.withValues(alpha: wallpaper ? .86 : 1);
  static Color get raised => Color.alphaBlend(
    (palette.light ? Colors.black : Colors.white).withValues(alpha: .045),
    palette.panel,
  );
  static Color get line =>
      palette.light ? Color(0xffb8bdc2) : Color(0xff454b4b);
  static Color get accent => palette.accent;
  static Color get muted =>
      palette.light ? Color(0xff505961) : Color(0xffaab4ae);
  static Color get text =>
      palette.light ? Color(0xff20282b) : Color(0xffedf2ed);
  static Color get hover =>
      Color.alphaBlend(accent.withValues(alpha: .12), palette.panel);
  static void configure(Record p) {
    final index = p['theme'] as int? ?? 0;
    palette = index == 11 && p['wallpaperAccent'] is int
        ? StudioPalette(
            '배경 맞춤',
            Color(0xff17191b),
            Color(0xff22272a),
            Color(p['wallpaperAccent'] as int),
          )
        : palettes[index.clamp(0, palettes.length - 1)];
    wallpaper = p['wallpaper'] != null;
  }
}

class StudioPanel extends StatelessWidget {
  const StudioPanel({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Material(
    color: StudioColors.panel,
    shape: RoundedRectangleBorder(
      side: BorderSide(color: StudioColors.line),
      borderRadius: BorderRadius.circular(12),
    ),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}

class StudioBar extends StatelessWidget {
  const StudioBar({
    super.key,
    required this.icon,
    required this.title,
    this.trailing,
    this.leading,
  });
  final IconData icon;
  final String title;
  final Widget? trailing, leading;
  @override
  Widget build(BuildContext context) => Container(
    height: 60,
    padding: EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: StudioColors.line)),
    ),
    child: Row(
      children: [
        leading ?? Icon(icon, size: 16, color: StudioColors.muted),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
        ),
        if (trailing != null) ...[SizedBox(width: 8), trailing!],
      ],
    ),
  );
}

final classificationColors =
    <Color>[
          Color(0xffe8b4b8),
          Color(0xffedc2a1),
          Color(0xffeddda6),
          Color(0xffc4dca8),
          Color(0xffa9d7c0),
          Color(0xffa7d8d7),
          Color(0xffadcce6),
          Color(0xffb4bce6),
          Color(0xffcdb9e5),
          Color(0xffe2bad8),
          Color(0xffd4b6ad),
          Color(0xffd3cab1),
          Color(0xffbbcabb),
          Color(0xffb9c7d0),
          Color(0xffcec2d3),
        ]
        .map(
          (c) => HSLColor.fromColor(
            c,
          ).withSaturation(.72).withLightness(.64).toColor(),
        )
        .toList();

class SlidingTabs extends StatelessWidget {
  const SlidingTabs({
    super.key,
    required this.selected,
    required this.onSelected,
  });
  final String selected;
  final ValueChanged<String> onSelected;
  static final labels = ['캐릭터', '스토리', '노트', '설정'];
  static final icons = [
    Icons.people_outline,
    Icons.account_tree_outlined,
    Icons.edit_note,
    Icons.tune,
  ];
  @override
  Widget build(BuildContext context) => Container(
    width: 400,
    height: 56,
    decoration: BoxDecoration(
      color: StudioColors.panel,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: StudioColors.line),
    ),
    child: Stack(
      children: [
        AnimatedPositioned(
          key: ValueKey('tab-indicator'),
          duration: Duration(milliseconds: 210),
          curve: Curves.easeOutCubic,
          left: 4 + labels.indexOf(selected) * 97.5,
          top: 4,
          bottom: 4,
          width: 97.5,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: StudioColors.hover,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: StudioColors.line),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.all(4),
          child: Row(
            children: [
              for (var i = 0; i < labels.length; i++)
                Expanded(
                  child: Semantics(
                    selected: labels[i] == selected,
                    button: true,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        focusColor: Colors.transparent,
                        hoverColor: Colors.transparent,
                        borderRadius: BorderRadius.circular(999),
                        onTap: () => onSelected(labels[i]),
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                icons[i],
                                size: 16,
                                color: labels[i] == selected
                                    ? StudioColors.accent
                                    : StudioColors.muted,
                              ),
                              SizedBox(width: 6),
                              Text(
                                labels[i],
                                style: TextStyle(
                                  fontSize: 16,
                                  color: labels[i] == selected
                                      ? StudioColors.text
                                      : StudioColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class SquareButton extends StatelessWidget {
  const SquareButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.selected = false,
  });
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool selected;
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onTap,
    style: TextButton.styleFrom(
      minimumSize: Size(84, 48),
      padding: EdgeInsets.symmetric(horizontal: 12),
      backgroundColor: selected ? StudioColors.accent : StudioColors.raised,
      foregroundColor: selected ? StudioColors.base : StudioColors.text,
      disabledForegroundColor: StudioColors.muted,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(7),
        side: BorderSide(
          color: selected ? StudioColors.accent : StudioColors.line,
        ),
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 16), SizedBox(width: 7)],
        Text(
          label,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
      ],
    ),
  );
}

PopupMenuItem<String> studioMenuItem(
  String value,
  String label,
  IconData icon, {
  bool destructive = false,
}) => PopupMenuItem(
  value: value,
  height: 56,
  child: Row(
    children: [
      Icon(
        icon,
        size: 16,
        color: destructive ? Color(0xffdfa59b) : StudioColors.muted,
      ),
      SizedBox(width: 12),
      Text(
        label,
        style: TextStyle(
          fontSize: 17,
          color: destructive ? Color(0xffdfa59b) : StudioColors.text,
        ),
      ),
    ],
  ),
);

class FolderCard extends StatefulWidget {
  const FolderCard({
    super.key,
    required this.record,
    required this.store,
    required this.count,
    required this.onTap,
    this.onDoubleTap,
    this.onMenu,
    this.cover,
    this.selected = false,
  });
  final Record record;
  final WorkspaceStore store;
  final int count;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;
  final ValueChanged<Offset>? onMenu;
  final Record? cover;
  final bool selected;
  @override
  State<FolderCard> createState() => _FolderCardState();
}

class _FolderCardState extends State<FolderCard> {
  Timer? clickWindow;
  bool hovered = false;
  @override
  void dispose() {
    clickWindow?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(FolderCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.record['id'] != widget.record['id']) {
      clickWindow?.cancel();
      hovered = false;
    }
  }

  void handleClick() {
    final modified =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isShiftPressed;
    final doubleClick = !modified && (clickWindow?.isActive ?? false);
    clickWindow?.cancel();
    if (!doubleClick) {
      clickWindow = Timer(Duration(milliseconds: 350), () {});
    }
    // Single click is dispatched immediately; no double-tap recognizer delays it.
    if (doubleClick && widget.onDoubleTap != null) {
      widget.onDoubleTap!();
    } else {
      widget.onTap();
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.record;
    final categoryColor = r['color'] is int
        ? HSLColor.fromColor(
            Color(r['color'] as int),
          ).withSaturation(.72).withLightness(.64).toColor()
        : null;
    final folder = r['type'] == 'directory';
    final note = r['type'] == 'note';
    return MouseRegion(
      onEnter: (_) => setState(() {
        hovered = true;
      }),
      onExit: (_) => setState(() {
        hovered = false;
      }),
      child: Material(
        key: ValueKey('folder-card-${r['id']}'),
        color: hovered
            ? Color.alphaBlend(
                (categoryColor ?? StudioColors.accent).withValues(alpha: .32),
                StudioColors.raised,
              )
            : categoryColor == null
            ? StudioColors.raised
            : Color.alphaBlend(
                categoryColor.withValues(alpha: .38),
                StudioColors.raised,
              ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: widget.selected
                ? StudioColors.accent
                : hovered
                ? Color(0xff525d4d)
                : categoryColor?.withValues(alpha: .55) ?? StudioColors.line,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Container(
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: widget.selected ? StudioColors.accent : Colors.transparent,
              width: 2,
            ),
          ),
          child: InkWell(
            onTap: handleClick,
            child: Padding(
              padding: EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        folder
                            ? Icons.folder_outlined
                            : note
                            ? Icons.notes
                            : Icons.person_outline,
                        size: 16,
                        color: StudioColors.muted,
                      ),
                      Spacer(),
                      if (categoryColor != null) ...[
                        Container(
                          key: ValueKey("color-${r['id']}"),
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: categoryColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        SizedBox(width: 6),
                      ],
                      if (widget.selected)
                        Icon(
                          Icons.check_circle,
                          size: 16,
                          color: StudioColors.accent,
                        )
                      else
                        Builder(
                          builder: (c) => IconButton(
                            tooltip: '항목 메뉴',
                            style: IconButton.styleFrom(
                              minimumSize: Size(24, 24),
                              maximumSize: Size(24, 24),
                              padding: EdgeInsets.zero,
                            ),
                            onPressed: widget.onMenu == null
                                ? null
                                : () {
                                    final box =
                                        c.findRenderObject()! as RenderBox;
                                    widget.onMenu!(
                                      box.localToGlobal(
                                        Offset(0, box.size.height),
                                      ),
                                    );
                                  },
                            icon: Icon(
                              Icons.more_horiz,
                              size: 16,
                              color: StudioColors.muted,
                            ),
                          ),
                        ),
                    ],
                  ),
                  Expanded(
                    child: Center(
                      child:
                          widget.cover != null &&
                              widget.cover!['deleted'] != true
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(
                                widget.store.media(
                                  widget.cover!['file'] as String,
                                ),
                                cacheWidth: 384,
                                fit: BoxFit.contain,
                                errorBuilder: (_, _, _) =>
                                    Icon(Icons.broken_image_outlined, size: 32),
                              ),
                            )
                          : Container(
                              width: 64,
                              height: 58,
                              decoration: BoxDecoration(
                                color: StudioColors.base.withValues(alpha: .55),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                folder
                                    ? Icons.folder_open_rounded
                                    : note
                                    ? Icons.edit_note_rounded
                                    : Icons.person_outline_rounded,
                                size: 32,
                                color: widget.selected
                                    ? StudioColors.accent
                                    : Color(0xffa4b296),
                              ),
                            ),
                    ),
                  ),
                  Text(
                    r['title'] as String,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 5),
                  Text(
                    folder
                        ? '${widget.count} ${r['scope'] == 'memo' ? '노트' : '캐릭터'}'
                        : note
                        ? r['kind'] as String? ?? '노트'
                        : '이미지 ${widget.count}장',
                    style: TextStyle(fontSize: 14, color: StudioColors.muted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
