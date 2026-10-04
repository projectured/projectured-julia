function test_process_debug()
@testset "ProcessDebug" begin

_binding(mod::Module, name::Symbol) = Base.invokelatest(getfield, mod, name)

# A context with everything the drain example calls, so a realized run has
# somewhere to send its items.
function _drain_context(name::Symbol)
    context = Module(name)
    # Realized code calls `process_at!` by name, so the runtime has to be in
    # scope wherever it is loaded — `realize_into` does this for the modules it
    # creates, and a test that loads the text by hand does it here.
    Base.include_string(context,
        "using ProjecturedProcess.ProcessModule: process_at!\n" *
        "const SENT = Any[]\nsend!(x) = push!(SENT, x)\n")
    context
end

# Wait for the process's task to actually reach its next probe. Waiting on
# `paused` alone would return immediately when it is already stopped — the
# resume has not been picked up yet — so the count is what says it moved.
function _wait_for_step(run, previous_count; timeout = 10.0)
    deadline = time() + timeout
    while time() < deadline
        run.trace.paused && run.trace.step_count > previous_count && return true
        istaskdone(run.task) && return false
        sleep(0.005)
    end
    false
end

# Every node index a run reaches, in order. The `on_step` hook is the
# embedder's seam, and recording through it is exactly what it is for.
function _visited(model, arguments...; context = Module(:ProcessVisitProbe), kwargs...)
    order = Int[]
    run = start_process(model, arguments...; context = context, kwargs...)
    run.trace.on_step = (trace, index) -> push!(order, index)
    wait(run.task)
    (order, run)
end

# ── instrumentation ──────────────────────────────────────────────────────
@testset "levels emit what they promise" begin
    model = make_process_drain_document_example()

    plain = realize_process_text(model)
    @test !occursin("process_at!", plain)
    @test !occursin("trace", plain)

    positioned = realize_process_text(model; instrumentation = :position)
    @test occursin("function drain(queue, trace = nothing)", positioned)
    @test occursin("process_at!(trace, ", positioned)
    @test !occursin("(; ", positioned)                    # no locals at this level
    @test (Meta.parseall(positioned); true)

    with_locals = realize_process_text(model; instrumentation = :locals)
    @test occursin("process_at!(trace, ", with_locals)
    @test occursin("queue = queue", with_locals)
    @test (Meta.parseall(with_locals); true)

    @test_throws Exception realize_process_text(model; instrumentation = :everything)
end

@testset "a probe carries only the variables that exist there" begin
    lines = split(realize_process_text(make_process_drain_document_example();
                                       instrumentation = :locals), "\n")
    inside = filter(l -> occursin("item = item", l), lines)
    @test !isempty(inside)                                # inside the loop it is in scope

    # After the loop Julia has dropped the iteration variable, so a probe that
    # still reported it would name a variable that does not exist.
    last_probe = last(filter(l -> occursin("process_at!", l), lines))
    @test occursin("sent = sent", last_probe)
    @test !occursin("item = item", last_probe)
end

# ── the Heisenbug guard ──────────────────────────────────────────────────
# Probes are additive and always in statement position, so instrumented and
# plain realizations cannot differ in behaviour. This is the assertion that
# keeps it that way.
@testset "instrumentation does not change what the process does" begin
    model = make_process_drain_document_example()
    results = map((:none, :position, :locals)) do level
        context = _drain_context(Symbol("ProcessLevel", level))
        Base.include_string(context, realize_process_text(model; instrumentation = level))
        f = _binding(context, :drain)
        (Base.invokelatest(f, Any[1, nothing, 2, 3]), copy(_binding(context, :SENT)))
    end
    @test results[1] == results[2] == results[3]
    @test results[1] == (3, Any[1, 2, 3])

    # An instrumented realization still runs standalone: no trace, no debugger,
    # no difference.
    context = _drain_context(:ProcessStandalone)
    Base.include_string(context, realize_process_text(model; instrumentation = :position))
    @test Base.invokelatest(_binding(context, :drain), Any[1, 2]) == 2
end

