# Fragment of `EditorModule` — the inbox of operations and the wake that ends the wait.

# ── The inbox ─────────────────────────────────────────────────────────
#
# The one door into a running editor from outside its own task. A frame reads the
# document, evaluates against it and paints it, so anything that writes it from
# another task races the frame — and a reactive computation cannot write at all.
# An operation posted here is applied by the editor's own task at a defined point
# in the frame, which is the same guarantee an operation from the reader already
# has.

"""
    post_operation!(editor, operation) -> operation

Hand `editor` an operation to apply on its next frame. Thread-safe, and the only
supported way for anything outside the editor's task — a driver advancing a
simulation, a file watcher, an agent, a timer — to change what it shows.

Blocks once `INBOX_CAPACITY` operations are waiting, so a producer faster than
the editor is slowed down rather than allowed to queue work that will be stale
before it is applied.

Wakes the editor after the `put!`, so a posted operation is applied on the
next frame rather than on the next tick of a timer.
"""
post_operation!(editor::Editor, operation::Operation) =
    (put!(editor.inbox, operation); wake_editor!(editor); operation)

"""
    wake_editor!(editor) -> Nothing

Ask `editor` to run a frame now. Thread-safe, non-blocking and coalescing:
any number of calls before the next frame cost one frame, because the frame
takes the whole flag at once. [`post_operation!`](@ref) calls it after
`put!`; a feed's producer-side store calls it through the callback
[`attach_wake_callback!`](@ref) gave it.

The flag is the truth and the backend wake is only the kick that ends a wait
in progress. Only the false-to-true transition kicks, so the backend holds at
most one pending wake however often producers call this. A kick a frame
happens to consume costs nothing: the flag still skips the next wait.
"""
function wake_editor!(editor::Editor)
    Threads.atomic_xchg!(editor.wake_pending, true) && return nothing
    Base.invokelatest(wake_backend!, editor.backend)
    nothing
end

"""
    drain_operations!(editor) -> Int

Apply the operations that wait in the inbox when the drain starts, at most
`INBOX_CAPACITY`, and answer how many there were. Called once per frame by
`run_editor!`, before `run_read_stage!`, so the frame paints what it just applied.

An operation posted during the drain waits for the next drain, so a producer
that posts as fast as the editor applies can not hold off the paint. When
operations are left, the drain sets `editor.wake_pending`, and the next frame
runs without a wait.

Each operation applies in the operation barrier of [`run_evaluate_stage!`](@ref), with
the same repairs: an operation that fails half way is taken back where it has a way back,
the fault is recorded, and the next operation still applies. When the operations of the drain hold a call that another task posted with
[`run_on_editor_task!`](@ref), the whole drain runs as one code unit
([`run_code_unit!`](@ref)): on a thread of its own while the loop holds its frames,
so a long call keeps the window alive. The busy bar names each call in turn.

It is not
`run_evaluate_stage!` itself: posted
operations do not become `editor.operation`, because that field means "what the reader
made of this frame's input" and is what `_log_performance_counters!` uses to tell a frame
in which the user did something from an idle one. It also keeps a sync arriving ten times
a second out of the operation log.
"""
function drain_operations!(editor::Editor)
    # `Base.n_avail` also counts the producers that wait for room. The bound
    # keeps each `take!` to an operation that the inbox holds already.
    count = min(Base.n_avail(editor.inbox), INBOX_CAPACITY)
    operations = Operation[take!(editor.inbox) for _ in 1:count]
    calls = String[operation.description for operation in operations
                   if operation isa RunFunctionOperation]
    if isempty(calls)
        _apply_posted_operations!(editor, operations)
    else
        run_code_unit!(editor; parts = calls) do
            _apply_posted_operations!(editor, operations)
        end
    end
    isready(editor.inbox) && (editor.wake_pending[] = true)
    count
end

