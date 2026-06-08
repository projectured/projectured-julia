# Document Graph

A global, reactive graph that connects independent document locations (whole docs or sub-elements) with typed edges, without modifying the original documents — plus an `InjectionSource` pattern that feeds those edges into `InjectingProjection`.

**Depends on `DocumentLocator`** (see `plan/pending/document-locator.md`). `DocumentLocator` is the shared, domain-neutral `(document, path)` struct used as node identity here.

## Design Principles

- **Non-invasive**: original document types (`EmailDocument`, `ConversationConversation`, etc.) are untouched.
- **Separate from `AnnotationRegistry`**: the annotation system stays as-is; `DocumentGraph` is for heavyweight, structured cross-document links.
- **Flexible edge payload**: simple `GraphLinkEdge` (type label only) and open `GraphDataEdge` (type + arbitrary metadata). Both subtypes of a common abstract type — more edge kinds can be added without changing the core.
- **Sub-element granularity**: a node targets either a whole document or a `ReferencePath` inside one.
- **Reactive**: the graph lives in a `Cell`, so projections depending on it invalidate automatically when edges are added/removed.

## Why `DocumentLocator` instead of flat `(document, path)` slots on each edge

The alternative — inlining `source_document`, `source_path`, `target_document`, `target_path` directly as fields on every edge type — is simpler in terms of type count. The `DocumentLocator` wrapper is kept for three reasons:

1. **Query API cohesion** — `edges_from(graph, node)`, `edges_to(graph, node)`, and `neighbors(graph, node)` all accept and return a single typed value. Without `DocumentLocator` you'd thread `(doc_cell, path)` pairs through every query call and return `Vector{Tuple{Any,ReferencePath}}` from `neighbors`.
2. **Chaining** — graph traversals compose naturally: the output of `neighbors` feeds directly into the next `edges_from` call without destructuring.
3. **Shared vocabulary** — `DocumentLocator` is defined once in `program/src/common/` and reused by annotations, selection, and any future feature that needs to point at a document element. The graph does not invent its own parallel type.

## Phase 1: Document Types

### File: `program/src/document/DocumentGraph.jl`

**`DocumentLocator`** is imported from `program/src/common/DocumentLocator.jl` — no redefinition here.

**`GraphEdge`** (abstract `<: Document`):
```julia
abstract type GraphEdge <: Document end
```

**`GraphLinkEdge <: GraphEdge`** — typed link, no payload:
```julia
@document struct GraphLinkEdge <: GraphEdge
    source::DocumentLocator
    target::DocumentLocator
    kind::Symbol           # :reply_to, :attachment, :generated_from, …
    selection::Reference
end
```

**`GraphDataEdge <: GraphEdge`** — typed link with arbitrary metadata:
```julia
@document struct GraphDataEdge <: GraphEdge
    source::DocumentLocator
    target::DocumentLocator
    kind::Symbol
    data::Any              # timestamp, author, score, or another Document
    selection::Reference
end
```

**`DocumentGraph <: Document`**:
```julia
@document struct DocumentGraph <: Document
    nodes::CellVector      # optional catalogue of registered DocumentLocator values
    edges::CellVector      # all GraphEdge instances
    selection::Reference
end
```

**Global registry** (same pattern as `AnnotationRegistry`):
```julia
const global_document_graph = Cell{Union{Nothing,DocumentGraph}}(nothing)

function get_document_graph()
    isnothing(global_document_graph[]) &&
        (global_document_graph[] = DocumentGraph())
    global_document_graph[]
end
```

## Phase 2: Query API

Node equality uses `locator_equal(a, b)` from `DocumentLocator` — `===` on `document`; `reference_equal` on `path`.

Functions on a `DocumentGraph`:
- `add_edge!(graph, edge)` — push edge into `graph.edges`
- `remove_edge!(graph, edge)` — remove edge by identity
- `edges_from(graph, loc)` — edges where `source` matches `loc`
- `edges_to(graph, loc)` — edges where `target` matches `loc`
- `edges_of_kind(graph, kind::Symbol)` — filter by edge `:kind`
- `edges_between(graph, src, tgt)` — edges connecting two locators in either direction
- `neighbors(graph, loc)` — all directly connected locators (deduplicated)

## Phase 3: InjectingProjection Integration

No new projection type needed. The pattern is an `InjectionSource` collector that queries the graph.

### Pattern (email → AI chat inline):
```julia
InjectionSource() do input_doc, full_iomap
    graph = get_document_graph()           # reactive read → dependency registered
    src_cell = getfield(input_doc, :some_field)
    loc   = DocumentLocatorPath(src_cell)   # EmptyReferencePath → whole document
    specs = InjectionSpec[]
    for edge in edges_from(graph, loc)
        edge.kind === :ai_reply || continue
        chat_doc = edge.target.document[]
        # map the source sub-element reference into the text domain
        text_ref = map_reference_forward(full_iomap, edge.source.path)
        # project the chat doc independently (collapsed thumbnail)
        canvas  = projection_print(ConversationToGraphics(collapsed=true), chat_doc, ...)
        push!(specs, InjectionSpec(text_ref, :after, TextGraphics(canvas)))
    end
    specs
end
```

Reading `global_document_graph` inside the collector registers a reactive dependency — any edge added/removed automatically invalidates the downstream cells, and `TextToGraphics` reflows on the next render.

## Phase 4: Integration

### File: `program/src/Projectured.jl`
- `include("common/DocumentLocator.jl")` (must precede document graph)
- `include("document/DocumentGraph.jl")`
- Export `DocumentLocator`, `DocumentLocatorPath`, `locator_equal`, `is_whole_document` (from `DocumentLocator`)
- Export `DocumentGraph`, `GraphEdge`, `GraphLinkEdge`, `GraphDataEdge`,
  `global_document_graph`, `get_document_graph`,
  `add_edge!`, `remove_edge!`,
  `edges_from`, `edges_to`, `edges_of_kind`, `edges_between`, `neighbors`

## Implementation Steps

1. **Implement `DocumentLocator`** first (see `plan/pending/document-locator.md` — independent, no document-graph dependency).
2. **Create `DocumentGraph.jl`** with `GraphEdge`, `GraphLinkEdge`, `GraphDataEdge`, `DocumentGraph`, global registry, and query functions — all using `DocumentLocator` for node identity.
3. **Wire into `Projectured.jl`** (include + exports).
4. **Write tests** — add/query edges, sub-element locator targeting, reactive invalidation.
5. **Document `InjectionSource` pattern** in an example file showing email ↔ AI-chat linking.

## Pending Plan Dependencies

- **`DocumentLocator`** (`plan/pending/document-locator.md`) — must be implemented before Phase 1. It is a small, self-contained step with no further dependencies.
- **`InjectingProjection`** (`plan/pending/injecting-projection.md`) — required for Phases 3–4. Phases 1–2 are independent of it.

## Future Extensions

- **Directed vs undirected** edge traversal helpers
- **Edge projections** — render the graph as a visual graph view (separate plan)
- **Persistence** — serialize the `DocumentGraph` to disk alongside open documents
- **Scoped graphs** — per-workspace or per-session graph instances alongside the global one
