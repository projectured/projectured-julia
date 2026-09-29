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
a computation that could not report anything itself.
"""
function report_frame_faults!(editor::Editor)
    records = drain_faults!(editor.faults; policy = editor.fault_policy)
    for record in records
        report_fault!(editor.faults, record; policy = editor.fault_policy,
                      backend = editor.backend)
    end
    length(records)
end

const _CONSECUTIVE_FAULT_LIMITS = (print = 4, device_read = 8, device_write = 8)

"""
    get_consecutive_fault_limit(counter) -> Int

How many faults in a row the work counted under `counter` takes before the
editor stops it: `:print` before the editor enters the safe mode, and
`:device_read` or `:device_write` before the editor stops calling that half of
the device seam. An unknown counter is an error.

See also [`is_editor_degraded`](@ref), which compares the count with it.
"""
get_consecutive_fault_limit(counter::Symbol) =
    getfield(_CONSECUTIVE_FAULT_LIMITS, counter)

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
    count = get_consecutive_fault_count(editor.faults, counter)
    count >= get_consecutive_fault_limit(counter)
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

# The barrier of one operation. It applies `operation`, and when the operation
# fails half way, it takes the change back where there is a way back and runs the
# repairs below. It writes no log line and leaves `editor.operation` alone, so
# `evaluate!` and the drain of the inbox apply an operation the same way.
function _evaluate_operation_guarded!(editor::Editor, operation)
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

# An inverse reads the state the change starts from, so it is taken BEFORE the
# change is applied. Taking one can itself fail: the fault is recorded, and a way
# back that could not be worked out is `nothing` — a truthful answer, not an error.
function _make_operation_inverse(editor::Editor, operation)
    operation === nothing && return nothing
    try
        make_inverse_operation(editor.document, operation)
    catch exception
        is_passthrough_exception(exception) && rethrow()
        record_fault!(editor.faults, :evaluate; origin = typeof(operation), exception,
                      traceback = catch_backtrace())
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
        catch exception
            is_passthrough_exception(exception) && rethrow()
            # The way back failed too. The document stands as it is, and the
            # two repairs below still run.
            record_fault!(editor.faults, :evaluate; origin = typeof(inverse), exception,
                          traceback = catch_backtrace())
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
    catch exception
        is_passthrough_exception(exception) && rethrow()
        # A document that can not even be asked where its selection is has
        # nothing this repair can do for it.
        record_fault!(editor.faults, :evaluate; origin = :_repair_selection!, exception,
                      traceback = catch_backtrace())
    end
    nothing
end
