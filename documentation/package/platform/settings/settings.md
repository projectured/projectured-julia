# Settings

> **Kind:** design · **Status:** current · **Stands on:** [editor.md](../../kernel/editor.md), [operation.md](../../kernel/operation.md), [document.md](../../kernel/document.md)

The settings slice of `ProjecturedPlatform` holds what a person chooses about how an editor works: whether a window repaints only what changed, how long a double click can take, whether a fault stops the editor. A setting is a field of a document, so a view shows it and an edit changes it, as for any other document. The editor and the kernel read no setting.

## The parts

- `@settings struct NameSettings … end` declares a settings group: a document with one cell for each setting. Each setting has a docstring `"Label: text"`, a type (`Bool`, `Int`, `Float64`, `Symbol` or `String`), a default, and, after `in`, the values that it can take. The macro also adds `get_setting_descriptions(T)`, one `SettingDescription` for each setting, and `get_settings_name(T)`, the name of the group in a settings file.
- A slice declares the group of the part that it owns, beside the code that acts on it.
- `Settings` holds the groups of one editor, one of each type, found by the declared type of the group. `make_settings(groups...)` makes one with the default group of each loaded group type; the method table of `get_setting_descriptions` is the list of the types, and no table names them.
- `ApplySettingOperation(write)` holds a `ReplaceReferencedValueOperation` of one setting of a group. Its evaluation checks the value against the description and converts it, writes it, and then applies the group with `apply_settings_to_editor!`. A value that does not fit changes nothing and writes a warning to the log. Its inverse is the same operation around the inverse of the write, so an undo writes the old value and then applies it.
- `apply_settings!(target, group)` copies the values of a group to a target, where they act outside the documents: a field of a backend, the fault policy of an editor. The default does nothing; the owner of a target adds a method. `is_settings_target(target, group)` answers whether a method applies the group to the target.

## Why a wrapping operation

A change of a setting is a write and an effect. `ApplySettingOperation` is a `WrappingOperation`, so the effect runs after the write in both directions. Two operations in a `CompoundOperation` would undo in the reverse order: the apply first, with the new value still in the cell, and then the write of the old value, so the target keeps the new value.

The effect is in the evaluation, not in a projection. An `ApplySettingOperation` that comes from the inbox, from a server or from a load applies its group, as one that comes from a view does.

See [plan/pending/editor-settings.md](../../../../plan/pending/editor-settings.md) for the design and its decisions.
