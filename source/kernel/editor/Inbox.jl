# Fragment of `EditorModule` — the inbox: the one operation door into a running editor, and the wake that ends its wait.

# ── The inbox ─────────────────────────────────────────────────────────
#
# The one door into a running editor from outside its own task. A frame reads the
# document, evaluates against it and paints it, so anything that writes it from
# another task races the frame — and a reactive computation cannot write at all
# (PAR-NO-WRITE-IN-THUNK). An operation posted here is applied by the editor's own
# task at a defined point in the frame, which is the same guarantee an operation
# from the reader already has.

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
    wake_backend!(editor.backend)
    nothing
end

"""
    drain_operations!(editor) -> Int

Apply every operation waiting in the inbox and answer how many there were.
Called once per frame by `run_editor!`, before `read!`, so the frame paints what
it just applied.

Applied through `evaluate_operation` rather than [`evaluate!`](@ref): posted
operations do not become `editor.operation`, because that field means "what the
reader made of this frame's input" and is what `perf!` uses to tell a frame in
which the user did something from an idle one. It also keeps a sync arriving ten
times a second out of the operation log.
"""
function drain_operations!(editor::Editor)
    count = 0
    while isready(editor.inbox)
        evaluate_operation(editor, take!(editor.inbox))
        count += 1
    end
    count
end

# ── A call on the editor task ────────────────────────────────────────
#
# A tool that a client calls from the server's task, and a turn that streams on a
# task of its own, write the document too. They go through the inbox like every
# other writer. A tool call needs its answer back, so what it posts is a function
# and a channel: the editor runs the function in its drain and puts the answer
# into the channel, and the caller waits on it.

"""
    RunFunctionOperation(function_, answer)

Run `function_()` on the editor task, in the drain of the inbox. `answer` is the
channel that takes `(true, value)` or `(false, exception)`, or `nothing` when no
task waits for the call. [`run_on_editor_task!`](@ref) makes it.
"""
struct RunFunctionOperation <: Operation
    function_::Function
    answer::Union{Channel{Any}, Nothing}
end

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
        is_passthrough_exception(exception) && rethrow()
    end
    nothing
end

function AgentModule.run_on_editor_task!(function_, editor::Editor; wait::Bool = true)
    task = editor.loop_task
    if task === nothing || task === current_task()
        value = function_()
        return wait ? value : nothing
    end
    answer = wait ? Channel{Any}(1) : nothing
    post_operation!(editor, RunFunctionOperation(function_, answer))
    answer === nothing && return nothing
    succeeded, value = take!(answer)
    succeeded ? value : throw(value)
end

# The calls still in the inbox when the loop ends run here, on the task that ran
# the loop, where no frame runs any more. So a task that waits for one gets its
# answer and does not wait forever. An operation of another kind that was posted
# after the last frame is not applied.
function _answer_waiting_calls!(editor::Editor)
    while isready(editor.inbox)
        operation = take!(editor.inbox)
        operation isa RunFunctionOperation || continue
        try
            evaluate_operation(editor, operation)
        catch exception
            is_passthrough_exception(exception) && rethrow()
            record_fault!(editor.faults, :evaluate; origin = :RunFunctionOperation,
                          exception, traceback = catch_backtrace())
        end
    end
    nothing
end
