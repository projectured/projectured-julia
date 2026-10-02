# Settings in the view

> **Kind:** design · **Status:** current · **Stands on:** [settings.md](../settings/settings.md), [editor.md](../../kernel/editor.md), [appearance.md](../appearance/appearance.md)

The settingsmanaging slice of `ProjecturedPlatform` connects the `Settings` of an editor to its view. It holds the `Settings` in the root document, turns each normal edit of a setting into an applied setting, and brings the values to the places where they act when the editor starts. The editor holds no setting and reads none: it gets a document and a projection, as always.

## The parts

- `SettingsDocument(settings, content)` is the root document of an editor with the wrapper. The `Settings` are a part of the document, so a view can show them and a reference can name them. `get_wrapped_document` goes through it to the content.
- `SettingsManagingProjection(inner)` prints the content through `inner` and returns its output, and maps references through the `content` field. Its reader asks the content first, and then the gesture table of the `SettingsDocument`.
- `wrap_setting_writes(settings, operation)` replaces each `ReplaceReferencedValueOperation` of one setting of a group of `settings` with an `ApplySettingOperation` of it, also inside a `CompoundOperation` or a `WrappingOperation`. The reader of the wrapper calls it on every answer. Every other operation stays as it is.
- The `settings` wrapper of `build_editor` puts both around everything but the appearance wrapper (`:screen => -10`), so the `AppearanceDocument` stays the root and the `SettingsDocument` is its content. It is on by default.
- The commands "Show the settings", "Toggle partial render" and "Toggle repaint outline" have no key; a person runs them from the palette. "Show the settings" focuses the tab that shows the settings, or opens one.

## Why the wrapper turns the edit

Every view of a settings group makes the same normal edit of a field: a settings tab, `ObjectToWidget`, an inspector, a paste. The wrapper is the one place where such an edit becomes a write and an apply, so no view contains the effect of a setting, and no view can leave it out.

An `ApplySettingOperation` that comes from another path, such as the inbox, applies its group too, because the effect is in its evaluation. A plain `ReplaceReferencedValueOperation` of a group that does not pass the readers writes the cell and applies nothing.

## The start of an editor

A start step of the wrapper runs once the editor exists (`start_settings!`):

- A `Settings` that a main builder made and filled from its sources wins: the step applies each group to the editor and to its backend.
- For `settings = true` the wrapper makes a `Settings` with the default group of each loaded type, with `is_read_from_targets` set. The step first reads each group from the editor and its backend with `read_settings!`, then reads the environment variables, which win for one run, and then applies. So a value that a caller gave a target directly, such as `build_editor(...; fault_policy)` or a keyword of a backend, stays, and the settings show what acts.

The `window` wrapper takes the `PointerSettings` of the same editor from `EditorParts.arguments`, so the recognitions of its gesture tracker read the cells of the group.

## The settings tab

`SettingsToWidget` draws the `Settings` of an editor as widgets in a `WidgetScrollPane`, and the slice registers it with the natural renderer, so a tab that holds the `Settings` draws them. The slice takes the printer of the pane from the widget printer with the widget theme of the appearance, as the appearance tab does. The toolbar of the window and its View menu open the tab with the `Settings` of the editor (`find_editor_settings`).

- One card for each group, in the order of their names, and one row for each setting: the label, whose tooltip is the text of the setting, the control, and a button that resets it. Under the cards, "Reset all".
- A `Bool` is a switch, a number with a range is a spin box with the step of the range, a `Symbol` with its choices is a radio group, and a `String` is a text. A text edit becomes the write of the whole text and a caret after the characters that it put in.
- The selection works the normal way. The tab wires the paths of its output with `set_output_path_computations!` and carries them down its widgets with `set_output_tree_path_computations!`; a path that a press or Tab makes goes back through the default reader of the kernel, which introduces it into the `Settings`. So Tab and the arrows reach each control, Space and Return change a switch, and a text draws its caret.
- Each control is a computed cell over its setting, so it follows a change from any path: a command, an undo, a load.
- The pane keeps its own place. A change of a setting does not print the tab again, so the place stays. A change of "Catch faults" prints the whole view again (`invalidate_projection!`), because each fault barrier decides while it prints whether it catches, and the new pane starts at the top. The `Settings` can not keep the place as the `Appearance` does, because the settings slice is below the style slice that holds `Point2D`.
- The start step keeps the types of the groups that the editor does not use in `Settings.unused_types`: an applied group (`is_settings_group_applied`) that neither the editor nor its backend applies, such as the render group of a backend that draws no windows. The card of such a group says so, and its controls are off.
- A control edit, a reset and "Reset all" are normal edits of the groups. The wrapper applies them, and a history that holds the tab records them, so Ctrl+Z takes a change back and applies the old value.

## Tests that check the root

The wrapper changes the root of every editor that `build_editor` makes. A test that checks the root document after `build_editor`, or the depth of a selection path, turns it off with `settings = false`, as it turns off `appearance` and `tabs`.

See [plan/done/editor-settings.md](../../../../plan/done/editor-settings.md) for the design and its decisions.
