# ── Adaptagrams opt-in example registry ──────────────────────────────────────
#
# Projection builders in projection/Graph.jl; engine-free builders
# (make_graph_document_example) from ProjecturedExample; the relationship's
# DB-derived document (make_dvdrental_relationship_graph_document_example) from
# ProjecturedOdbcExample.

# Native AdaptagramsEngine graph layout.
const graph_adaptagrams_example      = Example("graph_adaptagrams",      make_graph_document_example,                        make_graph_adaptagrams_projection_example)

# The dvdrental entity-relationship diagram (live DB + native shim). Kept OUT of
# the sweep — needs a live database and the built shim. Run directly.
const dvdrental_relationship_example = Example("dvdrental_relationship",
    make_dvdrental_relationship_graph_document_example,
    make_dvdrental_relationship_projection_example)

# The Adaptagrams tier's example slice (sweep-safe subset — the DB-backed
# relationship diagram is excluded, as above).
const adaptagrams_examples = Example[
    graph_adaptagrams_example,
]
