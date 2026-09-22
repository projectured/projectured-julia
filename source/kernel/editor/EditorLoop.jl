# Fragment of `EditorModule` — the loop itself: the per-frame counters log, one frame, and the waiting main loop.

# ── Performance logging ───────────────────────────────────────────────

"""
    perf!(editor::Editor)

Log reactive performance counters for the current frame. Only prints
when the editor processed a non-nothing operation.
"""
function perf!(editor::Editor)
    PERFORMANCE_COUNTERS_ENABLED || return
    editor.operation === nothing && return
    c = get_performance_counters()
    # The per-stage timing keys are the editor's own (recorded via `@performance_time`
    # below), not seeded by the reactive engine, so read them defensively: a frame
    # that ran no stage yet leaves them absent.
    rt = get(c, :read_time, 0) / 1e6
    et = get(c, :evaluate_time, 0) / 1e6
    pt = get(c, :print_time, 0) / 1e6
    # @info (not raw println) so this never writes to the global stdout the
    # assistant's `execute_julia_code` may have redirected to a now-closed pipe.
    @info "[perf] reads=$(c[:reads]) computes=$(c[:computes]) invalidations=$(c[:invalidations]) writes=$(c[:writes]) read=$(round(rt; digits=2))ms eval=$(round(et; digits=2))ms print=$(round(pt; digits=2))ms"
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
        has_input = @performance_time :read_time _run_barrier(editor, :read;
                                                              fallback = false) do
            read!(editor)
        end
        has_input || break
        @performance_time :evaluate_time evaluate!(editor)
        applied = editor.operation
        editor.iomap === nothing && break     # repaint before reading anything else
    end
    editor.operation = applied
    @performance_time :print_time _run_barrier(editor, :print;
                                               origin = typeof(editor.projection)) do
        print!(editor)
    end
    _consider_safe_mode!(editor)
end

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
clients can drive the editor; off by default.
"""
function run_editor!(editor::Editor; mcp::Bool=false,
              mcp_instructions::Union{AbstractString,Nothing}=nothing,
              on_start=nothing,
              fault_policy::FaultPolicy=FaultPolicy())
    # This is the moment the barriers go on. An `Editor` starts strict, so every
    # editor a test builds behaves as it does without this feature and a broken
    # projection fails its test. A loop a person sits in front of is the thing
    # that must survive instead, and this is that loop. Pass
    # `make_strict_fault_policy()` to run it without barriers. A barrier in the
    # projection reads the policy from the printer context, so a projection
    # printed under another policy prints again.
    editor.fault_policy == fault_policy || invalidate_projection!(editor)
    editor.fault_policy = fault_policy
    server = if mcp
        mcp_instructions === nothing ?
            make_agent_server(:mcp, editor) :
            make_agent_server(:mcp, editor; instructions=mcp_instructions)
    else
        nothing
    end
    server === nothing || start_agent_server!(server)
    # The editor exists now, and this is the first moment anything outside can
    # have it. What needs to reach a running editor — a driver that will post
    # its work, a watcher, a client — is handed it here, once, before any frame.
    on_start === nothing || on_start(editor)
    # Advance this editor's private animation clock once per frame; subscribers
    # via `get_reactive_clock_time(editor.clock)` re-evaluate on the next pull.
    # Logical time is wall-clock seconds since the loop started.
    t_start = Base.time()
    try
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
                set_clock_time!(editor.clock, frame_started - t_start)
                # What was posted or stored from outside this task, applied
                # here so the frame paints what its feeds just wrote.
                _run_barrier(editor, :evaluate) do
                    drain_feeds!(editor)
                end
                run_frame!(editor)
                _run_barrier(editor, :report) do
                    perf!(editor)
                    record_frame_measurements!(editor, Base.time() - frame_started)
                end
            end
        end
    catch e
        e isa QuitEditorException || rethrow()
    finally
        server === nothing || stop_agent_server!(server)
    end
end

"""
    run_editor!(backend::Backend, projection, document; mcp::Bool=false,
                mcp_instructions=nothing)

Bootstrap overload: initialise the backend, wire up an `Editor` with
the given projection and document, and run the read-eval-print loop
above. The pipeline is expected to produce a `ScreenDocument` so the
backend can reconcile native windows against it; pipelines whose
output is a bare `GraphicsCanvas` go unrendered (use `write_image`
for offscreen).

The native windows are opened before the first frame, by
`open_native_windows!`, which also corrects `document` to the geometry the
window system granted. A window system may grant less than it was asked for, and
it answers only once the window exists; a document projected before that answer
is projected at a size the window never has, and the answer then arrives as a
resize that computes the whole document again. `Editor.devices` only carries the
hardware kinds the editor needs: `Display`, `Keyboard`, `Mouse`.

Pass `mcp=true` to start an MCP server alongside the loop.

`devices` defaults to the full SDL hardware set (`Display`, `Keyboard`,
`Mouse`); backends that drive a different channel — e.g. the `ConsoleBackend`,
which has no native window or pointer — pass their own set (e.g.
`Device[Keyboard()]`).

`on_start(editor)` runs once, after the editor is built and before the first
frame. It is how something that will post operations gets hold of the editor to
post them to, since this overload is what constructs it.

`fault_policy` goes to the loop above. Pass `make_strict_fault_policy()` to stop
at the first fault instead of surviving it.
"""
function run_editor!(backend::Backend, projection, document; mcp::Bool=false,
              mcp_instructions::Union{AbstractString,Nothing}=nothing,
              devices::Vector{Device}=Device[Display(), Keyboard(), Mouse()],
              feeds::Vector{Feed}=Feed[],
              on_start=nothing,
              fault_policy::FaultPolicy=FaultPolicy())
    initialize_backend!(backend)
    try
        configure_devices!(backend, devices)
        # Before the first projection, so the document is laid out once, at the
        # size the window system granted rather than at the size it was asked
        # for. Nothing has read a cell yet, so the correction invalidates
        # nothing.
        open_native_windows!(backend, document)
        editor = Editor(backend, document, projection, devices; feeds = feeds)
        run_editor!(editor; mcp=mcp, mcp_instructions=mcp_instructions, on_start=on_start,
                    fault_policy=fault_policy)
    finally
        quit_backend!(backend)
    end
end
