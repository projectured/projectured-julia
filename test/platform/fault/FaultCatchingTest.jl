# The barrier inside the pipeline.
#
# The property under test is containment: a printer that fails on one node costs
# that node and nothing else. The tree still draws, the mark keeps the slot, and
# the fault is collected once however many times the thunk runs.
#
# The failure is raised from inside the output cell rather than from
# `print_document`, because that is where a real printer fails. A printer builds
# a graph of thunks and returns; it throws later, while the renderer pulls the
# output. A barrier that only wraps the call to `print_document` catches none of
# this, and a test that raises from the call would not notice.


@document struct FaultProbeLeaf
    value::Int = 0
end

@document struct FaultProbeBranch
    children::CollectionDocument = CellVector()
end

# Fails on every odd leaf, and only when the output cell is read.
struct OddLeafBreaker <: Projection end

ProjectionModule.print_document(::OddLeafBreaker, recursion, leaf::FaultProbeLeaf, ctx) =
    SimpleIoMap(nothing, leaf,
                Cell(@computation(isodd(leaf.value) ?
                            error("leaf $(leaf.value) is odd") :
                            SyntaxLeaf(TextString(string(leaf.value))))))

ProjectionModule.read_intent(::OddLeafBreaker, recursion, change::Intent, iomap) = change
ProjectionModule.map_reference_forward(::OddLeafBreaker, iomap, reference) = nothing
ProjectionModule.map_reference_backward(::OddLeafBreaker, iomap, reference) = nothing

struct FaultProbeBranchToSyntax <: Projection end

function ProjectionModule.print_document(p::FaultProbeBranchToSyntax, recursion,
                                         branch::FaultProbeBranch, ctx)
    child_iomaps = [print_child(recursion, branch.children[index],
                                make_child_context(ctx, ElementReferenceStep(index - 1)))
                    for index in 1:length(branch.children)]
    SimpleIoMap(p, branch,
                SyntaxNode(() -> Any[iomap.output for iomap in child_iomaps];
                           sep = TextString(" ")))
end

ProjectionModule.read_intent(::FaultProbeBranchToSyntax, recursion, change::Intent, iomap) = change
ProjectionModule.map_reference_forward(::FaultProbeBranchToSyntax, iomap, reference) = nothing
ProjectionModule.map_reference_backward(::FaultProbeBranchToSyntax, iomap, reference) = nothing

# Throws at one moment of its life, chosen by `when`: `:early` while it builds
# its IoMap, `:late` when its output cell is read, and `:read` in its reader and
# its reference maps. Each of those throws an interrupt. `:failing_read` throws
# an ordinary error from its reader.
Base.@kwdef struct InterruptingProjection <: Projection
    when::Symbol
end

function ProjectionModule.print_document(p::InterruptingProjection, recursion,
                                         leaf::FaultProbeLeaf, ctx)
    p.when === :early && throw(InterruptException())
    SimpleIoMap(nothing, leaf,
                Cell(@computation(p.when === :late ? throw(InterruptException()) :
                                  SyntaxLeaf(TextString(string(leaf.value))))))
end

function ProjectionModule.read_intent(p::InterruptingProjection, recursion,
                                      change::Intent, iomap)
    p.when === :failing_read && error("the reader is broken")
    throw(InterruptException())
end
ProjectionModule.map_reference_forward(::InterruptingProjection, iomap, reference) =
    throw(InterruptException())
ProjectionModule.map_reference_backward(::InterruptingProjection, iomap, reference) =
    throw(InterruptException())

_probe_dispatch() = TypeDispatchingProjection(
    FaultProbeLeaf => OddLeafBreaker(),
    FaultProbeBranch => FaultProbeBranchToSyntax())

_probe_branch(count::Integer) =
    FaultProbeBranch(children = CellVector(Cell[Cell(FaultProbeLeaf(value = index))
                                                for index in 1:count]))

