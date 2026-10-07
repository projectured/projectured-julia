# Fragment of `UndoModule` — the settings of the histories of an editor.

"""
    HistorySettings(; undo_capacity = 100)

How many steps the undo history of each document keeps before it drops the
oldest one.

How many steps each history of an editor keeps. A builder gives each `UndoBuffer`
that it makes the cell of the setting, `get_setting_cell(settings,
:undo_capacity)`, so a change reaches every buffer, and a buffer that holds more
steps drops the oldest at its next step.
"""
@settings struct HistorySettings
    "Undo steps: the most steps that each history keeps."
    undo_capacity::Int = 100 in 10:10000
end

"""
    make_history_wrap(settings) -> Function

The function that puts a document into an `UndoBuffer` whose capacity is the cell
of `undo_capacity` of the `HistorySettings` of `settings`, so the history follows
a change of the setting. The open of a file gives each file it opens one, and an
application gives the files that it opens at its start one.
"""
make_history_wrap(settings::Settings) =
    content -> UndoBuffer(content; capacity = get_setting_cell(
        get_settings_group!(settings, HistorySettings), :undo_capacity))
