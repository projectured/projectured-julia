"""
    UndoModule

**The way back.** An `UndoBuffer` is a document that holds another document and
the steps that take it back, and `UndoBufferToAnyProjection` is the transparent
projection that makes the buffer invisible and records what passes through it.

The buffer is a document and not a field of the editor, so a window can have one
history and each file inside it another. The one closest to the focus answers
`Ctrl+Z`, and the one above records that it did — an outer buffer takes an inner
buffer's step back by asking the inner buffer to undo, because a redo is the way
back from an undo.

Nothing is recorded by a reader. The reader answers a `RecordUndoOperation`, and
`evaluate_operation` takes the way back through `make_inverse_operation` before
it applies the change. A change nobody could invert becomes a **barrier**, and
undo stops at it rather than building a state the person never saw.

The module lives in four fragments that share this namespace:

- [`UndoDocument.jl`](UndoDocument.jl) — the buffer, one entry, the three
  operations and the default filter.
- [`UndoBufferToAny.jl`](UndoBufferToAny.jl) — the transparent projection: the
  printer, the two reference maps, the reader and the gesture table.
- [`UndoTheme.jl`](UndoTheme.jl) — the theme of the history.
- [`UndoBufferToSyntax.jl`](UndoBufferToSyntax.jl) — the history itself, drawn
  for a person to read.
- [`HistorySettings.jl`](HistorySettings.jl) — `HistorySettings`, how many steps
  each history keeps.
"""
module UndoModule

using ..CellModule
using ..CollectionModule
using ..DocumentModule
using ..GestureModule
using ..GraphicsModule
using ..StyleModule
using ..SyntaxModule
using ..TextModule
using ..EventModule
using ..GestureBindingModule
using ..IntentModule
using ..IoMapModule
using ..OperationModule
using ..ProjectionModule
using ..ReferenceModule
using ..SelectionModule
using ..SettingsModule
using ..ToolModule
using ..EditorModule
using ..AgentModule
using ..ProjectionAlgebraModule
using ..NaturalModule

# Imported to extend: this module adds a method to each of these.
import ..DocumentModule: get_wrapped_document, replace_wrapped_document!, get_edited_field,
                         get_document_title
import ..OperationModule: evaluate_operation, make_inverse_operation,
                          get_wrapped_operation, rewrap_operation,
                          is_self_contained_operation
import ..ProjectionModule: get_projection_gesture_bindings
import ..FileFormatModule: record_saved_state!, has_unsaved_edits, get_saved_text_hash
import ..EditorModule: wrap_editor!, get_wrapper_layers
import ..ProjectionModule: print_document, read_intent,
                           map_reference_forward, map_reference_backward

export make_history_wrap
export UndoDocument, UndoBuffer, UndoEntry, is_undo_barrier,
       push_undo_entry!, clear_undo_history!, is_undo_step,
       RecordUndoOperation, UndoOperation, RedoOperation, make_undoable_operation,
       TYPING_PAUSE, get_typing_caret,
       find_undo_buffer, describe_undo_history, register_undo_tools!,
       UndoBufferToAnyProjection, UndoBufferToAnyIoMap,
       UndoTheme, ScaledUndoTheme, UndoBufferToSyntax, make_undo_projection,
       HistorySettings

include("UndoDocument.jl")
include("UndoBufferToAny.jl")
include("UndoTheme.jl")
include("UndoBufferToSyntax.jl")
include("HistorySettings.jl")

# The row that lets every renderer draw a history: what it holds, and nothing of
# its own. The open of a file gives the file a history in every editor that has
# settings, so no editor can be left without the row.
function __init__()
    register_natural_graphics!(:undo, (; measure, appearance) -> Pair{Type,Any}[
        UndoBuffer => UndoBufferToAnyProjection()])
end

end # module