# A printer context whose barriers catch, as the one of a running editor. With
# no policy in its context a barrier catches nothing, the way a test editor does.
# The list holds the barriers that took a fault, as the list of an editor does.
_make_tolerant_context(store) =
    with_property(with_property(with_property(PrinterContext(), :fault_store, store),
                                :fault_policy, FaultPolicy(is_console_enabled = false,
                                                           is_sound_enabled = false)),
                  :noted_barriers, Any[])

# Run `read` as the frames of an editor do: a read that reaches a cell that
# failed throws, the barriers that took the fault show their marks, and the next
# read draws them. One read finds one fault, so it can take a read per fault.
function _read_with_marks(read, context)
    noted = get_property(context, :noted_barriers)
    for _ in 1:16
        try
            return read()
        catch exception
            exception isa RecordedFaultException || rethrow()
            foreach(show_barrier_mark!, noted)
            empty!(noted)
        end
    end
    read()
end

# The content of the one layer that the dwell binding of `document` answers, or
# `nothing` when the binding does not answer.
function _read_fault_tooltip(document)
    operation = read_gesture(document, MouseDwell(0, 0; time = 0.0))
    operation === nothing ? nothing : only(get_wrapped_operation(operation).layers)[2]
end

# The drawn children of the printed output. Every cell on the way is forced,
# because the failure this suite is about happens when a cell is READ and a test
# that stops at the cell would never see it.
_force_cell(value) = value isa Cell ? _force_cell(value[]) : value

function _drawn_children(output)
    node = _force_cell(output)
    children = _force_cell(getfield(node, :children))
    [_force_cell(children[index]) for index in 1:length(children)]
end

