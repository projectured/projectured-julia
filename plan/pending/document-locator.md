# Document Locator

> **⏳ AUDIT STATUS (verified 2026-06-23): ALL STEPS OPEN.** No `DocumentLocator` abstract type, `DocumentLocatorPath`, `locator_equal`, or `is_whole_document` exists anywhere in source. No `common/DocumentLocator.jl` file exists (only `Document.jl`, `Operation.jl`, `Projection.jl`, `Reactive.jl`, `OperationRerooting.jl`, `IoMap.jl`, `DocumentCopy.jl` under `package/kernel/src/common/`). The only mention of "DocumentLocator" in source is a passing comment naming the *pattern* in `package/projectured/example/document/Versioning.jl:125` (re `VersionCriterion`); it does not implement this type. No exports in any `Projectured.jl`. The integration targets (`DocumentGraph`/`GraphNode`, `AnnotationBinding*`) also do not exist as source structs — they belong to sibling pending plans. This plan is entirely unimplemented and remains relevant.

A generic, domain-neutral abstraction for pointing at any element in the document universe. `DocumentLocator` is an **abstract type**; each addressing approach is a concrete subtype named `DocumentLocator<Mode>`. New addressing modes are added as new subtypes — existing code is unaffected.

## Goal

Provide a single, shared way to say *"this element, in this document"* that any feature can use — selection, annotation, document graph, drag-and-drop, or anything else that needs to point at a location in the document universe.

Today each feature that needs this invents its own representation: a bare `ReferencePath` (no document reference), a `(target_document, reference)` pair split across two fields, or a domain-scoped struct like `GraphNode`. The result is fragmented vocabulary, inconsistent semantics, and no natural place to add new addressing modes.

The goal is a common abstract type — `DocumentLocator` — with concrete subtypes for each addressing approach. Any feature that accepts a `DocumentLocator` automatically supports all current and future addressing modes without modification. New modes (predicate search, pattern matching, SQL-style queries, …) are added as new subtypes and immediately work everywhere a `DocumentLocator` is expected.

## Design

### File: `program/src/common/DocumentLocator.jl`

**`DocumentLocator`** — abstract base type. No fields; no `Document` contract. It is a *pointer concept*, not a document node:

```julia
abstract type DocumentLocator end
```

---

### `DocumentLocatorPath <: DocumentLocator`

The direct, structural addressing mode: a document cell plus a `ReferencePath` into it. This is the initial concrete subtype — the `(document, path)` pair used by the graph, annotation bindings, and selection today.

```julia
struct DocumentLocatorPath <: DocumentLocator
    document::Any        # Cell reference pointing at the root document
    path::ReferencePath  # EmptyReferencePath → whole document; otherwise a sub-element
end
```

Convenience constructor — whole-document locator:
```julia
DocumentLocatorPath(document) = DocumentLocatorPath(document, EmptyReferencePath())
```

---

### Helpers

```julia
"""
    locator_equal(a, b)

Structural equality of two locators. Same-type methods define the equality
semantics for each concrete subtype. Cross-type locators are never equal —
they address using incompatible mechanisms.
"""
locator_equal(a::DocumentLocatorPath, b::DocumentLocatorPath) =
    a.document === b.document && reference_equal(a.path, b.path)

locator_equal(::DocumentLocator, ::DocumentLocator) = false

"""
    is_whole_document(loc)

True when the locator points at an entire document (empty path).
Meaningful only for `DocumentLocatorPath`; other subtypes may not have this concept.
"""
is_whole_document(loc::DocumentLocatorPath) = isempty(loc.path)
```

---

### Sketch of future subtypes

These are not part of the current implementation. They illustrate how the pattern extends:

```julia
struct DocumentLocatorPredicate <: DocumentLocator
    document::Any        # Cell reference to search within
    predicate::Any       # f(element, path) → Bool
end

struct DocumentLocatorPattern <: DocumentLocator
    document::Any        # Cell reference to search within
    pattern::Any         # structural pattern (domain-specific)
end
```

A cross-document or corpus-level locator could omit the `document` field entirely and search across all open documents — that is fully supported since the abstract type imposes no fields.

## Design Decisions

**Abstract type, not a slot.**
The rejected alternative is a single struct with a `constraint::Any` field:

```julia
struct DocumentLocator          # rejected
    document::Any
    path::ReferencePath
    constraint::Any             # undefined semantics: predicate? SQL? pattern?
end
```

This is wrong for three reasons:
1. **Different addressing modes need different fields.** A `DocumentLocatorPredicate` needs a function but no path. A `DocumentLocatorPattern` needs a pattern but no function. A future SQL locator needs a query string. Forcing all of these into one struct means unused fields everywhere and no type-level information about which mode is active.
2. **Equality is mode-specific.** `DocumentLocatorPath` equality uses `===` on `document` and `reference_equal` on `path`. A predicate-based locator might use identity on the function object. An SQL locator might compare query strings. A `constraint::Any` slot makes it impossible to dispatch correctly.
3. **Dispatch is lost.** With an abstract type, `evaluate_locator`, `locator_equal`, and future operations dispatch cleanly on the concrete subtype. With a slot, you end up with `if constraint isa Function … elseif constraint isa String …` — exactly what Julia's type system exists to avoid.

