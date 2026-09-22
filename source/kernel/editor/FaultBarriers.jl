# Fragment of `EditorModule` — the fault barriers of the loop: the per-stage guards, the repairs, and the frame report.

# ── The fault barriers ───────────────────────────────────────────────────────
#
# One barrier per stage of the frame. Each one answers its fallback rather than
# the exception, so a stage that fails costs that stage and not the editor.
# `editor.fault_policy` decides whether any of them catches at all; a programmatic
# editor starts strict, and `run_editor!` is what turns them on.

# What a barrier answers when it caught. A sentinel rather than `nothing`,
# because `nothing` is a value a stage may answer for itself.
struct _BarrierFailed end
const _BARRIER_FAILED = _BarrierFailed()

_run_barrier(body, editor::Editor, site::Symbol; counter::Symbol = site,
             origin = :editor, reference = nothing, fallback = nothing) =
    run_fault_barrier(body, editor.faults; policy = editor.fault_policy,
                      backend = editor.backend, site = site, counter = counter,
                      origin = origin, reference = reference, fallback = fallback)

"""
    report_frame_faults!(editor) -> Int

Hand every fault the last frame collected to whatever shows it, and answer how
many there were.

Call it once per frame, before anything reads the projection. This is the one
place a fault is reported on the console, because it is the one place that knows
which records are new — a printer's fault arrives here too, recorded from inside
a thunk that could not report anything itself.
"""
function report_frame_faults!(editor::Editor)
    records = drain_faults!(editor.faults)
    for record in records
        report_fault!(editor.faults, record; policy = editor.fault_policy,
                      backend = editor.backend)
    end
    length(records)
end

"""
    is_editor_degraded(editor, counter) -> Bool

Whether the work counted under `counter` has failed often enough in a row that
the editor is to stop doing it.

A backend that throws in `write_to_devices` throws again on the next frame, a
hundred times a second, and calling it again is worse than leaving it alone.

The two halves of the device seam count apart — `:device_write` and
`:device_read` — because they fail apart. With one counter between them, a read
that works resets the count a write that failed just raised, and nothing ever
trips.
"""
function is_editor_degraded(editor::Editor, counter::Symbol)
    limit = counter === :print ? editor.fault_policy.print_failure_limit :
                                 editor.fault_policy.device_failure_limit
    get_consecutive_fault_count(editor.faults, counter) >= limit
end

# The input half of the device seam. A backend that throws here throws again on
# the next frame, a hundred times a second, so the fault is counted at the
# `:device` site and the seam is left alone once it passes its limit. An editor
# whose input is gone still paints, which is what lets a person see why.
function _read_from_devices_guarded(editor::Editor)
    is_editor_degraded(editor, :device_read) && return nothing
    _run_barrier(editor, :device; counter = :device_read,
                 origin = typeof(editor.backend)) do
        read_from_devices(editor.backend, editor.devices)
    end
end

# An inverse reads the state the change starts from, so it is taken BEFORE the
# change is applied. Taking one can itself fail, and a way back that could not be
# worked out is `nothing` — a truthful answer, not an error.
function _make_operation_inverse(editor::Editor, operation)
    operation === nothing && return nothing
    try
        make_inverse_operation(editor.document, operation)
    catch
        nothing
    end
end

# What the editor does to itself after an operation failed half way.
function _repair_after_operation_fault!(editor::Editor, inverse)
    # Repair 0 — take the change back, where there is a way back. A
    # `CompoundOperation` has none: its way back is built member by member, and
    # only `evaluate_invertible_operation!` does that interleave.
    if inverse !== nothing
        try
            evaluate_operation(editor, inverse)
        catch
            # The way back failed too. The document stands as it is, and the
            # two repairs below still run.
        end
    end
    # Repair 1 — re-print from scratch. A change that failed half way often
    # leaves the reactive graph inconsistent, and a fresh print rebuilds it.
    invalidate_projection!(editor)
    # Repair 2 — a selection that no longer resolves is the usual reason a
    # printer then fails on every frame that follows.
    _repair_selection!(editor)
    nothing
end

function _repair_selection!(editor::Editor)
    try
        path = get_selection(editor.document)
        path === nothing && return nothing
        is_valid_reference(editor.document, path) && return nothing
        clear_selection!(editor.document)
        @warn "[fault] the selection did not survive a failed operation and was cleared"
    catch
        # A document that can not even be asked where its selection is has
        # nothing this repair can do for it.
    end
    nothing
end

"""
    evaluate!(editor::Editor)

Apply the current operation to the document. Logs the operation when it is
non-nothing.
"""
function evaluate!(editor::Editor)
    # Log via @info, not a raw println: the assistant runs `execute_julia_code` on
    # a concurrent task that globally redirects `stdout`/`stderr` to a pipe (and
    # closes it), so a raw write to the live global stdout from this loop can land
    # in that closed pipe and crash. The logger writes to the stream captured at
    # startup, which the redirect leaves untouched.
    editor.operation !== nothing && @info "[operation] $(editor.operation)"
    operation = editor.operation
    editor.fault_policy.is_barrier_enabled ||
        return evaluate_operation(editor, operation)
    inverse = _make_operation_inverse(editor, operation)
    answer = _run_barrier(editor, :evaluate;
                          origin = operation === nothing ? :nothing : typeof(operation),
                          fallback = _BARRIER_FAILED) do
        evaluate_operation(editor, operation)
    end
    answer === _BARRIER_FAILED || return answer
    _repair_after_operation_fault!(editor, inverse)
    nothing
end

"""
    print!(editor::Editor)

Project the editor's document through its projection pipeline. The root
`PrinterContext` is minted with the editor's own `clock`, so animated cells
descendants build subscribe to this editor's clock rather than a shared one.

It also carries the editor's own document under `:root`. A projection deep in
the tree cannot reach the root any other way, and one that shows something about
the whole editor — where the selection is, which tabs are open — needs it.
"""
function print!(editor::Editor)
    if editor.iomap === nothing
        # The store rides down with the context. A projection barrier deep in
        # the tree records into it from inside a thunk, where it can write no
        # cell and reach no editor. `PrinterContext` itself does not change.
        ctx = with_property(
                  with_property(with_clock(PrinterContext(), editor.clock),
                                :root, editor.document),
                  :fault_store, editor.faults)
        editor.iomap = print_document(editor.projection, nothing,
                                      editor.document, ctx)
    end
    is_editor_degraded(editor, :device_write) && return nothing
    _run_barrier(editor, :device; counter = :device_write,
                 origin = typeof(editor.backend)) do
        write_to_devices(editor.backend, editor.devices, editor.iomap.output)
    end
end