function test_fault_catching()
@testset "the barrier inside the pipeline" begin

    @testset "without a barrier one bad node takes the whole tree" begin
        projection = RecursiveProjection(_probe_dispatch())
        iomap = print_document(projection, nothing, _probe_branch(6), PrinterContext())
        @test_throws Exception _drawn_children(iomap.output)
    end

    @testset "with a barrier the other nodes still draw" begin
        store = FaultStore()
        projection = RecursiveProjection(
            FaultCatchingProjection(inner = _probe_dispatch(),
                                    substitute = FaultToSyntax()))
        context = _make_tolerant_context(store)
        iomap = print_document(projection, nothing, _probe_branch(6), context)
        children = _read_with_marks(() -> _drawn_children(iomap.output), context)
        @test length(children) == 6
        # The three even leaves printed their value; the three odd ones carry a
        # mark, and the mark kept the slot the leaf had.
        drawn = [strip(string(child)) for child in children]
        @test count(text -> occursin("⚠", text), drawn) == 3
        @test count(text -> occursin("is odd", text), drawn) == 3
    end

    @testset "the three failures are one record" begin
        store = FaultStore()
        projection = RecursiveProjection(
            FaultCatchingProjection(inner = _probe_dispatch(),
                                    substitute = FaultToSyntax()))
        context = _make_tolerant_context(store)
        iomap = print_document(projection, nothing, _probe_branch(6), context)
        _read_with_marks(() -> _drawn_children(iomap.output), context)
        records = get_fault_records(store)
        @test length(records) == 1
        @test records[1].site === :print
        @test records[1].count == 3
    end

    @testset "a mark can be selected, and nothing else about it can be edited" begin
        store = FaultStore()
        barrier = FaultCatchingProjection(inner = _probe_dispatch(),
                                          substitute = FaultToSyntax())
        context = _make_tolerant_context(store)
        leaf = FaultProbeLeaf(value = 1)
        iomap = print_document(barrier, barrier, leaf, context)
        _read_with_marks(() -> _force_cell(iomap.output), context)

        # An Alt+press names the mark, as it names anything else on the screen.
        # The report is no child of the node that failed, so the path is a
        # drawn-object step from it.
        press = MouseClick(:left, 0, 0, 1, ModifierKeys(alt = true); time = 0.0)
        operation = read_intent(barrier, iomap, press)
        @test operation isa ReplaceSelectionOperation
        report = evaluate_reference(leaf, operation.path)
        @test report isa FaultReport
        @test occursin("leaf 1 is odd", _read_fault_tooltip(report).content)

        # The same path, twice: a selection that named a new report on every
        # frame would be lost on the next one.
        again = read_intent(barrier, iomap, press)
        @test evaluate_reference(leaf, again.path) === report

        # The mark is the whole image of the node, so the container rings it.
        @test map_reference_forward(barrier, iomap, operation.path) == EmptyReference()

        # Everything else about a node that failed stays inert: a key is
        # declined, and a path into the node has no image, so no edit can
        # address one. A plain click tries the part again (`test_fault_part`).
        @test read_intent(barrier, iomap, nothing) === nothing
        @test read_intent(barrier, iomap, KeyPress('x'; time = 0.0)) === nothing
        @test map_reference_forward(barrier, iomap, EmptyReference()) === nothing
    end

    @testset "a mark says the whole fault when the pointer rests on it" begin
        report = FaultReport(site = "print", origin = "OddLeafBreaker",
                             message = "BoundsError: index 4 of a vector of 3")
        # The one line a mark draws is cut where the mark ends; the window says
        # what failed, where it was caught, and the whole message.
        said = _read_fault_tooltip(report)
        @test said isa TextString
        text = string(said.content)
        @test occursin("OddLeafBreaker", text)
        @test occursin("print", text)
        @test occursin("BoundsError: index 4 of a vector of 3", text)

        # A mark is inert, so the selection never names the report: what a person
        # points at is the widget the mark is drawn as, and a widget says what its
        # own `tooltip` holds.
        alert = print_document(FaultToWidget(), FaultToWidget(), report,
                               PrinterContext()).output
        @test alert isa WidgetAlert
        @test String(_read_fault_tooltip(alert).value) == text
    end

    @testset "the barrier needs no store to work" begin
        projection = RecursiveProjection(
            FaultCatchingProjection(inner = _probe_dispatch(),
                                    substitute = FaultToSyntax()))
        context = _make_tolerant_context(nothing)
        iomap = print_document(projection, nothing, _probe_branch(4), context)
        @test length(_read_with_marks(() -> _drawn_children(iomap.output), context)) == 4
    end

    @testset "the fault reaches the log with its count" begin
        store = FaultStore()
        log = FaultLog()
        attach_fault_target!(store, log)
        projection = RecursiveProjection(
            FaultCatchingProjection(inner = _probe_dispatch(),
                                    substitute = FaultToSyntax()))
        context = _make_tolerant_context(store)
        iomap = print_document(projection, nothing, _probe_branch(6), context)
        _read_with_marks(() -> _drawn_children(iomap.output), context)
        drain_faults!(store)
        # One line, and the number on it is the number of places the bug was
        # found in. That is the whole point of a key that holds no reference.
        @test length(log.entries) == 1
        @test log.entries[1].site === :print
        @test log.entries[1].count == 3
    end

    @testset "two exceptions of one origin are two lines" begin
        # The store keys a fault by its site, its origin and its exception type,
        # and the log keys a line the same way.
        store = FaultStore()
        log = FaultLog()
        attach_fault_target!(store, log)
        record_fault!(store, :print; origin = :SyntaxToText, exception = BoundsError([1], 3))
        record_fault!(store, :print; origin = :SyntaxToText, exception = ArgumentError("bad"))
        drain_faults!(store)
        @test length(log.entries) == 2
        @test occursin("BoundsError", log.entries[1].message)
        @test occursin("bad", log.entries[2].message)
        # The same fault again takes its own line back, and not the other one.
        for _ in 1:9
            record_fault!(store, :print; origin = :SyntaxToText, exception = BoundsError([1], 3))
        end
        drain_faults!(store)
        @test length(log.entries) == 2
        @test log.entries[1].count == 10
        @test log.entries[2].count == 1
    end

    @testset "an interrupt passes through the barrier" begin
        # An interrupt means stop. A barrier that caught it would turn Ctrl+C
        # into a mark on the screen.
        context = _make_tolerant_context(FaultStore())
        late = FaultCatchingProjection(inner = InterruptingProjection(when = :late),
                                       substitute = FaultToSyntax())
        iomap = print_document(late, late, FaultProbeLeaf(value = 1), context)
        @test_throws InterruptException _force_cell(iomap.output)
        early = FaultCatchingProjection(inner = InterruptingProjection(when = :early),
                                        substitute = FaultToSyntax())
        @test_throws InterruptException print_document(early, early,
                                                       FaultProbeLeaf(value = 1), context)
        reader = FaultCatchingProjection(inner = InterruptingProjection(when = :read),
                                         substitute = FaultToSyntax())
        iomap = print_document(reader, reader, FaultProbeLeaf(value = 1), context)
        @test_throws InterruptException read_intent(reader, iomap, KeyPress('x'; time = 0.0))
        @test_throws InterruptException map_reference_forward(reader, iomap, EmptyReference())
    end

    @testset "the strict policy catches nothing" begin
        store = FaultStore()
        projection = RecursiveProjection(
            FaultCatchingProjection(inner = _probe_dispatch(),
                                    substitute = FaultToSyntax()))
        context = with_property(with_property(PrinterContext(), :fault_store, store),
                                :fault_policy, make_strict_fault_policy())
        iomap = print_document(projection, nothing, _probe_branch(2), context)
        @test_throws ErrorException _drawn_children(iomap.output)
        @test isempty(get_fault_records(store))
        # A context with no policy is strict too.
        iomap = print_document(projection, nothing, _probe_branch(2), PrinterContext())
        @test_throws ErrorException _drawn_children(iomap.output)
        reader = FaultCatchingProjection(inner = InterruptingProjection(when = :failing_read),
                                         substitute = FaultToSyntax())
        iomap = print_document(reader, reader, FaultProbeLeaf(value = 1), context)
        @test_throws ErrorException read_intent(reader, iomap, KeyPress('x'; time = 0.0))
    end

    @testset "an editor hands its policy to the barrier" begin
        projection = RecursiveProjection(
            FaultCatchingProjection(inner = _probe_dispatch(),
                                    substitute = FaultToSyntax()))
        # An editor starts strict, so the barrier catches nothing and a test sees
        # the fault.
        strict = Editor(_probe_branch(2), projection;
                        backend = HeadlessBackend(), devices = Device[])
        print!(strict)
        @test_throws ErrorException _drawn_children(strict.iomap.output)
        # The policy of a loop that a person sits in front of turns it on.
        tolerant = Editor(_probe_branch(2), projection;
                          backend = HeadlessBackend(), devices = Device[])
        tolerant.fault_policy = FaultPolicy(is_console_enabled = false,
                                            is_sound_enabled = false)
        print!(tolerant)
        @test_throws RecordedFaultException _drawn_children(tolerant.iomap.output)
        # The frame shows the mark of the barrier that took the fault.
        report_frame_faults!(tolerant)
        @test length(_drawn_children(tolerant.iomap.output)) == 2
        @test length(get_fault_records(tolerant.faults)) == 1
    end

    @testset "a person opens the session's log, and a window fills it" begin
        domain = ProjecturedPlatform.DomainModule
        log = get_session_fault_log()
        # `Ctrl+T` and `faults` give the one log of the session, never a fresh
        # one that nothing fills.
        @test domain.make_insertion_document(FaultLog) === log
        @test "faults" in domain.get_insertion_names(FaultLog)
        @test get_document_title(log) == "Faults"
        # A saved window keeps the capacity of the log and none of its faults.
        @test ProjecturedPlatform.SerializationModule.pred_arguments(log) ==
              ((), Pair{Symbol,Any}[:capacity => log.capacity])

        store = FaultStore()
        attach_fault_target!(store, log)
        projection = RecursiveProjection(
            FaultCatchingProjection(inner = _probe_dispatch(),
                                    substitute = FaultToSyntax()))
        context = _make_tolerant_context(store)
        iomap = print_document(projection, nothing, _probe_branch(6), context)
        _read_with_marks(() -> _drawn_children(iomap.output), context)
        drain_faults!(store)
        @test any(entry -> entry isa FaultLogEntry && entry.site === :print && entry.count >= 3,
                  collect(log.entries))
    end
end
end
