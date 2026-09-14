# Fragment of `ProcessModule`.
#
# ProcessModel → ProcessDiagram: the first stage of the flowchart pipeline, and
# a thin one. It wraps the model in the presentation document that carries the
# debug session, so the renderer downstream has one place to read the live
# position and the model itself stays pure content.
#
# The `ProcessDiagram` is built once per projection setup and keeps its identity,
# so a driver can take its handle at setup and keep writing the same session for
# the rest of the run — the `FsmToFsmDiagram` pattern, for the same reason.
#
# Selection peels exactly the one step this stage owns — `model` — and hands the
# rest through unchanged, so a selection into a step round-trips through the
# whole pipeline (School A).
"""
    ProcessToProcessDiagram()

The model → diagram stage. Stateless; all the state it produces lives on the
`ProcessDiagram` it emits.
"""
struct ProcessToProcessDiagram <: Projection end

@iomap struct ProcessToProcessDiagramIoMap
    projection::Any
    input::Any
    output::Any
end

# An empty placeholder is still something the renderer has to draw (as an empty
# diagram), so it gets a diagram too rather than a second pipeline.
function print_document(p::ProcessToProcessDiagram, recursion,
                        model::Union{ProcessModel, ProcessNothing, ProcessInsertion}, ctx)
    iomap_cell = Cell(nothing)
    diagram = ProcessDiagram(
        Cell(model), Cell(nothing),
        ComputedCell(() -> let im = iomap_cell[]
            im === nothing ? nothing : map_reference_forward(p, im, model.selection)
        end))
    iomap = ProcessToProcessDiagramIoMap(p, model, diagram)
    iomap_cell[] = iomap
    iomap
end

# anything... ↔ model.anything...
#
# The `model` step takes the node type of whatever root this actually is;
# spelling `::ProcessModel` literally would leave the step under-typed for a
# `ProcessNothing` root (the `ChartToChartPlot` lesson).
function map_reference_forward(::ProcessToProcessDiagram, iomap, reference)
    reference === nothing && return nothing
    mt = get_reference_node_type(iomap.input)
    @reference_case reference begin
        ∅ => @reference ::ProcessDiagram
        rest... => (@reference ::ProcessDiagram.model::mt.^(rest))
    end
end

function map_reference_backward(::ProcessToProcessDiagram, iomap, reference)
    reference === nothing && return nothing
    @reference_case reference begin
        ∅ => @reference ::ProcessModel
        ::ProcessDiagram.model.rest... => (@reference ^(rest))
        __ => nothing
    end
end
