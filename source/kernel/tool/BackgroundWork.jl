# Fragment of `ToolModule` — background work: code that runs on a task of the
# default pool while its editor goes on with its frames, and reaches documents
# only through the verbs.

"""
    BackgroundWork

Code that runs on a task of the default pool while its editor goes on with its
frames, as [`start_background_work`](@ref) starts it. The work owns no document:
it reaches one through the verbs, which post their calls to the editor and wait
while the window answers. A write of a cell that a computation of the editor
reads is reported as a fault of the editor; a read races with no report.

`fetch(work)` answers the value of the work, or throws its exception, and
[`stop_background_work!`](@ref) stops it as a stop stops a code unit.
[`is_background_work_done`](@ref) says whether it ended.

Work that a running code unit starts keeps a link to that unit. While the unit
runs, a call of a verb from the work that waits for the editor throws
`CodeUnitWaitException`, and a `fetch` of the work from the unit throws
[`BackgroundWorkWaitException`](@ref): the unit holds the documents of the editor,
so the two would wait for each other.
"""
mutable struct BackgroundWork
    description::String
    parent::Union{CodeUnit, Nothing}
    stop::Threads.Atomic{Bool}
    steps::Vector{Any}
    lock::ReentrantLock
    task::Union{Task, Nothing}
end

function Base.show(io::IO, work::BackgroundWork)
    state = !istaskdone(work.task) ? "runs" :
            istaskfailed(work.task) ? "failed" : "done"
    print(io, "BackgroundWork(", repr(work.description), ", ", state, ")")
end

"""
    BackgroundWorkWaitException(description)

The code unit that started the background work `description` asked for its value
while the unit runs. The work reaches documents through the editor, which waits
for the unit, so the wait could never end. It throws at once instead.

Let the unit end first: answer the work as the value of the code, or run the
code with `background = true`.
"""
struct BackgroundWorkWaitException <: Exception
    description::String
end

Base.showerror(io::IO, exception::BackgroundWorkWaitException) =
    print(io, "BackgroundWorkWaitException: the code unit that started the background ",
          "work \"", exception.description, "\" can not wait for it while the unit runs, ",
          "because the work reaches documents through the editor, which waits for the ",
          "unit. Answer the work as the value of the code, or run the code with ",
          "`background = true`.")

"""
    start_background_work(function_; description = "background work",
                          editor = get_evaluation_editor(),
                          parent = get_current_code_unit(), is_sticky = false) -> BackgroundWork

Run `function_()` on a task of the default pool, and answer at once. The work
runs with `editor` as the editor of the evaluation, so a verb that it calls with
no editor takes `editor`. `description` names the work.

`parent` is the code unit that the work belongs to: by default the unit that the
calling code runs in. While that unit runs, the work can not wait for the editor,
and the unit can not wait for the work. Give `nothing` for work that the unit
does not wait for, such as the run of a tool call or a turn of an agent.

With `is_sticky`, the work runs on the thread of the calling task, as an `@async`
task does, and never at the same time as that task. Its stop and its waits are
those of any work.

Use it for code that does not need the documents of the editor, such as a long
computation or a wait for a process: the window answers meanwhile. The work
reaches a document only through the verbs.

# Example

    # One call of the code tool starts the work and ends at once.
    work = start_background_work(() -> sum(abs2, rand(10^8)); description = "a long sum")
    # A later call reads its value.
    fetch(work)
"""
function start_background_work(function_; description::AbstractString = "background work",
                               editor = get_evaluation_editor(),
                               parent::Union{CodeUnit, Nothing} = _CURRENT_CODE_UNIT[],
                               is_sticky::Bool = false)
    work = BackgroundWork(String(description), parent, Threads.Atomic{Bool}(false),
                          Any[], ReentrantLock(), nothing)
    # The parent is the code unit of the work, so a call of a verb from it throws
    # while that unit runs; its waits end at its own stop.
    run_work() = with(function_, _CURRENT_CODE_UNIT => parent, _CURRENT_STOP_SCOPE => work,
                      _EVALUATION_EDITOR => editor)
    work.task = is_sticky ? (@async run_work()) : (Threads.@spawn :default run_work())
    work
end

function Base.fetch(work::BackgroundWork)
    # The code of the unit and its tasks run in the stop scope of the unit; other
    # work that the unit started runs in its own.
    parent = work.parent
    parent !== nothing && !parent.ended[] && _CURRENT_STOP_SCOPE[] === parent &&
        throw(BackgroundWorkWaitException(work.description))
    try
        fetch(work.task)
    catch exception
        exception isa TaskFailedException || rethrow()
        throw(exception.task.exception)
    end
end

"""
    stop_background_work!(work) -> Nothing

Stop `work`: set its stop flag, and run each stop step that its waits attached,
as [`stop_code_unit!`](@ref) does for a unit. The `sleep` of the code tool and our
own waits end with `InterruptException`; code that computes runs to its end,
because Julia can not stop code that runs. It does not wait for the work.
"""
stop_background_work!(work::BackgroundWork) = _stop_scope!(work)

"""
    is_in_background_work() -> Bool

Whether the calling code runs in background work, or in a task that the work
started. Such code owns no document, so it never runs as a code unit: a call that
would start a unit runs at once.
"""
is_in_background_work() = _CURRENT_STOP_SCOPE[] isa BackgroundWork

"""
    is_background_work_done(work) -> Bool

Whether `work` ended, with a value or with an exception.
"""
is_background_work_done(work::BackgroundWork) = istaskdone(work.task)
