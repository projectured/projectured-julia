# Fragment of `EditorModule` — the loop: `run_frame!`, `run_editor!` and `make_editor`.

# ── Performance logging ───────────────────────────────────────────────

"""
    _log_performance_counters!(editor::Editor)

Log the performance counters of the current frame: every count, and every time
in milliseconds, in name order. Logs only when the editor processed an
operation.
"""
function _log_performance_counters!(editor::Editor)
    PERFORMANCE_COUNTERS_ENABLED || return
    editor.operation === nothing && return
    counters = get_performance_counters()
    fields = String[]
    for key in sort!(collect(keys(counters.counts)))
        push!(fields, "$(key)=$(counters.counts[key])")
    end
    for key in sort!(collect(keys(counters.times)))
        push!(fields, "$(key)=$(round(counters.times[key] / 1e6; digits = 2))ms")
    end
    # Through the logger, so the line reaches every logger that the process
    # installed.
    @info "[perf] $(join(fields, ' '))"
end

# ── One frame ─────────────────────────────────────────────────────────

# How many operations one frame may apply before it must repaint. A pointer in
# motion delivers input for as long as it moves, so an unbounded drain would put
# off the repaint for as long as the reader keeps moving the mouse. The bound is
# what makes a frame finite. It is high enough that ordinary input never reaches
# it, and whatever is left waits for the next frame.
const MAX_OPERATIONS_PER_FRAME = 32

"""
    run_frame!(editor::Editor)

Run one read-eval-print frame: apply everything the backend has waiting, then
repaint once. `run_editor!` runs this once per tick; call it directly to drive an
editor one frame at a time — a test harness, an embedder, or a scripted timeline
that interleaves its own work between frames.

`run_read_stage!` answers one operation, so the frame loops it. Input arrives faster
than a frame can paint, and a frame that applied a single operation made a burst of
input cost one frame — plus one `sleep` — for each step in it. That is what made
a hover highlight fall behind a pointer crossing several widgets. At most
`MAX_OPERATIONS_PER_FRAME` operations are applied before the repaint.

An operation that dropped the cached projection (a whole-root swap calls
`invalidate_projection!`) ends the frame. `run_read_stage!` reads against the stored
IoMap and *discards* an input it has none for, so input behind such a swap has to wait
for the repaint that rebuilds the projection, or it would be thrown away.

A frame whose reads end before the input runs out, at the bound, at a read that
threw or at a dropped IoMap, sets `editor.wake_pending`. `run_editor!` then runs
the next frame without a wait, so the input that is left does not wait for new
input.

The loop leaves the last applied operation in `editor.operation`. `run_read_stage!`
clears that field when the input runs out, and `_log_performance_counters!` reads it
to tell a frame that did something from an idle one.
"""
function run_frame!(editor::Editor)
    # Every fault the last frame collected, shown before this one reads
    # anything. It belongs to the frame rather than to the loop above it: a
    # driver that steps frames by hand — a playback, a test — must collect its
    # faults too. It runs first because a write to a log document has to happen
    # outside every computation, and this is the one point in a frame that is.
    _run_barrier(editor, :report) do
        report_frame_faults!(editor)
    end
    applied = nothing
    # True until a read finds no input: the reads can also end at the bound, at a
    # read that threw, or at a dropped IoMap.
    is_input_left = true
    for _ in 1:MAX_OPERATIONS_PER_FRAME
        # A reader that throws is a reader that declined: the gesture is lost,
        # the frame goes on, and the fault says which reader lost it.
        has_input = @measure_performance_time :read_time begin
            _run_barrier(editor, :read; fallback = _BARRIER_FAILED) do
                run_read_stage!(editor)
            end
        end
        has_input === _BARRIER_FAILED && break
        if !has_input
            is_input_left = false
            break
        end
        @measure_performance_time :evaluate_time run_evaluate_stage!(editor)
        applied = editor.operation
        editor.iomap === nothing && break     # repaint before reading anything else
    end
    # Input can wait in the backend, or a gesture in the recognizer, so the next
    # turn of the loop runs a frame without a wait.
    is_input_left && (editor.wake_pending[] = true)
    editor.operation = applied
    # Outside the paint, so a part that prints again shows in this frame.
    editor.is_retry_pending && _retry_marked_barriers!(editor)
    @measure_performance_time :print_time begin
        _run_barrier(editor, :print; origin = typeof(editor.projection)) do
            run_print_stage!(editor)
        end
    end
    _consider_safe_mode!(editor)
