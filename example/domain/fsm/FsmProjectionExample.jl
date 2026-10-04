# The natural notation pipeline: the fsm/julia merged dispatch table through
# the shared Syntax → Text → Graphics tail every domain ends with.
function make_fsm_projection_example(; measure=FontFileMeasure())
    ChainingProjection(
        RecursiveProjection(FsmToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end

# The diagram pipeline: FsmMachine → FsmDiagram → GraphGraph, then the stock
# graph stages. The graph stages recurse each vertex's content (an `FsmState`)
# and each edge's label (an `FsmTransition`) through the compact diagram label
# projections; anything else falls back to the notation, so a machine that grows
# a foreign content type still renders.
function make_fsm_diagram_projection_example(; measure=FontFileMeasure(),
                                             engine=GridEmbedding())
    label = ChainingProjection(
        RecursiveProjection(FsmToSyntaxLabel()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
    ChainingProjection(
        FsmToFsmDiagram(),
        FsmDiagramToGraph(),
        NestingProjection(
            ChainingProjection(GraphGraphToGraphLayout(engine),
                               GraphLayoutToGraphicsCanvas());
            recursion=label),
    )
end
