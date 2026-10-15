# Fragment of `EditorModule` — code units, and the held frames that the loop runs
# while one runs.

# ── Code units ──────────────────────────────────────────────────────────────
#
# A code unit is work whose length is not known before it starts: a run of the
# code tool, or the calls that other tasks posted. It runs on a thread of its own,
# and meanwhile it owns the documents and the state of the editor. The loop, on
# its own thread, runs held frames: they keep the window alive and read no cell.
# So one task at a time touches the documents: the loop before the unit starts and
# after it ends, and the unit between. The start of the task of the unit, and the
# `fetch` of the loop on that task once it is done, order the memory of the two
# threads.

# How many faults of held frames the loop keeps for one unit. A backend that fails
# in each held frame fails a hundred times a second, and the store keys them into
# one record anyway.
const _HELD_FAULT_LIMIT = 16

# How long a stop has no effect before the bar says so, and before a close asks
# whether to quit.
const _STOP_NOTICE_SECONDS = 3.0

"""
    run_code_unit!(function_, editor; parts) -> value

Run `function_()` as a code unit of `editor`, with the words `parts` for the busy
bar, and answer its value. An exception of `function_` is thrown again here.

When the loop of `editor` runs on the calling task, the unit runs on a task of
its own, on the first of these that the process has:

1. an interactive thread that neither the loop nor the main task uses, pinned
   there: no task of the default pool, such as a formula, background work or a
   task of model code, runs on it, so the unit never waits behind one;
2. with the loop on an interactive thread, any free thread of the default pool;
3. with the loop on a default thread, another default thread, pinned there.

Meanwhile the unit owns the documents and the state of `editor`, and the loop runs
held frames ([`run_held_frame!`](@ref)): the window answers, shows that the editor
is busy, and takes a stop or a close. In every other case, as with one thread,
with a backend that shows no held frames, in a test that runs the frames by hand,
inside a unit, or in background work, `function_` runs at once on the calling
task. [`find_code_unit_thread_notice`](@ref) says when a unit has no thread of its
own.

The stop control of the bar, and Escape while the bar shows, stop the unit
([`stop_code_unit!`](@ref)), and so does a first close of a window. A second
close, or a close after a stop that had no effect for 3 seconds, asks whether to
quit without a save, and its confirm throws `QuitEditorException` while the unit
still runs.
"""
function run_code_unit!(function_, editor::Editor; parts::Vector{String})
    (get_current_code_unit() === nothing && !is_in_background_work()) || return function_()
    unit = CodeUnit(parts)
    place = _find_editor_code_unit_place(editor)
    place === nothing && return run_as_code_unit(function_, unit)
    _prepare_held_frames!(editor, parts)
    task = _make_code_unit_task(place) do
        try
            (true, run_as_code_unit(function_, unit))
        catch exception
            (false, exception)
        finally
            # A unit that outlives a quit owns the cells until it ends.
            remove_cell_writer!(current_task())
            # Ends the wait of the held frame in progress; safe from any thread.
            Base.invokelatest(wake_backend!, editor.backend)
        end
    end
    unit.task = task
    @atomic editor.code_unit = unit
    add_cell_writer!(task)
    schedule(task)
    # A confirm to quit throws here and leaves the unit running, and its owner.
    _run_held_frames!(editor, unit, task)
    editor.frame_stages.held_seconds += time() - unit.started
    succeeded, value = fetch(task)
    @atomic editor.code_unit = nothing
    _end_held_frames!(editor)
    succeeded ? value : throw(value)
end

# The unit of an editor runs where `run_code_unit!` runs it.
ToolModule.run_in_code_unit(function_, editor::Editor; parts::Vector{String}) =
    run_code_unit!(function_, editor; parts)

# Where a unit of `editor` runs, only when the calling task runs the loop of a
# backend that shows held frames; `nothing` when the unit runs inline.
function _find_editor_code_unit_place(editor::Editor)
    editor.loop_task === current_task() || return nothing
    Base.invokelatest(shows_held_frames, editor.backend) || return nothing
    _find_code_unit_place(Threads.threadid())
end

# Where a unit of a loop on `loop_thread` runs, from the threads of the pools: the
# thread that it is pinned to, `:default` for any free thread of the default pool,
# or `nothing` when it runs inline. Thread 1 runs the main task: the loop, or the
# REPL that started the loop on another thread.
function _find_code_unit_place(loop_thread::Integer,
                               interactive = Threads.threadpooltids(:interactive),
                               default = Threads.threadpooltids(:default))
    for thread in interactive
        thread == loop_thread || thread == 1 || return thread
    end
    loop_thread in interactive && !isempty(default) && return :default
    for thread in default
        thread == loop_thread || return thread
    end
    nothing
end

# The task of a unit at `place`, not yet scheduled, so the unit owns the cells
# before it runs: pinned to a thread, or free on the default pool.
_make_code_unit_task(function_, thread::Integer) = _make_pinned_task(function_, thread)

