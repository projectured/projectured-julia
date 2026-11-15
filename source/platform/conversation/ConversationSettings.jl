# Fragment of `ConversationModule` — the settings of the transcripts of an editor.

"""
    ConversationSettings(; finished_turn = :message)

What a transcript shows of a finished answer of the model. `:message` shows its
message, with the work before it (the thinking, the tool calls and the texts
between them) folded into one line that opens to it. `:everything` shows every
part, as while the answer runs.

The transcript reads the cell of the setting, `get_setting_cell(settings,
:finished_turn)`, so a change reaches every finished turn that a person did not
open or fold.
"""
@settings struct ConversationSettings
    "Finished turn: what a finished answer shows, its message with the work folded into one line, or everything."
    finished_turn::Symbol = :message in (:message, :everything)
end
