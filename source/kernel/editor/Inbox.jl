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
before it is applied. A post of the owner of the editor never blocks: the task of
its loop, its running code unit, a task that the unit started, and any task before
the loop starts. Such a post goes to a queue with no bound, which the next drain
takes first, so the owner never waits for itself.

Throws `InvalidStateException` once the loop has ended, because nothing would
apply the operation.

Wakes the editor after the `put!`, so a posted operation is applied on the
next frame rather than on the next tick of a timer.
"""
function post_operation!(editor::Editor, operation::Operation)
    put!(_is_owner_post(editor) ? editor.owner_posts : editor.inbox, operation)
    wake_editor!(editor)
    operation
end

# Whether a post of the calling task goes to the queue of the owner: before the
# loop starts no task drains yet, the owner must never wait for itself, and a task
# that the running unit started must not wait for the drain that waits for the unit.
function _is_owner_post(editor::Editor)
    editor.loop_task === nothing && return true
    _is_editor_owner(editor) && return true
    unit = @atomic editor.code_unit
    unit !== nothing && get_current_code_unit() === unit
end

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
    # The posts of the owner first. `Base.n_avail` of the inbox also counts the
    # producers that wait for room. The bound keeps each `take!` to an operation
    # that the inbox holds already.
    owned = Base.n_avail(editor.owner_posts)
    count = owned + min(Base.n_avail(editor.inbox), INBOX_CAPACITY)
    operations = Operation[take!(index <= owned ? editor.owner_posts : editor.inbox)
                           for index in 1:count]
    calls = String[operation.description for operation in operations
                   if operation isa RunFunctionOperation]
    if isempty(calls)
        _apply_posted_operations!(editor, operations)
    else
        run_code_unit!(editor; parts = calls) do
            _apply_posted_operations!(editor, operations)
        end
    end
    (isready(editor.owner_posts) || isready(editor.inbox)) && (editor.wake_pending[] = true)
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
            # A stop of the unit runs the stop step of the call too.
            operation.stop === nothing || attach_code_unit_stop!(operation.stop)
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
    RunFunctionOperation(function_, answer, description = "a call from another task", stop = nothing)

Run `function_()` on the editor task, in the drain of the inbox. `answer` is the
channel that takes `(true, value)` or `(false, exception)`, or `nothing` when no
task waits for the call. `description` names the call on the busy bar while it
runs in a code unit, and `stop` is a function with no argument that a stop of that
unit runs, such as the cancel of the turn that made the call.
[`run_on_editor_task!`](@ref) makes it.
"""
struct RunFunctionOperation <: Operation
    function_::Function
    answer::Union{Channel{Any}, Nothing}
    description::String
    stop::Union{Function, Nothing}
    # 0 while the call waits, 1 once the editor started it, 2 once its caller
    # withdrew it. One compare-and-swap decides between the start and the
    # withdrawal, so a call never both runs and times out.
    state::Threads.Atomic{Int}
end

RunFunctionOperation(function_::Function, answer::Union{Channel{Any}, Nothing},
                     description::AbstractString = "a call from another task",
                     stop::Union{Function, Nothing} = nothing) =
    RunFunctionOperation(function_, answer, String(description), stop, Threads.Atomic{Int}(0))

# An exception goes to the task that waits for it, and a posted call that no task
# waits for throws into the barrier of the drain, which records it. An exception
# that means stop is thrown on here as well, so an interrupt still stops the loop.
function OperationModule.evaluate_operation(::Editor, operation::RunFunctionOperation)
    # A call that its caller withdrew after its timeout does not run.
    Threads.atomic_cas!(operation.state, 0, 1) == 0 || return nothing
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

AgentModule.is_editor_loop_running(editor::Editor) =
    editor.loop_task !== nothing && !editor.has_loop_ended

# The call runs at once when no loop runs, and for the task that owns the documents:
# the task of the running code unit, or else the task of the loop.
function AgentModule.run_on_editor_task!(function_, editor::Editor; wait::Bool = true,
                                         description::AbstractString = "a call from another task",
                                         timeout::Real = EDITOR_CALL_TIMEOUT_SECONDS,
                                         stop::Union{Function, Nothing} = nothing)
    if editor.loop_task === nothing || _is_editor_owner(editor)
        value = function_()
        return wait ? value : nothing
    end
    # A task or background work that the running unit started would wait for the
    # editor that waits for the unit (rule b of the plan of units). Once the unit
    # ended, the call waits for the drain after it.
    unit = @atomic editor.code_unit
    wait && unit !== nothing && !unit.ended[] && get_current_code_unit() === unit &&
        throw(CodeUnitWaitException(String(description)))
    answer = wait ? Channel{Any}(1) : nothing
    operation = RunFunctionOperation(function_, answer, description, stop)
    try
        post_operation!(editor, operation)
    catch exception
        exception isa InvalidStateException || rethrow()
        # The loop ended between the look at its task and the post. No frame runs
        # any more, so the call runs here, unless a unit still owns the editor.
        (@atomic editor.code_unit) === nothing || rethrow()
        value = function_()
        return wait ? value : nothing
    end
    answer === nothing && return nothing
    # The withdrawal at the timeout, unless the editor started the call first.
    timer = isfinite(timeout) ? Timer(timeout) do _
        Threads.atomic_cas!(operation.state, 0, 2) == 0 &&
            put!(answer, (false, EditorCallTimeoutException(operation.description, Float64(timeout))))
    end : nothing
    succeeded, value = try
        take!(answer)
    finally
        timer === nothing || close(timer)
    end
    succeeded ? value : throw(value)
end

# The end of the loop closes both queues first: a later post throws, and a producer
# that waits for room in the full inbox wakes with that exception. The calls still
# in the queues then run here, on the task that ran the loop, where no frame runs
# any more. So a task that waits for one gets its answer and does not wait
# forever. An operation of another kind that was posted after the last frame is
# not applied. When the loop ends while a code unit still runs, after a quit, the
# unit owns the documents, so a call gets an exception as its answer and does not
# run.
function _answer_waiting_calls!(editor::Editor)
    close(editor.owner_posts)
    close(editor.inbox)
    is_unit_running = (@atomic editor.code_unit) !== nothing
    unapplied = copy(editor.unapplied_operations)
    empty!(editor.unapplied_operations)
    while !isempty(unapplied) || isready(editor.owner_posts) || isready(editor.inbox)
        operation = !isempty(unapplied) ? popfirst!(unapplied) :
                    isready(editor.owner_posts) ? take!(editor.owner_posts) :
                    take!(editor.inbox)
        operation isa RunFunctionOperation || continue
        if is_unit_running
            operation.answer !== nothing && Threads.atomic_cas!(operation.state, 0, 2) == 0 &&
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