# ── where it is ──────────────────────────────────────────────────────────
@testset "a run reports every position it reaches" begin
    model = make_process_drain_document_example()
    seed = model.body.steps[1]
    loop = model.body.steps[2]
    guard = loop.body.steps[1]
    skip = guard.then_branch.steps[1]
    hand = loop.body.steps[2]
    tally = loop.body.steps[3]
    done = model.body.steps[3]
    index(node) = get_node_index(model, node)

    order, run = _visited(model, Any[7, nothing]; context = _drain_context(:ProcessOrderProbe))

    # The whole path, node by node: seed, the loop header, then one pass per
    # item — the second of which takes the `continue` branch — and the return.
    # The loop header is probed on entry and at the top of every iteration —
    # including the one a `continue` jumps to. It is not probed for the test
    # that fails and ends the loop, which is the one position a realized loop
    # does not report.
    @test order == [index(seed), index(loop),
                    index(loop), index(guard), index(hand), index(tally),
                    index(loop), index(guard), index(skip),
                    index(done)]
    @test run.trace.node == index(done)
    @test run.trace.step_count == length(order)
    @test fetch(run.task) == 1
end

# ── the bridge ───────────────────────────────────────────────────────────
@testset "the bridge carries the position into the session" begin
    model = make_process_drain_document_example()
    session = ProcessDebugSession()
    run = start_process(model, Any[1, 2]; context = _drain_context(:ProcessBridgeProbe),
                        session = session)
    wait(run.task)

    @test session.node_count == length(process_nodes(model))   # stamped at realization
    sync_process_debug!(session, run.trace, model)

    @test session.status === :finished
    @test session.node == get_node_index(model, model.body.steps[3])
    @test session.current === model.body.steps[3]              # resolved for the views
    @test session.step_count == run.trace.step_count

    # Detaching forgets the run but keeps the author's breakpoints.
    toggle_breakpoint!(session, model.body.steps[1])
    detach_process_debug!(session)
    @test session.status === :detached
    @test session.node == 0 && session.current === nothing
    @test length(session.breakpoints) == 1
end

# ── breakpoints and stepping ─────────────────────────────────────────────
# The process runs on its own task, so a breakpoint stops *it* while the
# editor keeps going. The bridge is what eventually lets it go.
@testset "a breakpoint stops the process, and the UI resumes it" begin
    model = make_process_drain_document_example()
    hand = _process_break_step(model)
    session = ProcessDebugSession()
    toggle_breakpoint!(session, hand)
    @test has_breakpoint(session, hand)

    run = start_process(model, Any[1, 2]; context = _drain_context(:ProcessBreakProbe),
                        session = session)
    # The breakpoints reach the runtime through the bridge, not through the
    # constructor: this is the push half of the sync.
    sync_process_debug!(session, run.trace, model)

    _wait_until(() -> run.trace.paused)
    @test run.trace.paused
    @test !istaskdone(run.task)                 # stopped, not finished

    sync_process_debug!(session, run.trace, model)
    @test session.status === :paused
    @test session.current === hand              # ...and the views know where

    # Continue: it runs to the same breakpoint on the next item.
    session.command = :continue
    sync_process_debug!(session, run.trace, model)
    _wait_until(() -> run.trace.paused)
    @test run.trace.node == get_node_index(model, hand)
    @test run.trace.step_count > 1

    session.command = :continue
    sync_process_debug!(session, run.trace, model)
    wait(run.task)
    sync_process_debug!(session, run.trace, model)
    @test session.status === :finished
    @test fetch(run.task) == 2
end

@testset "stepping walks one node at a time" begin
    model = make_process_drain_document_example()
    session = ProcessDebugSession()
    run = start_process(model, Any[1]; context = _drain_context(:ProcessStepProbe),
                        session = session, mode = :step)

    _wait_until(() -> run.trace.paused)
    sync_process_debug!(session, run.trace, model)
    @test session.status === :paused
    @test session.current === model.body.steps[1]      # the first node, not the last

    visited = Any[session.current]
    for _ in 1:3
        reached = run.trace.step_count
        session.command = :step
        sync_process_debug!(session, run.trace, model)
        @test _wait_for_step(run, reached)
        sync_process_debug!(session, run.trace, model)
        push!(visited, session.current)
    end
    @test visited == Any[model.body.steps[1], model.body.steps[2], model.body.steps[2],
                         model.body.steps[2].body.steps[1]]

    # Stop unwinds a stopped process instead of leaving the task hanging.
    session.command = :stop
    sync_process_debug!(session, run.trace, model)
    wait(run.task)
    @test istaskdone(run.task)
    @test fetch(run.task) === nothing                  # stopped, not returned