# Apply the operations that the drain took, in order. In a code unit, the bar names
# each call as it starts. An exception that means stop leaves the rest unapplied, and
# the end of the loop treats them as the operations still in the inbox.
function _apply_posted_operations!(editor::Editor, operations::Vector{Operation})
    unit = get_current_code_unit()
    part = 0
    for (index, operation) in enumerate(operations)
        if operation isa RunFunctionOperation
            part += 1
            unit === nothing || set_code_unit_part!(unit, part)
        end
        try
            _evaluate_operation_guarded!(editor, operation)
        catch
            append!(editor.unapplied_operations, operations[(index + 1):end])
            rethrow()
        end
    end
    nothing
end

# ── A call on the editor task ────────────────────────────────────────
#
# A tool that a client calls from the server's task, and a turn that streams on a
# task of its own, write the document too. They go through the inbox like every
# other writer. A tool call needs its answer back, so what it posts is a function
# and a channel: the editor runs the function in its drain and puts the answer
# into the channel, and the caller waits on it.

"""
    RunFunctionOperation(function_, answer, description = "a call from another task")

Run `function_()` on the editor task, in the drain of the inbox. `answer` is the
channel that takes `(true, value)` or `(false, exception)`, or `nothing` when no
task waits for the call. `description` names the call on the busy bar while it
runs in a code unit. [`run_on_editor_task!`](@ref) makes it.
"""
struct RunFunctionOperation <: Operation
    function_::Function
    answer::Union{Channel{Any}, Nothing}
    description::String
end

RunFunctionOperation(function_::Function, answer::Union{Channel{Any}, Nothing}) =
    RunFunctionOperation(function_, answer, "a call from another task")

# An exception goes to the task that waits for it, and a posted call that no task
# waits for throws into the barrier of the drain, which records it. An exception
# that means stop is thrown on here as well, so an interrupt still stops the loop.
function OperationModule.evaluate_operation(::Editor, operation::RunFunctionOperation)
    answer = operation.answer
    answer === nothing && return (operation.function_(); nothing)
    try
        put!(answer, (true, operation.function_()))
    catch exception
        put!(answer, (false, exception))
        is_fault_exception(exception) || rethrow()
    end
    nothing
end

# The call runs at once when no loop runs, and for the task that owns the documents:
# the task of the running code unit, or else the task of the loop.
function AgentModule.run_on_editor_task!(function_, editor::Editor; wait::Bool = true,
                                         description::AbstractString = "a call from another task")
    if editor.loop_task === nothing || _is_editor_owner(editor)
        value = function_()
        return wait ? value : nothing
    end
    answer = wait ? Channel{Any}(1) : nothing
    post_operation!(editor, RunFunctionOperation(function_, answer, String(description)))
    answer === nothing && return nothing
    succeeded, value = take!(answer)
    succeeded ? value : throw(value)
end

# The calls still in the inbox when the loop ends run here, on the task that ran
# the loop, where no frame runs any more. So a task that waits for one gets its
# answer and does not wait forever. An operation of another kind that was posted
# after the last frame is not applied. When the loop ends while a code unit still
# runs, after a quit, the unit owns the documents, so a call gets an exception as
# its answer and does not run.
function _answer_waiting_calls!(editor::Editor)
    is_unit_running = (@atomic editor.code_unit) !== nothing
    unapplied = copy(editor.unapplied_operations)
    empty!(editor.unapplied_operations)
    while !isempty(unapplied) || isready(editor.inbox)
        operation = isempty(unapplied) ? take!(editor.inbox) : popfirst!(unapplied)
        operation isa RunFunctionOperation || continue
        if is_unit_running
            operation.answer === nothing ||
                put!(operation.answer, (false, InvalidStateException(
                    "The editor quit while a code unit ran, so the call did not run.", :closed)))
            continue
        end
        try
            evaluate_operation(editor, operation)
        catch exception
            is_fault_exception(exception) || rethrow()
            record_fault!(editor.faults, :evaluate; origin = :RunFunctionOperation,
                          exception, traceback = catch_backtrace())
        end
    end
    nothing
end
