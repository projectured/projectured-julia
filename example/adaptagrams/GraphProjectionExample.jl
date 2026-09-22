# Adaptagrams-engine graph projections (native libcola placement + libavoid
# obstacle-avoiding routing). Split out of ProjecturedExample so the base example
# package carries no dependency on the native ProjecturedAdaptagrams shim; these
# reuse the base graph wiring (`make_graph_projection_example`) with the native
# engine swapped in. Building the projection is cheap and engine-free — the native
# call happens lazily when the projection is printed. The shim need not be built
# first: an unbuilt shim falls back to a pure-Julia layout engine and warns once.

function make_graph_adaptagrams_projection_example(; measure=measure_truetype_text)
    make_graph_projection_example(; measure=measure, engine=AdaptagramsLayout())
end

# The dvdrental entity-relationship diagram laid out by the native AdaptagramsLayout.
# Pairs with `make_dvdrental_relationship_graph_document_example` (ODBC). The content
# dispatcher routes each vertex's `WidgetCard` through `make_table_projection_example`.
function make_dvdrental_relationship_projection_example(; measure=measure_truetype_text)
    content = TypeDispatchingProjection(
        WidgetCard  => make_table_projection_example(measure=measure),
        WidgetTable => make_table_projection_example(measure=measure),
        Any         => make_mixed_projection_example(measure=measure),
    )
    make_graph_projection_example(; measure=measure,
                                  engine=AdaptagramsLayout(), content=content)
end
