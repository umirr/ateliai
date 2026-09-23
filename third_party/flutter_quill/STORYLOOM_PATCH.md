# Local patches

Upstream flutter_quill 11.5.1, MIT license retained in LICENSE. Only lib/ and package metadata are vendored.

- `text_line.dart`: position list markers relative to first rendered glyph for center/right aligned paragraphs. Calculate caret height from the current span font size instead of line spacing. Render leading literal hash headings in a bold style and level-specific colors without editing document text or offsets.
- `raw_editor_state_selection_delegate_mixin.dart`: reveal caret against the scroll viewport using content-local coordinates, including keyboard and drag selections.
- `raw_editor_state.dart`: schedule caret reveal after layout without competing scroll animations; manual scrolling does not recreate the editor.

Covered by `test/editor_input_test.dart`. Keep these patches when upgrading Quill.

## 0.8.1

Windows CursorPainter preserves the glyph-sized prototype. Selection boxes use tight glyph bounds. Native input updates suppress intermediate remote echoes and retain valid composition ranges; mandatory trailing newlines are normalized. Controller replacement detaches and attaches the same listener. Regression coverage lives in the app editor and cursor tests.

## 0.8.2

Caret geometry uses tight glyph boxes rather than adding line-leading twice. Painter and IME caret rectangle share the same geometry. Selection drag does not trigger conflicting caret auto-scroll. Composition listeners detach before connection disposal. Desktop composition key ownership is guarded in the app editor.

## 0.8.3

Drag-selection start explicitly requests keyboard focus even when the desktop editor was unfocused. List leading styles use body font metrics, indent space grows with the font, marker baselines align with the body, and checkbox centers align to the first glyph line.
