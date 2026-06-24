# The graph projection: GraphGraph → GraphLayout → GraphicsCanvas, with each
# vertex's content rendered by a per-domain sub-pipeline (the "recursion"). The
# two graph stages run as a SequentialProjection; a NestingProjection threads the
# content projection as their recursion (mirrors make_table_projection_example).
#
# Defaults to the pure-Julia FallbackLayoutEngine. Pass an engine to swap it
# (e.g. the native AdaptagramsEngine, see make_graph_adaptagrams_projection_example)
# behind the same interface.

function make_graph_projection_example(; measure=truetype_measure_text,
                                       engine=FallbackLayoutEngine(),
                                       content=nothing)
    # A vertex's content can be any domain. Dispatch on the root content type to a
    # complete per-domain pipeline to GraphicsCanvas: tables render directly via
    # TableToGraphics; Json/Xml go through Syntax → Text → Graphics. Each branch is
    # self-contained (RecursiveProjection/NestingProjection set their own
    # recursion), so they compose cleanly under one dispatcher. Callers can pass
    # their own `content` dispatcher (e.g. one that also routes `WidgetCard`) to
    # reuse the graph-stages wiring without duplicating it.
    if content === nothing
        content = TypeDispatchingProjection(
            WidgetTable => make_table_projection_example(measure=measure),
            Any         => make_mixed_projection_example(measure=measure),
        )
    end

    graph_stages = SequentialProjection(
        GraphGraphToGraphLayout(engine),
        GraphLayoutToGraphicsCanvas(),
    )

    NestingProjection(graph_stages; recursion=content)
end

# The same graph, laid out by the native AdaptagramsEngine (libcola placement +
# libavoid obstacle-avoiding routing) instead of the pure-Julia grid fallback —
# a side-by-side demonstration that the engine is a swappable seam. Requires the
# ProjecturedAdaptagrams native shim to be built
# (`using Pkg; Pkg.build("ProjecturedAdaptagrams")`); otherwise it errors at
# print time with build guidance. Building the projection is cheap and engine-
# free — the native call happens lazily when the projection is printed.
function make_graph_adaptagrams_projection_example(; measure=truetype_measure_text)
    make_graph_projection_example(; measure=measure, engine=AdaptagramsEngine())
end

# The dvdrental entity-relationship diagram: the relationship `GraphGraph` (one
# `WidgetCard` per table) laid out by the native AdaptagramsEngine. The content
# dispatcher routes a vertex's `WidgetCard` content through
# `make_table_projection_example`, which already dispatches `WidgetCard` (title +
# nested column `WidgetTable`), `WidgetTable`, `WidgetLabel`, and the layout types
# down to a `GraphicsCanvas` — so no new primitive projection is needed. Pair with
# `make_dvdrental_relationship_graph_document_example`; requires the
# ProjecturedAdaptagrams native shim to be built (see above).
function make_dvdrental_relationship_projection_example(; measure=truetype_measure_text)
    content = TypeDispatchingProjection(
        WidgetCard  => make_table_projection_example(measure=measure),
        WidgetTable => make_table_projection_example(measure=measure),
        Any         => make_mixed_projection_example(measure=measure),
    )
    make_graph_projection_example(; measure=measure,
                                  engine=AdaptagramsEngine(), content=content)
end
