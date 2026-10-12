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
    make_safe_mode_projection(store) -> projection or nothing

A projection that shows the faults in `store` and nothing else.

Use it when the printer failed so many times in a row that it draws nothing.
The projection it answers replaces the one that fails, so the screen still
shows something: at worst, the list of what went wrong.

While the safe mode lasts, the editor attaches the projection to `store` as a
fault target, and it detaches the projection when the safe mode ends. So a
projection that answers `append_fault!` shows the faults that arrive meanwhile.

The default is `nothing`. Then nothing replaces the projection, and the frame
before stays on the screen. A package that can draw a fault answers it, so the
kernel names neither a log document nor a projection.

# Example

    projection = make_safe_mode_projection(editor.faults)

See also [`enter_safe_mode!`](@ref).
"""
function make_safe_mode_projection end

make_safe_mode_projection(store) = nothing

"""
    enter_safe_mode!(editor) -> Bool

Put the projection aside and show the fault list instead. Answers whether it
happened: nothing answered `make_safe_mode_projection`, or the editor was
already in the safe mode, and it did not.

The projection of the safe mode is a target of the fault store until
[`leave_safe_mode!`](@ref).
"""
function enter_safe_mode!(editor::Editor)
    is_editor_in_safe_mode(editor) && return false
    projection = make_safe_mode_projection(editor.faults)
    projection isa Projection || return false
    editor.replaced_projection = editor.projection
    editor.projection = projection
    attach_fault_target!(editor.faults, projection)
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

Put the projection back, and detach the projection of the safe mode from the
fault store. Answers whether the editor was in the safe mode.
"""
function leave_safe_mode!(editor::Editor)
    is_editor_in_safe_mode(editor) || return false
    detach_fault_target!(editor.faults, editor.projection)
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
