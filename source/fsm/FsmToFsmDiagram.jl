# Fragment of `FsmModule`.
#
# FsmMachine → FsmDiagram: the first stage of the diagram pipeline, and a thin
# one. It wraps the machine in the presentation document that carries the live
# position (current state, last transition, transition count), so the renderer
# downstream has one place to read all of it and the machine itself stays pure
# content.
#
# The `FsmDiagram` is built once per projection setup and keeps its identity, so
# a live driver can take its handle at setup and keep writing to the same three
# cells for the rest of the run — the `ChartToChartPlot` pattern, for the same
# reason.
#
# Selection peels exactly the one step this stage owns — `machine` — and hands
# the rest through unchanged, so a selection into a state round-trips through the
# whole pipeline (School A).
"""
    FsmToFsmDiagram()

The machine → diagram stage. Stateless; all the state it produces lives on the
`FsmDiagram` it emits.
"""
struct FsmToFsmDiagram <: Projection end

@iomap struct FsmToFsmDiagramIoMap
    projection::Any
    input::Any
    output::Any
end

# An empty placeholder is still something the renderer has to draw (as an empty
# diagram), so it gets a diagram too rather than a second pipeline.
function print_document(p::FsmToFsmDiagram, recursion,
                        machine::Union{FsmMachine, FsmNothing, FsmInsertion}, ctx)
    iomap_cell = Cell(nothing)
    diagram = FsmDiagram(
        Cell(machine), Cell(0), Cell(0), Cell(0),
        ComputedCell(() -> let im = iomap_cell[]
            im === nothing ? nothing : map_reference_forward(p, im, machine.selection)
        end))
    iomap = FsmToFsmDiagramIoMap(p, machine, diagram)
    iomap_cell[] = iomap
    iomap
end

# anything... ↔ machine.anything...
#
# The `machine` step takes the node type of whatever root this actually is;
# spelling `::FsmMachine` literally would leave the step under-typed for an
# `FsmNothing` root (the `ChartToChartPlot` lesson).
function map_reference_forward(::FsmToFsmDiagram, iomap, reference)
    reference === nothing && return nothing
    mt = get_reference_node_type(iomap.input)
    @reference_case reference begin
        ∅ => @reference ::FsmDiagram
        rest... => (@reference ::FsmDiagram.machine::mt.^(rest))
    end
end

function map_reference_backward(::FsmToFsmDiagram, iomap, reference)
    reference === nothing && return nothing
    @reference_case reference begin
        ∅ => @reference ::FsmMachine
        ::FsmDiagram.machine.rest... => (@reference ^(rest))
        __ => nothing
    end
end
