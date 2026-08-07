# The natural notation pipeline: the process/julia merged dispatch table through
# the shared Syntax → Text → Graphics tail every domain ends with.
function make_process_projection_example(; measure=truetype_measure_text)
    ChainingProjection(
        RecursiveProjection(ProcessToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end

# The flowchart pipeline: ProcessModel → ProcessDiagram → GraphGraph, then the
# stock graph stages. The graph stages recurse each vertex's content (a process
# node) and each edge's label through the compact diagram label projections;
# anything else falls back to the notation, so a box that grows a foreign
# content type still renders.
function make_process_diagram_projection_example(; measure=truetype_measure_text,
                                                 engine=FallbackLayoutEngine())
    label = ChainingProjection(
        RecursiveProjection(ProcessToSyntaxLabel()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
    ChainingProjection(
        ProcessToProcessDiagram(),
        ProcessDiagramToGraph(),
        NestingProjection(
            ChainingProjection(GraphGraphToGraphLayout(engine),
                               GraphLayoutToGraphicsCanvas());
            recursion=label),
    )
end