end

"""
    get_frame_clock_time(backend, wall_time) -> Float64

The time that the editor's clock shows in a frame, in seconds. `wall_time` is
the wall-clock time since the loop started, and a backend answers it unless it
keeps a time of its own: a recorder that keeps video time answers the time of
the frame it is about to write, so an animation moves one frame of time per
frame, however long the frame took to make.
"""
get_frame_clock_time(backend, wall_time) = wall_time

# ── Main loop ──────────────────────────────────────────────────────────

"""
    run_editor!(editor::Editor; mcp = false, fault_policy = editor.fault_policy)

Execute the read-eval-print loop. Between frames the editor sleeps in
`wait_for_input`, and three things end the sleep: an input event, a
[`wake_editor!`](@ref) from any task, or the timeout
[`compute_wait_timeout`](@ref) answers — the animation bound while the clock
has subscribers, the nearest feed deadline, else never. Each frame:
`drain_feeds!` moves what producers posted or stored from outside — the
inbox first, then every registered feed — then `run_frame!` applies every
operation the backend has waiting and repaints once. `run_read_stage!` internally
swallows envelopes that don't translate to an operation, so no outer drain
is needed. An editor with no IoMap, as `Editor(…)` makes it, prints once before
its first frame, so the first frame reads its input against an IoMap.

A backend without a real wait sleeps one 10 ms poll slice per call (the
`BackendDefaults` fallback), which also gives cooperative `@async` tasks
(e.g. the MCP server, a simulation driver) their turn on this thread. A frame
that does not wait, because a wake is pending or a deadline is due, yields once
for the same reason.

`mcp` starts an MCP server alongside the loop, so external clients can drive
the editor; off by default. Its value is `true` for the server's own defaults,
or a `NamedTuple` of `instructions`, `host` and `port`, and a field that is left
out takes the server's default.

When the loop ends, it answers the calls that wait in the inbox, runs the stop
steps of the editor, stops the server and quits the backend it ran on. Each of these steps runs also when the loop or a
step before it throws. The first exception goes on to the caller: the exception of
the loop, or else the first exception of a step.
`fault_policy` defaults to the editor's own. Every form that makes an editor
starts it strict, and a program that a person starts passes `FaultPolicy()`.
"""
function run_editor!(editor::Editor; mcp::Union{Bool,NamedTuple}=false,
              fault_policy::FaultPolicy=editor.fault_policy)
    server = nothing
    has_quit = false
    try
        # A barrier in the projection reads from the printer context whether it
        # catches, so a projection printed under another `is_barrier_enabled`
        # prints again. A report reads the log and the sound flags from the editor.
        editor.fault_policy.is_barrier_enabled == fault_policy.is_barrier_enabled ||
            invalidate_projection!(editor)
        editor.fault_policy = fault_policy
        # From here on, a call that another task makes through
        # `run_on_editor_task!` runs in a frame of this task.
        editor.loop_task = current_task()
        # The server renders the tool set when it starts, so it starts here:
        # a tool that the caller declares between `make_editor` and this call
        # reaches a client too.
        server = mcp === false ? nothing : _make_mcp_server(editor, mcp)
        server === nothing || start_agent_server!(server)
        # An editor that has no IoMap prints once before its first frame, because
        # `run_read_stage!` drops an input that no IoMap can read.
        if editor.iomap === nothing
            _run_barrier(editor, :print; origin = typeof(editor.projection)) do
                run_print_stage!(editor)
            end
        end
        # Advance this editor's private animation clock once per frame;
        # subscribers via `get_reactive_clock_time(editor.clock)` re-evaluate
        # on the next pull. Logical time is the time of the frame that
        # `get_frame_clock_time` answers: wall-clock seconds since the loop
        # started, unless the backend keeps a time of its own. The times come
        # from the monotonic clock, so a step of the system clock moves no
        # animation and no frame time.
        t_start = time_ns()
        while true
            # A wake posted since the last frame took ownership skips the
            # wait: the flag is the truth, whatever became of the backend
            # kick. The wait itself ends on input, on a kick, or at the
            # timeout — and a backend with no wait of its own polls in 10 ms
            # slices here, exactly as this loop did when it slept. A frame
            # that does not wait yields once, because the wait is where the
            # cooperative tasks of this thread get their turn.
            timeout = editor.wake_pending[] ? 0.0 : compute_wait_timeout(editor)
            if timeout > 0
                wait_for_input(editor.backend, editor.devices, timeout)
            else
                yield()
            end
            # The frame takes ownership of every wake posted before it;
            # a wake that arrives from here on belongs to the next frame.
            Threads.atomic_xchg!(editor.wake_pending, false)
            # A fresh per-frame counter store, bound for this frame's dynamic extent; the
            # cell operations below count into it and `_log_performance_counters!` reads
            # it.
            frame_started = time_ns()
            run_with_performance_counters() do
                wall_time = (frame_started - t_start) / 1e9
                # A backend whose time throws is recorded, and the frame shows
                # the wall time.
                clock_time = _run_barrier(editor, :device;
                                          origin = typeof(editor.backend),
                                          fallback = wall_time) do
                    get_frame_clock_time(editor.backend, wall_time)
                end
                set_clock_time!(editor.clock, clock_time)
                # What was posted or stored from outside this task, applied
                # here so the frame paints what its feeds just wrote. Each feed
                # drains in a barrier of its own.
                drain_feeds!(editor)
                run_frame!(editor)
                _run_barrier(editor, :report) do
                    _log_performance_counters!(editor)
                    record_frame_performance!(editor, (time_ns() - frame_started) / 1e9)
                end
            end
        end
    catch e
        e isa QuitEditorException || rethrow()
        has_quit = true
    finally
        editor.loop_task = nothing
        exception = _end_editor_loop!(editor, server)
        # An exception of the loop goes on, so the exception of a step goes on
        # only after a quit.
        has_quit && exception !== nothing && throw(exception)
    end
