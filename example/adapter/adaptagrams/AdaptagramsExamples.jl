# ── Adaptagrams opt-in example registry ──────────────────────────────────────
#
# Projection builders in projection/Graph.jl; engine-free builders
# (make_graph_document_example) from ProjecturedExample; the relationship's
# DB-derived document (make_dvdrental_relationship_graph_document_example) from
# ProjecturedODBCExample.

# Native AdaptagramsLayout graph layout.
const graph_adaptagrams_example      = Example("graph_adaptagrams",      make_graph_document_example,                        make_graph_adaptagrams_projection_example)

"""
    make_dvdrental_relationship_example() -> Example

Build the dvdrental entity-relationship example: the live catalog of the
database, drawn as cards and foreign-key edges, laid out by the native
Adaptagrams shim.

A function rather than a constant. The `Example` constructor calls its document
builder at once, and that builder opens a connection to the dvdrental database.
A constant therefore opens the connection while the package precompiles, where
no database is reachable. Call this at the prompt instead, where the database
is there:

    run_example(make_dvdrental_relationship_example())

The example also stays out of `adaptagrams_examples`, so no sweep runs it.
"""
make_dvdrental_relationship_example() = Example("dvdrental_relationship",
    make_dvdrental_relationship_graph_document_example,
    make_dvdrental_relationship_projection_example)

# The Adaptagrams tier's example slice (sweep-safe subset — the DB-backed
# relationship diagram is excluded, as above).
const adaptagrams_examples = Example[
    graph_adaptagrams_example,
]