**`DocumentLocator<Mode>` naming.**
Consistent with the existing codebase pattern: `GraphEdge` → `GraphLinkEdge`, `GraphDataEdge`; `ReferenceStep` → `RangeReference`, `FieldReference`, `FunctionReference`. The abstract concept is the prefix; the mode is the suffix.

**Plain types, not `Document`s.**
`DocumentLocator <: Document` was considered and rejected. The reasons:

1. **`===` equality breaks.** `locator_equal` uses `a.document === b.document` to compare cell identity. With `@document`, `getproperty` dereferences the cell — `a.document` returns the document *value*, not the cell. `===` would silently compare wrong things; you'd have to reach past the abstraction via `getfield(loc, :document)`.
2. **`selection::Reference` on every locator is meaningless overhead.** Locators are used as field values in graph edges, annotation bindings, and operations. Each instance would carry a `selection` cell that is always `nothing` — the Document contract has no meaning for a pointer type.
3. **Spurious reactive tracking.** Every read of `loc.document` or `loc.path` would register a reactive dependency. Locators are read frequently in equality checks and graph traversals; this creates a large number of unintended reactive edges.
4. **Mutability is wrong for pointer types.** Cell-wrapped fields would make a locator's path changeable in-place. Locators in `AnnotationBinding.target` and graph edge fields should be stable values; if a binding's target changes, the whole locator is replaced, not mutated.
5. **Conceptual mismatch.** A `Document` is *content* — something edited, displayed, and persisted. A locator is a *pointer* — something used to find content. `ReferencePath` and `ReferenceStep` follow the same rule: neither is a `Document`. Locators belong in the same category.

**`document::Any` on concrete subtypes, not on the abstract type.**
Future subtypes may not need a single document reference (e.g., a corpus-wide search). Each concrete type carries only the fields its semantics actually require.

**`===` (identity) equality on `document` in `DocumentLocatorPath`.**
Two path locators pointing at the same live document cell must compare equal regardless of the document's current content. `==` would do structural comparison of the potentially large document tree.

## Exports

From `program/src/Projectured.jl`:

```julia
export DocumentLocator, DocumentLocatorPath, locator_equal, is_whole_document
```

## Integration Points

Features that should use `DocumentLocator` (abstract) as their field type, and `DocumentLocatorPath` as the concrete value initially:

- **`DocumentGraph`** — `source::DocumentLocator` and `target::DocumentLocator` on edge types, constructed as `DocumentLocatorPath` values (see `plan/pending/document-graph.md`). Graph queries accept any locator subtype.
- **Annotation bindings** — `AnnotationBindingDirect` and `AnnotationBindingReferencePath` collapse into a single binding type with `target::DocumentLocator`. `DocumentLocatorPath(doc)` replaces a direct reference; `DocumentLocatorPath(doc, path)` replaces a reference path binding (see `plan/pending/annotation-feature.md`).
- **`ReplaceSelectionOperation`** — can carry a `DocumentLocator` field when cross-document selection is needed (see `plan/tentative/evaluate-operation-document-arg.md`).
- **Future: cross-document selection, drag-drop targets, SQL queries, pattern search** — each arrives as a new `DocumentLocator<Mode>` subtype with no changes to existing code.

## Implementation Steps

1. **⏳ OPEN — Create `DocumentLocator.jl`** with the abstract type, `DocumentLocatorPath`, and helpers. *(No such file exists under `package/*/src/common/`; type not defined anywhere.)*
2. **⏳ OPEN — Wire into `Projectured.jl`**: `include("common/DocumentLocator.jl")` and exports. *(No `include`/`export` of any `DocumentLocator` symbol in any `Projectured.jl`.)*
3. **⏳ OPEN — Write tests** — `DocumentLocatorPath` construction, `locator_equal` (same doc/path, different doc, different path, cross-type always false), `is_whole_document`. *(No `locator_equal`/`is_whole_document`/`DocumentLocatorPath` references in `package/test/`.)*
4. **⏳ OPEN — Update `DocumentGraph`** to use `DocumentLocator` / `DocumentLocatorPath` instead of `GraphNode` (parallel with document-graph implementation work). *(No `DocumentGraph`/`GraphNode` struct exists in source; depends on the unimplemented document-graph plan.)*
5. **⏳ OPEN — Update annotation bindings** to collapse the two binding subtypes using `target::DocumentLocator` (parallel with annotation-feature implementation work). *(No `AnnotationBinding*` types exist in source; depends on the unimplemented annotation-feature plan.)*

## Dependencies

- `ReferenceModule` (`ReferencePath`, `EmptyReferencePath`, `reference_equal`) — must be loaded before this module.
- No other dependencies. This is a foundational type; no document types or projections are needed.