end

# The steps at the end of the loop. Each step runs also when a step before it
# throws, and the answer is the first exception of a step, or `nothing`.
function _end_editor_loop!(editor::Editor, server)
    first_exception = nothing
    for step in (() -> _answer_waiting_calls!(editor),
                 (() -> stop_step(editor) for stop_step in editor.stop_steps)...,
                 () -> server === nothing || stop_agent_server!(server),
                 () -> quit_backend!(editor.backend))
        try
            step()
        catch exception
            first_exception === nothing && (first_exception = exception)
        end
    end
    first_exception
end

# The server gets the options that the caller gave. An option that is left out,
# or that is `nothing`, takes the server's own default.
function _make_mcp_server(editor::Editor, mcp::Union{Bool,NamedTuple})
    options = mcp === true ? (;) : mcp
    for name in keys(options)
        name in (:instructions, :host, :port) ||
            error("The argument `mcp` has no field `$(name)`. Its fields are instructions, ",
                  "host and port.")
    end
    make_agent_server(:mcp, editor;
                      (name => value for (name, value) in pairs(options)
                       if value !== nothing)...)
end

"""
    make_editor(document::Document, projection; backend::Backend,
                devices = Device[Display(), Keyboard(), Mouse()], feeds = Feed[],
                fault_policy = make_strict_fault_policy()) -> Editor

Start `backend`, open the native windows of `document`, build the `Editor`, and
print it once, so the editor has its iomap and the window shows the document.
It runs no frame, so it reads no input. It applies no wrapper and chooses no
backend: [`build_editor`](@ref) does both and then calls this function.

Use it when there is work to do before the loop runs: attach a log, declare an
API, start a driver, or work on the document with a verb that reads through the
readers of the editor. Then run the loop with [`run_editor!`](@ref), which quits
the backend when the loop ends.

# Example

    editor = make_editor(document, projection; backend)
    attach_fault_target!(editor.faults, log)
    run_editor!(editor)

The native windows are opened before the print, by `open_native_windows!`,
which also corrects `document` to the geometry the window system granted. A
window system may grant less than it was asked for, and it answers only once the
window exists; a document printed before that answer is printed at a size the
window never has, and the answer then arrives as a resize that computes the
whole document again. `devices` defaults to a display, a keyboard and a mouse; a
backend that drives another channel passes its own set (e.g. `Device[Keyboard()]`).

`fault_policy` is strict by default: the editor stops at its first fault, so a
test that forgets the keyword fails loudly. A program that a person starts passes
`FaultPolicy()` on purpose, and then the loop survives a fault; the one print
runs under the policy already. When the build or the print fails, the backend is
quit and the error goes on to the caller, also when the quit throws.
"""
function make_editor(document::Document, projection; backend::Backend,
                     devices::Vector{Device}=_make_default_devices(),
                     feeds::Vector{Feed}=Feed[],
                     fault_policy::FaultPolicy=make_strict_fault_policy())
    initialize_backend!(backend)
    try
        configure_devices!(backend, devices)
        # A wrapper around the screen, such as the state of a tracker, is not
        # drawn: the backend opens the windows of the screen inside it.
        open_native_windows!(backend, get_wrapped_document(document))
        editor = Editor(document, projection; backend = backend, devices = devices,
                        feeds = feeds, fault_policy = fault_policy)
        _run_barrier(editor, :print; origin = typeof(editor.projection)) do
            run_print_stage!(editor)
        end
        return editor
    catch
        # The error of the build goes on, so an exception of the quit is dropped.
        try
            quit_backend!(backend)
        catch exception
            is_passthrough_exception(exception) && rethrow()
        end
        rethrow()
    end