function _make_code_unit_task(function_, pool::Symbol)
    task = Task(function_)
    task.sticky = false
    # The call by which `Threads.@spawn` gives a task its pool.
    Threads._spawn_set_thrpool(task, pool)
    task
end

"""
    find_code_unit_thread_notice(backend, loop_thread = Threads.threadid()) -> Union{String, Nothing}

A sentence for the person when a code unit of a loop on `loop_thread` that draws
on `backend` has no interactive thread of its own: the unit then shares the
default pool with formulas, background work and the tasks of model code, and can
wait behind a long computation, or it runs on the thread of the loop and holds the
window. It says how to start Julia. `nothing` when the unit has an interactive
thread of its own, and for a backend that shows no held frames, such as a video.

Call it on the task of the loop, as the start of a window does: the thread of the
loop decides which threads are free.
"""
function find_code_unit_thread_notice(backend, loop_thread::Integer = Threads.threadid())
    (backend !== nothing && Base.invokelatest(shows_held_frames, backend)) || return nothing
    place = _find_code_unit_place(loop_thread)
    place isa Integer && place in Threads.threadpooltids(:interactive) && return nothing
    # A loop on thread 1 needs one more interactive thread; a loop that a REPL
    # started on another thread needs two more.
    needed = loop_thread == 1 ? 2 : 3
    what = place === nothing ? "A tool call runs on the thread of the window and holds it." :
           "A tool call shares its thread with long computations and can wait behind them."
    string(what, " Start Julia with --threads=auto,", needed, ".")
end

# Whether the calling task owns the documents of `editor`: the task of its running
# code unit, or else the task of its loop.
function _is_editor_owner(editor::Editor)
    unit = @atomic editor.code_unit
    unit === nothing ? current_task() === editor.loop_task : current_task() === unit.task
end

# ── Held frames ─────────────────────────────────────────────────────────────

# The held frames of `unit`, until its task ends. Each frame answers what the
# person did: a stop, a close, or the confirm to quit (decisions D3 and D4 of
# plan/done/the-editor-always-answers-the-person.md).
function _run_held_frames!(editor::Editor, unit::CodeUnit, task::Task)
    stopped_at = nothing
    closes = 0
    is_quit_asked = false
    while !istaskdone(task)
        now = time()
        is_stop_pending = stopped_at !== nothing && now - stopped_at >= _STOP_NOTICE_SECONDS
        state = HeldFrameState(now - unit.started, unit.part[], is_stop_pending, is_quit_asked)
        answer = _run_held_frame(editor, state)
        if answer === :stop
            stop_code_unit!(unit)
            stopped_at === nothing && (stopped_at = now)
        elseif answer === :close
            closes += 1
            if stopped_at === nothing
                stop_code_unit!(unit)
                stopped_at = now
            elseif closes >= 2 || now - stopped_at >= _STOP_NOTICE_SECONDS
                is_quit_asked = true
            end
        elseif answer === :quit && is_quit_asked
            throw(QuitEditorException())
        end
    end
    nothing
end

# One held frame. A frame that throws counts as a frame in which the person did
# nothing, after a pause of one slice, so a backend that throws at once can not
# use all of a processor.
function _run_held_frame(editor::Editor, state::HeldFrameState)
    try
        # Through `invokelatest`, as every call of the backend protocol.
        Base.invokelatest(run_held_frame!, editor.backend, editor.devices, state)
    catch exception
        is_fault_exception(exception) || rethrow()
        _keep_held_fault!(editor, exception, catch_backtrace())
        sleep(0.01)
        :none
    end
end

function _prepare_held_frames!(editor::Editor, parts::Vector{String})
    try
        Base.invokelatest(prepare_held_frames!, editor.backend, editor.devices, parts)
    catch exception
        is_fault_exception(exception) || rethrow()
        _keep_held_fault!(editor, exception, catch_backtrace())
    end
    nothing
end

# After the unit: give the window its shape back, and hand the faults of the held
# frames to the store, which the loop owns again. Under a strict policy the first
# fault goes on to the caller, as any fault of a frame does.
function _end_held_frames!(editor::Editor)
    try
        Base.invokelatest(end_held_frames!, editor.backend, editor.devices)
    catch exception
        is_fault_exception(exception) || rethrow()
        _keep_held_fault!(editor, exception, catch_backtrace())
    end
    faults = copy(editor.held_faults)
    empty!(editor.held_faults)
    isempty(faults) && return nothing
    editor.fault_policy.is_barrier_enabled || throw(first(faults)[1])
    for (exception, traceback) in faults
        record_fault!(editor.faults, :device; origin = typeof(editor.backend), exception,
                      traceback)
    end
    nothing
end

_keep_held_fault!(editor::Editor, exception, traceback) =
    length(editor.held_faults) < _HELD_FAULT_LIMIT &&
        push!(editor.held_faults, (exception, traceback))
