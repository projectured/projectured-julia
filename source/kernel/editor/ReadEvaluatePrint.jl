# Fragment of `EditorModule` — the three stages of a frame: read, evaluate and print.

# ── Read-Eval-Print ──────────────────────────────────────────────────

"""
    run_read_stage!(editor::Editor) -> Bool

Drain input window inputs via the backend until one translates into an
operation. Returns `true` when an operation was produced (stored in
`editor.operation`), `false` once the backend has nothing left to
deliver — used by `run_editor!` to decide when to stop draining and repaint.
An Escape that leaves the safe mode also answers `false`, so the projection that
is back paints before the input behind the Escape is read.

Window inputs that don't yield an operation (no iomap yet, or a projection
reader that passed the event through unchanged) are silently consumed;
there's nothing to evaluate or repaint for them.

Each input of the backend is a `WindowInput`: an event (KeyDown, KeyUp,
KeyPress, MouseDown, MouseUp, MouseMove, MouseScroll, WindowQuit, WindowClose,
…) and the id of the `WindowDocument` it came from. The window input is passed
to the reader of the projection, which translates it through the last stored
IoMap. The editor recognizes no gesture: a projection does, such as the gesture
tracking projection that the screen package puts around the screen.

A timer of `editor.timers` whose time has come is read first, as a bare
`TimerExpire`: a timer belongs to no window. The earliest one goes first, and it
leaves the timers when it is read.
"""
function run_read_stage!(editor::Editor)
    while true
        window_input = _pop_due_timer!(editor)
        window_input === nothing && (window_input = _read_from_devices_guarded(editor))
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
            change = read_intent(editor.projection, nothing,
                                 Intent(window_input, nothing), editor.iomap)
            op = change isa Intent ? change.operation : change
            if op isa Operation
                editor.operation = op
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
                # soon as the projection is back. The projection that is back has
                # no IoMap, so the frame paints before it reads the input behind
                # this Escape, and the next frame runs without a wait.
                if leave_safe_mode!(editor)
                    editor.operation = nothing
                    editor.wake_pending[] = true
                    return false
                end
                editor.operation = QuitEditorOperation()
                return true
            end
        end
    end
end

"""
    read_rooted_operation(editor, place, operation; description = "")
        -> Operation | Nothing

`operation`, which is relative to the document that `place` names, as an
operation from the root of `editor`'s document. The readers of
`editor.projection` from the root to `place` lift it on the way out, as they lift
the answer to a gesture, so every reader between the place and the root has its
turn: a wrapper reroots it, and a sorted view maps an index back. `place` is a
reference from the root.

It evaluates nothing. A caller evaluates the answer with `evaluate_operation`,
or posts it with `post_operation!`. `nothing` when the readers do not carry it
to the root.

`description` says in words what the operation does, for the gesture log. It
reads `editor.iomap`, which the frame prints, so it runs on the editor's task.
"""
function read_rooted_operation(editor, place::Reference, operation::Operation;
                               description::AbstractString = "")
    place isa EmptyReference && return operation
    editor.iomap === nothing &&
        throw(ArgumentError("read_rooted_operation: the editor has printed nothing, " *
                            "so no reader can carry the operation."))
    change = Intent(nothing, operation, String(description), "", place)
    answer = read_intent(editor.projection, nothing, change, editor.iomap)
    rooted = answer isa Intent ? answer.operation : answer
    rooted isa Operation ? rooted : nothing
end

# The `TimerExpire` of the earliest timer whose time has come, which leaves the
# timers, or `nothing` when no timer is due.
function _pop_due_timer!(editor::Editor)
    isempty(editor.timers) && return nothing
    name, due = first(editor.timers)
    for (other, other_due) in editor.timers
        other_due < due && ((name, due) = (other, other_due))
    end
    due <= time() || return nothing
    delete!(editor.timers, name)
    TimerExpire(name, due)
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
    run_evaluate_stage!(editor::Editor)

Apply the current operation to the document. Logs the operation, in the words
of `describe_operation`, when it is non-nothing.

When the fault policy of the editor enables the barriers, `run_evaluate_stage!` makes
the inverse of the operation first, and then runs the operation in the `:evaluate`
barrier. When the operation throws, the barrier records the fault, and
`run_evaluate_stage!` runs three repairs: it applies the inverse where there is one,
it drops the IoMap so that the next print starts from scratch, and it clears a
selection that does not resolve. With the barriers off, the exception goes on to the
caller.
"""
function run_evaluate_stage!(editor::Editor)
    # Log via @info, not a raw println: a call of the code tool runs on a
    # concurrent task that globally redirects `stdout`/`stderr` to a pipe (and
    # closes it), so a raw write to the live global stdout from this loop can land
    # in that closed pipe and crash. The logger writes to the stream captured at
    # startup, which the redirect leaves untouched.
    editor.operation !== nothing &&
        @info "[operation] $(describe_operation(editor.operation))"
    _evaluate_operation_guarded!(editor, editor.operation)
end

"""
    run_print_stage!(editor::Editor)

Project the editor's document through its projection pipeline. The root
`PrinterContext` holds the editor's own `clock`, so an animated cell that a
printer builds below it subscribes to the clock of this editor and not to a
shared one.

It also carries the editor's own document under `:root`. A projection deep in
the tree cannot reach the root any other way, and one that shows something about
the whole editor — where the selection is, which tabs are open — needs it.
"""
function run_print_stage!(editor::Editor)
    if editor.iomap === nothing
        # The store and the policy ride down with the context. A projection
        # barrier deep in the tree records into the store from inside a
        # computation, where it can write no cell and reach no editor, and it
        # catches only what the policy lets it catch. `PrinterContext` itself
        # does not change.
        ctx = with_property(
                  with_property(
                      with_property(
                          with_property(with_clock(PrinterContext(), editor.clock),
                                        :root, editor.document),
                          :fault_store, editor.faults),
                      :fault_policy, editor.fault_policy),
                  :noted_barriers, editor.noted_barriers)
        editor.iomap = print_document(editor.projection, nothing,
                                      editor.document, ctx)
    end
    is_editor_degraded(editor, :device_write) && return nothing
    _run_barrier(editor, :device; counter = :device_write,
                 origin = typeof(editor.backend)) do
        _write_output_to_devices!(editor)
    end
end

# A fault that a fault barrier took while the device read the output belongs to
# the printer, not to the device. The barrier recorded it and is on the list, so
# the frame skips the paint, the screen keeps the frame before it, and the next
# frame draws the mark. With no barrier on the list nothing will draw a mark, so
# the fault counts as a fault of the device, and the device barrier bounds it.
function _write_output_to_devices!(editor::Editor)
    try
        with(_PAINTING_EDITOR => editor) do
            # Through `invokelatest`, as every call of the backend protocol: a
            # backend package adds methods, which would invalidate a resolved call.
            Base.invokelatest(write_to_devices!, editor.backend, editor.devices,
                              editor.iomap.output)
        end
    catch exception
        (exception isa RecordedFaultException && !isempty(editor.noted_barriers)) ||
            rethrow()
        nothing
    end
end
