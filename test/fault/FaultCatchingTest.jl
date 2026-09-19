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
                ComputedCell(() -> isodd(leaf.value) ?
                             error("leaf $(leaf.value) is odd") :
                             SyntaxLeaf(TextString(string(leaf.value)))))

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

_probe_dispatch() = TypeDispatchingProjection(
    FaultProbeLeaf => OddLeafBreaker(),
    FaultProbeBranch => FaultProbeBranchToSyntax())

_probe_branch(count::Integer) =
    FaultProbeBranch(children = CellVector(Cell[Cell(FaultProbeLeaf(value = index))
                                                for index in 1:count]))

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
        context = with_property(PrinterContext(), :fault_store, store)
        iomap = print_document(projection, nothing, _probe_branch(6), context)
        children = _drawn_children(iomap.output)
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
        context = with_property(PrinterContext(), :fault_store, store)
        iomap = print_document(projection, nothing, _probe_branch(6), context)
        _drawn_children(iomap.output)
        records = get_fault_records(store)
        @test length(records) == 1
        @test records[1].site === :print
        @test records[1].count == 3
    end

    @testset "a mark is inert" begin
        store = FaultStore()
        barrier = FaultCatchingProjection(inner = _probe_dispatch(),
                                          substitute = FaultToSyntax())
        context = with_property(PrinterContext(), :fault_store, store)
        iomap = print_document(barrier, barrier, FaultProbeLeaf(value = 1), context)
        _force = iomap.output isa Cell ? iomap.output[] : iomap.output
        # The reader declines and the mappers answer no image, which is what
        # keeps the selection out of a node that failed.
        @test read_intent(barrier, iomap, nothing) === nothing
        @test map_reference_forward(barrier, iomap, EmptyReference()) === nothing
    end

    @testset "the barrier needs no store to work" begin
        projection = RecursiveProjection(
            FaultCatchingProjection(inner = _probe_dispatch(),
                                    substitute = FaultToSyntax()))
        iomap = print_document(projection, nothing, _probe_branch(4), PrinterContext())
        @test length(_drawn_children(iomap.output)) == 4
    end

    @testset "the fault reaches the log with its count" begin
        store = FaultStore()
        log = FaultLog()
        attach_fault_target!(store, log)
        projection = RecursiveProjection(
            FaultCatchingProjection(inner = _probe_dispatch(),
                                    substitute = FaultToSyntax()))
        context = with_property(PrinterContext(), :fault_store, store)
        iomap = print_document(projection, nothing, _probe_branch(6), context)
        _drawn_children(iomap.output)
        drain_faults!(store)
        # One line, and the number on it is the number of places the bug was
        # found in. That is the whole point of a key that holds no reference.
        @test length(log.entries) == 1
        @test log.entries[1].site === :print
        @test log.entries[1].count == 3
    end
end
end
