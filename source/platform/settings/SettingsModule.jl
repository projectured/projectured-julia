"""
    SettingsModule

The settings of an editor: what a person chooses about how the editor works, in
groups of documents, one group for each part that acts on them.

A slice declares a group with `@settings`, and a `Settings` holds the groups of
one editor. A setting changes through `ApplySettingOperation`, which writes the
value and then applies the group with `apply_settings!`: the slice or the package
that owns a target, such as a backend, copies the values there. The editor and
the kernel read no setting.

- [`SettingsGroup.jl`](SettingsGroup.jl) — `SettingsGroup`, `SettingDescription`
  and the macro `@settings`.
- [`Settings.jl`](Settings.jl) — `Settings`, the groups of one editor.
- [`ApplySettingOperation.jl`](ApplySettingOperation.jl) — the write and the
  apply of a setting, and the seam `apply_settings!`.
- [`SettingsEnvironment.jl`](SettingsEnvironment.jl) — the environment variables
  that set a setting for one run.
- [`SettingsFile.jl`](SettingsFile.jl) — the settings file, and the operations
  that save and load it.
"""
module SettingsModule

using ..DocumentModule
using ..OperationModule
using ..ReferenceModule

import TOML

import ..DocumentModule: get_document_title
import ..OperationModule: evaluate_operation, describe_operation, make_inverse_operation,
                          is_self_contained_operation, get_wrapped_operation,
                          rewrap_operation

export SettingsGroup, SettingDescription, get_setting_descriptions, get_settings_name,
       get_settings_group_type, find_setting_description, convert_setting_value, @settings
export Settings, compute_loaded_settings_types, make_settings, get_settings_group!,
       set_settings_group!, get_settings_groups, is_settings_group, get_setting_cell
export apply_settings!, is_settings_target, is_settings_group_applied,
       is_settings_group_read_at_start, is_settings_group_used, read_settings!,
       read_settings_from_editor!, apply_settings_to_editor!, ApplySettingOperation,
       is_setting_write
export get_setting_environment_names, read_settings_environment!
export get_configuration_folder, get_settings_file, write_settings_file!,
       read_settings_file!, SaveSettingsOperation, LoadSettingsOperation

include("SettingsGroup.jl")
include("Settings.jl")
include("ApplySettingOperation.jl")
include("SettingsEnvironment.jl")
include("SettingsFile.jl")

end # module SettingsModule
