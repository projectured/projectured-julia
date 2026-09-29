# Fragment of `EditorModule` — the loop: the counter log, one frame,
# `get_frame_clock_time`, the waiting main loop, and `make_editor`.

# ── Performance logging ───────────────────────────────────────────────

"""
    perf!(editor::Editor)

Log the performance counters of the current frame: every count, and every time
in milliseconds, in name order. Logs only when the editor processed an
operation.
"""
function perf!(editor::Editor)
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

`read!` answers one operation, so the frame loops it. Input arrives faster than a
frame can paint, and a frame that applied a single operation made a burst of
input cost one frame — plus one `sleep` — for each step in it. That is what made
a hover highlight fall behind a pointer crossing several widgets. At most
`MAX_OPERATIONS_PER_FRAME` operations are applied before the repaint.

An operation that dropped the cached projection (a whole-root swap calls
`invalidate_projection!`) ends the frame. `read!` reads against the stored IoMap
and *discards* an input it has none for, so input behind such a swap has to wait
for the repaint that rebuilds the projection, or it would be thrown away.

The loop leaves the last applied operation in `editor.operation`. `read!` clears
that field when the input runs out, and `perf!` reads it to tell a frame that did
something from an idle one.
"""
function run_frame!(editor::Editor)
    # Every fault the last frame collected, shown before this one reads
    # anything. It belongs to the frame rather than to the loop above it: a
    # driver that steps frames by hand — a playback, a test — must collect its
    # faults too. It runs first because a write to a log document has to happen
    # outside every thunk, and this is the one point in a frame that is.
    _run_barrier(editor, :report) do
        report_frame_faults!(editor)
    end
    applied = nothing
    for _ in 1:MAX_OPERATIONS_PER_FRAME
        # A reader that throws is a reader that declined: the gesture is lost,
        # the frame goes on, and the fault says which reader lost it.
        has_input = @measure_performance_time :read_time begin
            _run_barrier(editor, :read; fallback = false) do
                read!(editor)
            end
        end
        has_input || break
        @measure_performance_time :evaluate_time evaluate!(editor)
        applied = editor.operation
        editor.iomap === nothing && break     # repaint before reading anything else
    end
    editor.operation = applied
    @measure_performance_time :print_time begin
        _run_barrier(editor, :print; origin = typeof(editor.projection)) do
            print!(editor)
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
    run_editor!(editor::Editor; mcp::Bool=false)

Execute the read-eval-print loop. Between frames the editor sleeps in
`wait_for_input`, and three things end the sleep: an input event, a
[`wake_editor!`](@ref) from any task, or the timeout
[`compute_wait_timeout`](@ref) answers — the animation bound while the clock
has subscribers, the nearest feed deadline, else never. Each frame:
`drain_feeds!` moves what producers posted or stored from outside — the
inbox first, then every registered feed — then `run_frame!` applies every
operation the backend has waiting and repaints once. `read!` internally
swallows envelopes that don't translate to an operation, so no outer drain
is needed.

A backend without a real wait sleeps one 10 ms poll slice per call (the
`BackendDefaults` fallback), which also gives cooperative `@async` tasks
(e.g. the MCP server, a simulation driver) their turn on this thread.

When `mcp=true`, an MCP server is started alongside the loop so external
clients can drive the editor; off by default. `mcp_instructions`, `mcp_host` and
`mcp_port` go to the server, and each one that is `nothing` takes the server's
own default.

When the loop ends, it quits the backend it ran on, also when it throws.
`fault_policy` defaults to the editor's own: an editor that [`make_editor`](@ref)
made already prints under the policy of its loop, and an editor a test builds
with `Editor(…)` stays strict.
"""
function run_editor!(editor::Editor; mcp::Bool=false,
              mcp_instructions::Union{AbstractString,Nothing}=nothing,
              mcp_host::Union{AbstractString,Nothing}=nothing,
              mcp_port::Union{Integer,Nothing}=nothing,
              fault_policy::FaultPolicy=editor.fault_policy)
    server = nothing
    try
        # A barrier in the projection reads the policy from the printer context,
        # so a projection printed under another policy prints again.
        editor.fault_policy == fault_policy || invalidate_projection!(editor)
        editor.fault_policy = fault_policy
        # From here on, a call that another task makes through
        # `run_on_editor_task!` runs in a frame of this task.
        editor.loop_task = current_task()
        # The server renders the tool set when it starts, so it starts here:
        # a tool that the caller declares between `make_editor` and this call
        # reaches a client too.
        server = mcp ? _make_mcp_server(editor, mcp_instructions, mcp_host, mcp_port) :
                       nothing
        server === nothing || start_agent_server!(server)
        # Advance this editor's private animation clock once per frame;
        # subscribers via `get_reactive_clock_time(editor.clock)` re-evaluate
        # on the next pull. Logical time is the time of the frame that
        # `get_frame_clock_time` answers: wall-clock seconds since the loop
        # started, unless the backend keeps a time of its own.
        t_start = Base.time()
        while true
            # A wake posted since the last frame took ownership skips the
            # wait: the flag is the truth, whatever became of the backend
            # kick. The wait itself ends on input, on a kick, or at the
            # timeout — and a backend with no wait of its own polls in 10 ms
            # slices here, exactly as this loop did when it slept.
            if !editor.wake_pending[]
                timeout = compute_wait_timeout(editor)
                timeout > 0 && wait_for_input(editor.backend, editor.devices, timeout)
            end
            # The frame takes ownership of every wake posted before it;
            # a wake that arrives from here on belongs to the next frame.
            Threads.atomic_xchg!(editor.wake_pending, false)
            # A fresh per-frame counter store, bound for this frame's dynamic
            # extent; the cell operations below count into it and `perf!` reads it.
            frame_started = Base.time()
            with_performance_counters() do
                wall_time = frame_started - t_start
                # A backend whose time throws is recorded, and the frame shows
                # the wall time.
                clock_time = _run_barrier(editor, :device; origin = typeof(editor.backend),
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
                    perf!(editor)
                    record_frame_performance!(editor, Base.time() - frame_started)
                end
            end
        end
    catch e
        e isa QuitEditorException || rethrow()
    finally
        editor.loop_task = nothing
        _answer_waiting_calls!(editor)
        server === nothing || stop_agent_server!(server)
        quit_backend!(editor.backend)
    end
end

# The server gets the settings the caller gave, and a setting that is `nothing` is
# left out, so the server's own default answers for it.
function _make_mcp_server(editor::Editor, instructions, host, port)
    settings = (; instructions, host, port)
    make_agent_server(:mcp, editor;
                      (name => value for (name, value) in pairs(settings)
                       if value !== nothing)...)
end

"""
    make_editor(backend::Backend, projection, document::Document;
                devices = Device[Display(), Keyboard(), Mouse()], feeds = Feed[],
                fault_policy = FaultPolicy()) -> Editor

Start `backend`, open the native windows of `document`, build the `Editor`, and
print it once, so the editor has its iomap and the window shows the document.
It runs no frame, so it reads no input.

Use it when there is work to do before the loop runs: attach a log, declare an
API, start a driver, or work on the document with a verb that reads through the
readers of the editor. Then run the loop with [`run_editor!`](@ref), which quits
the backend when the loop ends.

# Example

    editor = make_editor(backend, projection, document)
    attach_fault_target!(editor.faults, log)
    run_editor!(editor)

The native windows are opened before the print, by `open_native_windows!`,
which also corrects `document` to the geometry the window system granted. A
window system may grant less than it was asked for, and it answers only once the
window exists; a document printed before that answer is printed at a size the
window never has, and the answer then arrives as a resize that computes the
whole document again. `devices` defaults to the full SDL hardware set; a backend
that drives another channel, such as the `ConsoleBackend`, passes its own set
(e.g. `Device[Keyboard()]`).

`fault_policy` is the policy of a loop a person sits in front of, which survives
a fault; the one print runs under it already. Pass `make_strict_fault_policy()`
to stop at the first fault. When the build or the print fails, the backend is
quit before the error goes on.
"""
function make_editor(backend::Backend, projection, document::Document;
                     devices::Vector{Device}=Device[Display(), Keyboard(), Mouse()],
                     feeds::Vector{Feed}=Feed[],
                     fault_policy::FaultPolicy=FaultPolicy())
    initialize_backend!(backend)
    try
        configure_devices!(backend, devices)
        open_native_windows!(backend, document)
        editor = Editor(backend, document, projection, devices;
                        feeds = feeds, fault_policy = fault_policy)
        _run_barrier(editor, :print; origin = typeof(editor.projection)) do
            print!(editor)
        end
        return editor
    catch
        quit_backend!(backend)
        rethrow()
    end
end

"""
    run_editor!(backend::Backend, projection, document; mcp::Bool=false,
                mcp_instructions=nothing, mcp_host=nothing, mcp_port=nothing)

The one call for a caller with no work before the loop: [`make_editor`](@ref),
then the loop above. The pipeline is expected to produce a `ScreenDocument` so
the backend can reconcile native windows against it; pipelines whose output is
a bare `GraphicsCanvas` go unrendered (use `write_image` for offscreen).

Pass `mcp=true` to start an MCP server alongside the loop, and `mcp_host` and
`mcp_port` to say where it listens. `devices`, `feeds` and `fault_policy` go to
`make_editor`.

A caller with work to do before the loop — a driver that posts its work, a
watcher, a tool it declares — calls `make_editor`, does that work with the
editor, and then calls `run_editor!(editor)`.
"""
function run_editor!(backend::Backend, projection, document; mcp::Bool=false,
              mcp_instructions::Union{AbstractString,Nothing}=nothing,
              mcp_host::Union{AbstractString,Nothing}=nothing,
              mcp_port::Union{Integer,Nothing}=nothing,
              devices::Vector{Device}=Device[Display(), Keyboard(), Mouse()],
              feeds::Vector{Feed}=Feed[],
              fault_policy::FaultPolicy=FaultPolicy())
    editor = make_editor(backend, projection, document;
                         devices = devices, feeds = feeds, fault_policy = fault_policy)
    run_editor!(editor; mcp=mcp, mcp_instructions=mcp_instructions,
                mcp_host=mcp_host, mcp_port=mcp_port)
end
