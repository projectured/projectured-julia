# Settings in the view

> **Kind:** design · **Status:** current · **Stands on:** [settings.md](../settings/settings.md), [editor.md](../../kernel/editor.md), [appearance.md](../appearance/appearance.md)

The settingsmanaging slice of `ProjecturedPlatform` connects the `Settings` of an editor to its view. It holds the `Settings` in the root document, turns each normal edit of a setting into an applied setting, and brings the values to the places where they act when the editor starts. The editor holds no setting and reads none: it gets a document and a projection, as always.

## The parts

- `SettingsDocument(settings, content)` is the root document of an editor with the wrapper. The `Settings` are a part of the document, so a view can show them and a reference can name them. `get_wrapped_document` goes through it to the content.
- `SettingsManagingProjection(inner)` prints the content through `inner` and returns its output, and maps references through the `content` field. Its reader asks the content first, and then the gesture table of the `SettingsDocument`.
- `wrap_setting_writes(settings, operation)` replaces each `ReplaceReferencedValueOperation` of one setting of a group of `settings` with an `ApplySettingOperation` of it, also inside a `CompoundOperation` or a `WrappingOperation`. The reader of the wrapper calls it on every answer. Every other operation stays as it is.
- The `settings` wrapper of `build_editor` puts both around everything else, the appearance wrapper too (`:screen => 10`). It is on by default.
- The commands "Toggle partial render" and "Toggle repaint outline" have no key; a person runs them from the palette.

## Why the wrapper turns the edit

Every view of a settings group makes the same normal edit of a field: a settings tab, `ObjectToWidget`, an inspector, a paste. The wrapper is the one place where such an edit becomes a write and an apply, so no view contains the effect of a setting, and no view can leave it out.

An `ApplySettingOperation` that comes from another path, such as the inbox, applies its group too, because the effect is in its evaluation. A plain `ReplaceReferencedValueOperation` of a group that does not pass the readers writes the cell and applies nothing.

## The start of an editor

A start step of the wrapper runs once the editor exists (`start_settings!`):

- A `Settings` that a main builder made and filled from its sources wins: the step applies each group to the editor and to its backend.
- For `settings = true` the wrapper makes a `Settings` with the default group of each loaded type, with `is_read_from_targets` set. The step first reads each group from the editor and its backend with `read_settings!`, then reads the environment variables, which win for one run, and then applies. So a value that a caller gave a target directly, such as `build_editor(...; fault_policy)` or a keyword of a backend, stays, and the settings show what acts.

The `window` wrapper takes the `PointerSettings` of the same editor from `EditorParts.arguments`, so the recognitions of its gesture tracker read the cells of the group.

## Tests that check the root

The wrapper changes the root of every editor that `build_editor` makes. A test that checks the root document after `build_editor`, or the depth of a selection path, turns it off with `settings = false`, as it turns off `appearance` and `tabs`.

See [plan/pending/editor-settings.md](../../../../plan/pending/editor-settings.md) for the design and its decisions.