end

# ── staleness ────────────────────────────────────────────────────────────
# Edit the tree while a run is attached and every index means a different
# node. The session must show *no* position rather than a plausible wrong one.
@testset "an edit during a run makes the position stale" begin
    model = make_process_drain_document_example()
    session = ProcessDebugSession()
    run = start_process(model, Any[1]; context = _drain_context(:ProcessStaleProbe),
                        session = session)
    wait(run.task)
    sync_process_debug!(session, run.trace, model)
    @test session.status === :finished
    @test session.current !== nothing

    insert!(model.body.steps, 1, ProcessStep("a step that shifts every index"))
    @test is_stale(session, model)

    sync_process_debug!(session, run.trace, model)
    @test session.status === :stale
    @test session.node == 0
    @test session.current === nothing            # the views draw nothing at all
end

# ── the notation reflects it ─────────────────────────────────────────────
@testset "the notation shows where the process is" begin
    model = make_process_drain_document_example()
    hand = model.body.steps[2].body.steps[2]
    session = ProcessDebugSession()

    _text(projection) = print_document(
        ChainingProjection(RecursiveProjection(projection),
                           RecursiveProjection(SyntaxToText()),
                           RecursiveProjection(TextToString())), model).output
    _syntax(projection) = print_document(RecursiveProjection(projection), model).output
    _colored(syntax, color) =
        count(x -> x isa TextString && x.font_color === color,
              search_documents(syntax, x -> x isa TextString))

    plain = _text(ProcessToSyntax())
    live = _text(ProcessToSyntax(session = session))
    # No session, no difference — and with one, still no difference in the
    # *text*: the highlight is a style swap, so no caret offset moves.
    @test plain == live

    set_process_position!(session, model; node = get_node_index(model, hand), previous = 0)
    @test _text(ProcessToSyntax(session = session)) == plain

    # The live position takes the role of a warning, and a breakpoint the role of
    # an error.
    live_color = resolve_theme_color(ColorRole(:warning_text), Appearance())
    breakpoint_color = resolve_theme_color(ColorRole(:error_text), Appearance())

    # A node's whole keyword chrome takes the live colour: one leaf for a bare
    # keyword, and both quotes for a step that renders a description.
    @test _colored(_syntax(ProcessToSyntax()), live_color) == 0
    @test _colored(_syntax(ProcessToSyntax(session = session)), live_color) == 2

    set_process_position!(session, model; node = get_node_index(model, model.body.steps[2]),
                          previous = 0)
    @test _colored(_syntax(ProcessToSyntax(session = session)), live_color) == 1

    # A breakpoint colours its own keyword, in its own colour.
    toggle_breakpoint!(session, model.body.steps[1])      # a code-only step: `step`
    @test _colored(_syntax(ProcessToSyntax(session = session)), breakpoint_color) == 1

    # Where the run stands on a node that also has a breakpoint, the live
    # position wins — that is the one you need to see.
    toggle_breakpoint!(session, model.body.steps[2])
    @test _colored(_syntax(ProcessToSyntax(session = session)), live_color) == 1
    @test _colored(_syntax(ProcessToSyntax(session = session)), breakpoint_color) == 1
end

end # @testset "ProcessDebug"
end # test_process_debug

# The step a breakpoint is set on above: `hand it to the medium`, inside the loop.
_process_break_step(model) = model.body.steps[2].body.steps[2]

# Wait for something the process's own task has to do. Every use here is
# bounded by a timeout, so a design mistake fails the test instead of hanging
# the suite.
function _wait_until(predicate; timeout = 10.0)
    deadline = time() + timeout
    while !predicate() && time() < deadline
        sleep(0.005)
    end
    predicate()
end
