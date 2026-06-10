# Association Feature Implementation Plan

This plan implements a generic association system that allows connecting documents through associations stored in a global registry. Each association is a source-target pair where the source document provides the content (note, decoration, memo, mark, flag, etc.) and the target is the document element being associated with.

## Overview

Create a new Association domain with a global registry document that stores associations as edges connecting document locators. Each association connects a source document (containing the association content) to a target document element, enabling flexible attachment of notes, decorations, memos, marks, or flags to any document element.

## Key Design Principles

- **Maximum flexibility**: Source document can be any document type
- **Edge-based structure**: Association bindings are pure edges connecting documents
- **DocumentLocator integration**: Uses standardized locator for addressing any document element
- **Single binding type**: `DocumentLocator` abstract type handles all addressing modes without multiple binding subtypes
- **Reactive**: All association data uses cells for automatic dependency tracking
- **Projectional**: Association bindings are first-class documents that can be projected like any other domain
- **Two projection approaches**: Association-centric (tree view from association perspective) and decorator (add associations to any document projection)
- **Deferred complexity**: Operations and visualization kept simple per user request, extensible later

## Design Decisions

### Global Registry vs Per-Document Registry

**Decision:** Global registry (single entry point for all associations)

**Rationale:**
- Zero modification: Associate any document without changing document types
- Simpler implementation: Single source of truth
- Cross-document support: Enables associations across multiple documents
- Lazy creation: Registry only created when first association is added

**Trade-offs:**
- Global state management (acceptable for initial implementation)
- Harder to scope associations to specific documents (can add later)

### Source as Content Document vs Content Slot

**Decision:** Source document contains content (no `content::Any` slot on binding)

**Rationale:**
- Pure edge: Associations become true edges connecting documents
- First-class source: Source document is independently editable and can be complex
- Flexibility: Source can be any document type (Text, JSON, Conversation, etc.)

**Example:**
```julia
# Comment: source is a Text document
comment_doc = TextText("This needs review")
AssociationBinding(
    DocumentLocatorPath(comment_doc),
    DocumentLocatorPath(target_doc, path_to_element)
)
```

### Other Decisions

- Single `AssociationBinding` type using `DocumentLocator` for both source and target
- `DocumentLocator` abstract type allows future addressing modes without changing binding type
- Association bindings are Documents using `@document` macro for editor integration

## Implementation Order

1. Implement `DocumentLocator` (see `plan/pending/document-locator.md`)
2. Association domain types + query API (`Association.jl`)
3. Association operations
4. Association-centric projections (`AssociationToSyntax.jl`)
5. Decorator projection (`AssociationDecorating.jl`)
6. Integration (update `Projectured.jl`)
7. Testing

## Phase 1: Association Domain Types

### File: `program/src/document/Association.jl`

**Type Hierarchy:**
```julia
abstract type AssociationDocument <: Document end
```

**Concrete Types (all use `@document` macro, which auto-wraps fields into `Cell`):**
- `AssociationBinding <: AssociationDocument` - Edge connecting source document to target element:
  - `source::DocumentLocator` - Source document locator (contains the association content)
  - `target::DocumentLocator` - Target document locator (what the association points to)
  - `selection::Reference` - For document contract
- `AssociationRegistry <: AssociationDocument` - Global document storing:
  - `locators::CellVector` - Optional catalogue of registered DocumentLocator values
  - `bindings::CellVector` - All AssociationBinding instances
  - `selection::Reference` - For document contract

**Note:** All types use `@document` macro which auto-converts field type annotations to `Cell` — write logical types (e.g., `source::DocumentLocator`), not `Cell{DocumentLocator}`. The macro also generates an immutable `I`-prefixed variant and conversion constructors. No explicit `id` field — association bindings are identified by their cell references in the registry.

**Global Registry:** `global_association_registry::Cell{Union{Nothing, AssociationRegistry}}` with `get_association_registry()` accessor. Registry is reactive so projections can depend on it.

## Phase 2: Query API

**File:** `program/src/document/Association.jl` (same file as domain types)

Node equality uses `locator_equal(a, b)` from `DocumentLocator`.

**Functions on `AssociationRegistry`:**
- `add_association!(registry, binding)` — push binding into `registry.bindings`
- `remove_association!(registry, binding)` — remove binding by identity
- `associations_from(registry, loc)` — bindings where `source` matches `loc`
- `associations_to(registry, loc)` — bindings where `target` matches `loc`
- `associations_of_source_type(registry, type)` — filter by source document type
- `associations_between(registry, src, tgt)` — bindings connecting two locators
- `neighbors(registry, loc)` — all directly connected locators (deduplicated)

## Phase 3: Association Operations

**File:** `program/src/document/Association.jl` (same file as domain types)

**Operations:**
- `CreateAssociationOperation` - Create new association binding
- `DeleteAssociationOperation` - Remove association binding
- `CleanupStaleAssociationsOperation` - Remove associations with invalid locators

**Implementation:** Operations modify global `AssociationRegistry` and are reactive through the cell system. To modify association content, edit the source document directly.

## Phase 4: Association Projections

**Two approaches:**

1. **Association-centric:** Show associations and their connected documents as a tree (`AssociationToSyntax.jl`)
2. **Decorator:** Insert associations into any document projection pipeline (`AssociationDecorating.jl`)

**AssociationToSyntax.jl:**
- `AssociationBindingToSyntaxNode` - Project binding with source/target references
- `AssociationRegistryToSyntaxNode` - Project entire registry as syntax tree
- Printer shows locators and projects source document content
- Reader translates edits back to association operations

**AssociationDecorating.jl:**
- `DecorateWithAssociations` - Decorator projection with `decoration_mode::Symbol` parameter
- Printer queries registry via `associations_to`, evaluates locators, projects source documents as decorations
- Reader translates decoration edits to association operations

**Optional:** `AssociationToJson.jl` for serialization

## Phase 5: Integration Points

**Projectured.jl:**
- `include("common/DocumentLocator.jl")` (must precede association module)
- `include("document/Association.jl")`
- Export types, query functions, and operations

**Editor.jl:** Ensure editor can access global `AssociationRegistry`

## Future: Multi-Document Support

Add `document_id::String` field to `AssociationBinding` for per-document persistence. Helper functions: `get_associations_for_document`, `save_associations_for_document`, `load_associations_for_document`. Cleanup on document close via `CleanupStaleAssociationsOperation`.

## Dependencies

- **DocumentLocator** (`plan/pending/document-locator.md`) — must be implemented first
- **ReferenceModule** (`ReferencePath`, `EmptyReferencePath`, `reference_equal`) — must be loaded before this module
