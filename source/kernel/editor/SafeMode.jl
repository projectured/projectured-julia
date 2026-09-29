# Fragment of `EditorModule` — the safe mode, which swaps in the fault list.

# ── The safe mode ────────────────────────────────────────────────────────────
#
# The last guarantee: the editor always shows something. When the printer has
# failed on every frame for long enough that no repair helped, the projection is
# put aside and one that draws the fault list takes its place. At worst a person
# reads what went wrong instead of looking at a window that stopped moving.
#
# The kernel draws nothing itself, so it asks through `make_safe_mode_projection`
# and does nothing when nothing answers.

"""
    is_editor_in_safe_mode(editor) -> Bool

Whether the editor put its projection aside and is showing the fault list.
"""
is_editor_in_safe_mode(editor::Editor) = editor.replaced_projection !== nothing

"""
    enter_safe_mode!(editor) -> Bool

Put the projection aside and show the fault list instead. Answers whether it
happened: nothing answered `make_safe_mode_projection`, or the editor was
already in the safe mode, and it did not.
"""
function enter_safe_mode!(editor::Editor)
    is_editor_in_safe_mode(editor) && return false
    projection = make_safe_mode_projection(editor.faults)
    projection isa Projection || return false
    editor.replaced_projection = editor.projection
    editor.projection = projection
    invalidate_projection!(editor)
    # The count that brought us here is spent. A fault in the safe mode itself
    # must be able to raise a fresh one.
    reset_consecutive_fault_count!(editor.faults, :print)
    @warn("[fault] the printer failed too often in a row; showing the fault list. " *
          "Press Escape to go back.")
    true
end

"""
    leave_safe_mode!(editor) -> Bool

Put the projection back. Answers whether the editor was in the safe mode.
"""
function leave_safe_mode!(editor::Editor)
    is_editor_in_safe_mode(editor) || return false
    editor.projection = editor.replaced_projection
    editor.replaced_projection = nothing
    invalidate_projection!(editor)
    reset_consecutive_fault_count!(editor.faults, :print)
    true
end

# Called once per frame, after the paint. Entering is what the print-failure
# limit means, and it is also what bounds a substitute that can not be printed:
# that one re-raises every frame, so the count climbs and this puts a stop to it.
_consider_safe_mode!(editor::Editor) =
    is_editor_degraded(editor, :print) && enter_safe_mode!(editor)
