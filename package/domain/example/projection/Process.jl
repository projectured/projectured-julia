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
# The engine is whatever the session has: `default_layout_engine` is the
# pure-Julia fallback until `ProjecturedAdaptagrams` is loaded, and native
# placement with right-angled routing after that. A flowchart asks for
# `orthogonal` because its arrows are read as flow — a diagonal between two
# boxes reads as a relation instead of a direction.
function make_process_diagram_projection_example(; measure=truetype_measure_text,
                                                 engine=default_layout_engine(orthogonal=true))
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
