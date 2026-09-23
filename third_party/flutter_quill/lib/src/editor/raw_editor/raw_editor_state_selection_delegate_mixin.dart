import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../delta/delta_diff.dart';
import '../../document/document.dart';
import 'raw_editor.dart';

mixin RawEditorStateSelectionDelegateMixin on EditorState
    implements TextSelectionDelegate {
  @override
  TextEditingValue get textEditingValue {
    return widget.controller.plainTextEditingValue;
  }

  set textEditingValue(TextEditingValue value) {
    final cursorPosition = value.selection.extentOffset;
    final oldText = widget.controller.document.toPlainText();
    final newText = value.text;
    final diff = getDiff(oldText, newText, cursorPosition);
    if (diff.deleted == '' && diff.inserted == '') {
      // Only changing selection range
      widget.controller.updateSelection(value.selection, ChangeSource.local);
      return;
    }

    widget.controller.replaceTextWithEmbeds(
      diff.start,
      diff.deleted.length,
      diff.inserted,
      value.selection,
    );
  }

  @override
  void bringIntoView(TextPosition position) {
    if (!mounted || !position.offset.isFinite) return;
    try {
      final rect = renderEditor.getLocalRectForCaret(position);
      if (widget.config.scrollable && scrollController.hasClients) {
        final scroll = scrollController.position;
        // Caret coordinates are content-local, not viewport-local.
        final top = rect.top - 12, bottom = rect.bottom + 12;
        var target = scroll.pixels;
        if (top < target) {
          target = top;
        } else if (bottom > target + scroll.viewportDimension) {
          target = bottom - scroll.viewportDimension;
        }
        target = target.clamp(scroll.minScrollExtent, scroll.maxScrollExtent);
        if ((target - scroll.pixels).abs() > .5)
          scrollController.jumpTo(target);
      } else {
        renderEditor.showOnScreen(rect: rect);
      }
    } catch (_) {}
  }

  @override
  void hideToolbar([bool hideHandles = true]) {
    // If the toolbar is currently visible.
    if (selectionOverlay?.toolbar != null) {
      hideHandles ? selectionOverlay?.hide() : selectionOverlay?.hideToolbar();
    }
  }

  @override
  void userUpdateTextEditingValue(
    TextEditingValue value,
    SelectionChangedCause cause,
  ) {
    textEditingValue = value;
  }

  @override
  bool get cutEnabled =>
      widget.config.contextMenuBuilder != null && !widget.config.readOnly;

  @override
  bool get copyEnabled => widget.config.contextMenuBuilder != null;

  @override
  bool get pasteEnabled =>
      widget.config.contextMenuBuilder != null && !widget.config.readOnly;

  @override
  bool get selectAllEnabled => widget.config.contextMenuBuilder != null;
}
