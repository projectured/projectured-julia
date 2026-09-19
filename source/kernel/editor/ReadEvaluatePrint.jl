# Fragment of `EditorModule` — the three stages of a frame: read the input, evaluate the operation, print the document.

# ── Read-Eval-Print ──────────────────────────────────────────────────

"""
    read!(editor::Editor) -> Bool

Drain input window inputs via the backend until one translates into an
operation. Returns `true` when an operation was produced (stored in
`editor.operation`), `false` once the backend has nothing left to
deliver — used by `run_editor!` to decide when to stop draining and repaint.

Window inputs that don't yield an operation (no iomap yet, or a projection
reader that passed the event through unchanged) are silently consumed;
there's nothing to evaluate or repaint for them.

Raw backend events are first pulled through the editor's `GestureRecognizer`
(`pop_gesture!`), which is where multi-event combinations become gestures —
e.g. a `MouseDown`/`MouseUp` pair is recognised as a `MousePress` click. The
recogniser returns an `WindowInput` wrapping a backend-agnostic gesture
(KeyDown, KeyUp, KeyPress, MouseDown, MouseUp, MousePress, MouseMove,
MouseScroll, WindowQuit, WindowClose, …) together with the originating
`WindowDocument.id`. The window input is passed to the projection pipeline reader
which translates it via the last stored IoMap.
"""
function read!(editor::Editor)
    while true
        window_input = pop_gesture!(editor.recognizer,
                            () -> _read_from_devices_guarded(editor))
        if window_input === nothing
            editor.operation = nothing
            return false
        elseif window_input isa WindowInput && window_input.event isa WindowQuit
            editor.operation = QuitEditorOperation()
            return true
        elseif editor.iomap === nothing
            continue
        else
            # Seed a nothing-change carrying the gesture (the window input) and read
            # back the operation the reader pipeline produced.
            change = read_intent(editor.projection, nothing, Intent(window_input, nothing), editor.iomap)
            op = change isa Intent ? change.operation : change
            if op isa Operation
                editor.operation = op
                return true
            end
            # Editor-global readability zoom, recognised *after* the pipeline so a
            # projection that explicitly binds these keys (e.g. clipboard add/remove
            # on Ctrl+=/-) still wins when active.
            z = _zoom_operation(window_input)
            if z !== nothing
                editor.operation = z
                return true
            end
            # Escape closes the editor, but only when nothing else wanted it. A
            # reader that binds Escape — a dialog, an insertion, the command palette
            # — produced an operation above and won, so its Escape never reaches
            # here. This is why a backend must deliver Escape as a key rather than
            # as a quit: a quit cannot be declined.
            if _is_quit_gesture(window_input)
                # In the safe mode, Escape means "out of this", not "out of the
                # editor". The quit gesture goes back to its usual meaning as
                # soon as the projection is back.
                leave_safe_mode!(editor) && continue
                editor.operation = QuitEditorOperation()
                return true
            end
        end
    end
end

"""
    _is_quit_gesture(window_input) -> Bool

Is this the bare Escape that closes the editor? Modified Escape is left alone, so
a chord stays available to a projection.
"""
function _is_quit_gesture(window_input)
    window_input isa WindowInput || return false
    event = window_input.event
    event isa KeyDown || return false
    event.key === :escape || return false
    m = event.modifiers
    !(m.ctrl || m.shift || m.alt || m.meta)
end

"""
    _zoom_operation(window_input) -> Operation or nothing

Map a Ctrl-modified `=`/`-`/`0` key gesture to a readability-zoom operation:
`Ctrl` (optionally with Shift, so `Ctrl++` also works) → uniform
[`AdjustZoomOperation`](@ref); add `Alt` → font-only [`AdjustFontZoomOperation`](@ref).
`=`/`+` zooms in (+1), `-` out (-1), `0` resets (0). Returns `nothing` for
anything else. Recognised at the editor level so zoom works regardless of what
is selected.
"""
function _zoom_operation(window_input)
    window_input isa WindowInput || return nothing
    ev = window_input.event
    ev isa KeyDown || return nothing
    m = ev.modifiers
    (m.ctrl && !m.meta) || return nothing
    delta = ev.key === :equals ? 1  :
            ev.key === :minus  ? -1 :
            ev.key === :zero   ? 0  : nothing
    delta === nothing && return nothing
    m.alt ? AdjustFontZoomOperation(delta) : AdjustZoomOperation(delta)
end


# An editor is what keeps faults, and this is how code that holds one without
# being able to name its type reaches them. The kernel's agent layer drives a
# tool against a target it knows only as `Any`.
FaultModule.get_fault_store(editor::Editor) = editor.faults
FaultModule.get_fault_policy(editor::Editor) = editor.fault_policy
