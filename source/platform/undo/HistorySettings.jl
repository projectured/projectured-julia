# Fragment of `UndoModule` — the settings of the histories of an editor.

"""
    HistorySettings(; undo_capacity = 100)

How many steps each history of an editor keeps. A builder gives each `UndoBuffer`
that it makes the cell of the setting, `get_setting_cell(settings,
:undo_capacity)`, so a change reaches every buffer, and a buffer that holds more
steps drops the oldest at its next step.
"""
@settings struct HistorySettings
    "Undo steps: the most steps that each history keeps."
    undo_capacity::Int = 100 in 10:10000
end