end

"""
    run_editor!(document::Document, projection; wait = true, mcp = false, keywords...)
    run_editor!(document::Document; ...)

The one call for a caller with no work before the loop: [`build_editor`](@ref)
with `keywords`, then the loop above with `mcp`. A caller with work to do before
the loop — a driver that posts its work, a watcher, a tool it declares — calls
`build_editor` or `make_editor`, does that work with the editor, and then calls
`run_editor!(editor)`; with `wait = false`, it puts that work into the function
that `run_editor!(make; wait = false)` calls on the task of the loop.

With `wait = false` the call returns the editor at once, and the editor runs on
a task of its own: a task pinned to a thread of the default pool that is not the
thread of the caller, or an `@async` task when the process has no such thread.
The task builds the editor too, because a backend such as SDL answers only the
thread that started it. The loop's task is `editor.loop_task`, from the moment
the call returns until the loop ends. The loop keeps the world of its start, so a
function that the caller defines later is too new for it: a call that the caller
posts with `run_on_editor_task!` goes through `Base.invokelatest`.
"""
function run_editor!(document::Document, projection; wait::Bool = true,
                     mcp::Union{Bool,NamedTuple} = false, keywords...)
    make = () -> build_editor(document, projection; keywords...)
    wait ? run_editor!(make(); mcp) : _start_editor_task(make, mcp)
end

function run_editor!(document::Document; wait::Bool = true,
                     mcp::Union{Bool,NamedTuple} = false, keywords...)
    make = () -> build_editor(document; keywords...)
    wait ? run_editor!(make(); mcp) : _start_editor_task(make, mcp)
end

"""
    run_editor!(make::Function; wait = true, mcp = false)

The loop of the editor that `make()` answers, for a caller whose work before the
loop must run on the task of the loop. `make` builds the editor, does that work
with it, such as a tool it declares or a pane it opens, and answers the editor.

With `wait = false` the task of the loop calls `make`, as the form above calls
`build_editor`, and the call returns the editor once `make` returns. With
`wait = true` the calling task calls `make` and then runs the loop. An exception
of `make` goes to the caller in both cases.
"""
run_editor!(make::Function; wait::Bool = true, mcp::Union{Bool,NamedTuple} = false) =
    wait ? run_editor!(make(); mcp) : _start_editor_task(make, mcp)

# Build the editor with `make` on a task of its own and run its loop there, and
# answer the editor once it is built. An error of the build goes to the caller.
function _start_editor_task(make, mcp)
    made = Channel{Any}(1)
    function run_loop()
        editor = try
            make()
        catch exception
            put!(made, exception)
            return
        end
        editor.loop_task = current_task()
        put!(made, editor)
        run_editor!(editor; mcp)
    end
    thread = _find_editor_thread()
    task = thread === nothing ? (@async run_loop()) : _spawn_pinned(run_loop, thread)
    errormonitor(task)
    editor = take!(made)
    editor isa Exception && throw(editor)
    editor
end

# A thread of the default pool that is not the thread of the caller, or `nothing`
# when the process has no such thread.
function _find_editor_thread()
    current = Threads.threadid()
    candidates = [thread for thread in Threads.threadpooltids(:default) if thread != current]
    isempty(candidates) ? nothing : last(candidates)
end

# Run `f` in a task that never moves from thread `thread`: a sticky task, pinned
# with the internal call that `Threads.@threads :static` makes.
function _spawn_pinned(f, thread::Int)
    task = Task(f)
    task.sticky = true
    ccall(:jl_set_task_tid, Cint, (Any, Cint), task, thread - 1) == 1 ||
        error("The editor task could not be pinned to thread ", thread, ".")
    schedule(task)
    task
end
