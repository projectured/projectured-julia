# DocumentLink Feature Implementation Plan

This plan implements a generic document link system that allows connecting documents through links stored in a global registry. Each link is a source-target pair where the source document provides the content (note, decoration, memo, mark, flag, etc.) and the target is the document element being linked to.

## Overview

Create a new DocumentLink domain with a global registry document that stores links as edges connecting document locators. Each link connects a source document (containing the link content) to a target document element, enabling flexible attachment of notes, decorations, memos, marks, or flags to any document element.

## Key Design Principles

- **Maximum flexibility**: Source document can be any document type
- **Edge-based structure**: DocumentLink bindings are pure edges connecting documents
- **DocumentLocator integration**: Uses standardized locator for addressing any document element
- **Single binding type**: `DocumentLocator` abstract type handles all addressing modes without multiple binding subtypes
- **Reactive**: All document link data uses cells for automatic dependency tracking
- **Projectional**: DocumentLink bindings are first-class documents that can be projected like any other domain
- **Projection approach**: DocumentLink-centric (tree view from link perspective)
- **Deferred complexity**: Operations and visualization kept simple per user request, extensible later

## Design Decisions

### Global Registry vs Per-Document Registry

**Decision:** Global registry (single entry point for all document links)

**Rationale:**
- Zero modification: Link any document without changing document types
- Simpler implementation: Single source of truth
- Cross-document support: Enables links across multiple documents
- Lazy creation: Registry only created when first link is added

**Trade-offs:**
- Global state management (acceptable for initial implementation)
- Harder to scope links to specific documents (can add later)

### Source as Content Document vs Content Slot

**Decision:** Source document contains content (no `content::Any` slot on binding)

**Rationale:**
- Pure edge: DocumentLinks become true edges connecting documents
- First-class source: Source document is independently editable and can be complex
- Flexibility: Source can be any document type (Text, JSON, Conversation, etc.)

**Example:**
```julia
# Comment: source is a Text document
comment_doc = TextText("This needs review")
DocumentLinkBinding(
    DocumentLocatorPath(comment_doc),
    DocumentLocatorPath(target_doc, path_to_element)
)
```

### Other Decisions

- Single `DocumentLinkBinding` type using `DocumentLocator` for both source and target
- `DocumentLocator` abstract type allows future addressing modes without changing binding type
- DocumentLink bindings are Documents using `@document` macro for editor integration

## Implementation Order

1. Implement `DocumentLocator` (see `plan/pending/document-locator.md`)
2. DocumentLink domain types + query API (`DocumentLink.jl`)
3. DocumentLink operations
4. DocumentLink-centric projections (`DocumentLinkToSyntax.jl`)
5. Integration (update `Projectured.jl`)
6. Testing

## Phase 1: DocumentLink Domain Types

### File: `program/src/document/DocumentLink.jl`

**Type Hierarchy:**
```julia
abstract type DocumentLinkDocument <: Document end
```

**Concrete Types (all use `@document` macro, which auto-wraps fields into `Cell`):**
- `DocumentLinkBinding <: DocumentLinkDocument` - Edge connecting source document to target element:
  - `source::DocumentLocator` - Source document locator (contains the link content)
  - `target::DocumentLocator` - Target document locator (what the link points to)
  - `selection::Reference` - For document contract
- `DocumentLinkRegistry <: DocumentLinkDocument` - Global document storing:
  - `locators::CellVector` - Optional catalogue of registered DocumentLocator values
  - `bindings::CellVector` - All DocumentLinkBinding instances
  - `source_index::Dict{DocumentLocator, Vector{DocumentLinkBinding}}` - Index for O(1) source queries
  - `target_index::Dict{DocumentLocator, Vector{DocumentLinkBinding}}` - Index for O(1) target queries
  - `selection::Reference` - For document contract

**Note:** All types use `@document` macro which auto-converts field type annotations to `Cell` — write logical types (e.g., `source::DocumentLocator`), not `Cell{DocumentLocator}`. The macro also generates an immutable `I`-prefixed variant and conversion constructors. No explicit `id` field — document link bindings are identified by their cell references in the registry.

**Global Registry:** `global_document_link_registry::Cell{Union{Nothing, DocumentLinkRegistry}}` with `get_document_link_registry()` accessor. Registry is reactive so projections can depend on it.

## Phase 2: Query API

**File:** `program/src/document/DocumentLink.jl` (same file as domain types)

Node equality uses `locator_equal(a, b)` from `DocumentLocator`.

**Functions on `DocumentLinkRegistry`:**
- `add_document_link!(registry, binding)` — push binding into `registry.bindings` and update `source_index` and `target_index`
- `remove_document_link!(registry, binding)` — remove binding by identity and update indexes
- `document_links_from(registry, locator)` — bindings where `source` matches `locator` (uses `source_index` for O(1) lookup)
- `document_links_to(registry, locator)` — bindings where `target` matches `locator` (uses `target_index` for O(1) lookup)
- `document_links_of_source_type(registry, type)` — filter by source document type
- `document_links_between(registry, source_locator, target_locator)` — bindings connecting two locators
- `neighbors(registry, locator)` — all directly connected locators (deduplicated)
- `document_links_for_document(registry, document_locator)` — collect all links where source or target locator points to the given document

## Phase 3: DocumentLink Operations

**File:** `program/src/document/DocumentLink.jl` (same file as domain types)

**Operations:**
- `CreateDocumentLinkOperation` - Create new document link binding
- `DeleteDocumentLinkOperation` - Remove document link binding
- `CleanupStaleDocumentLinksOperation` - Remove document links with invalid locators

**Implementation:** Operations modify global `DocumentLinkRegistry` and are reactive through the cell system. To modify link content, edit the source document directly.

## Phase 4: DocumentLink Projections

**DocumentLinkToSyntax.jl:**
- `DocumentLinkBindingToSyntaxNode` - Project binding with source/target references
- `DocumentLinkRegistryToSyntaxNode` - Project entire registry as syntax tree
- Printer shows locators and projects source document content
- Reader translates edits back to document link operations

**Optional:** `DocumentLinkToJson.jl` for serialization

## Phase 5: Integration Points

**Projectured.jl:**
- `include("common/DocumentLocator.jl")` (must precede document link module)
- `include("document/DocumentLink.jl")`
- Export types, query functions, and operations

**Editor.jl:** Ensure editor can access global `DocumentLinkRegistry`

## Future: Multi-Document Support

Helper functions for per-document persistence: `save_document_links_for_document`, `load_document_links_for_document` using document locators. Cleanup on document close via `CleanupStaleDocumentLinksOperation`.

## Dependencies

- **DocumentLocator** (`plan/pending/document-locator.md`) — must be implemented first
- **ReferenceModule** (`ReferencePath`, `EmptyReferencePath`, `reference_equal`) — must be loaded before this module
