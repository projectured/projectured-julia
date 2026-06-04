# Annotation Feature Implementation Plan

This plan implements a generic annotation system that allows decorating any document element with annotations through a global annotation graph structure, supporting both direct and rule-based annotation binding with maximum flexibility for future extensions.

## Overview

Create a new Annotation domain with a global registry document that stores annotations and their relationships in a graph structure. Annotations can reference any document element and can themselves be annotated, enabling recursive annotation capabilities.

## Phase 1: Annotation Domain Types

### File: `program/src/document/Annotation.jl`

**Type Hierarchy:**
```julia
abstract type AnnotationDocument <: Document end
abstract type AnnotationBinding <: AnnotationDocument end
```

**Concrete Types (all use `@document` macro, which auto-wraps fields into `Cell`):**
- `Annotation <: AnnotationDocument` - Generic annotation type with:
  - `content::Any` - Flexible content (can be structured data)
  - `selection::Reference` - For document contract
- `AnnotationBindingDirect <: AnnotationBinding` - Direct annotation binding with:
  - `annotation::Annotation` - Reference to annotation (direct cell reference)
  - `target_document::Any` - Direct slot pointing to target document (definitive, destroyed if target destroyed)
  - `selection::Reference` - For document contract
- `AnnotationBindingReferencePath <: AnnotationBinding` - Dynamic annotation binding with:
  - `annotation::Annotation` - Reference to annotation (direct cell reference)
  - `reference::ReferencePath` - Reference path for dynamic binding (evaluated by projection when needed)
  - `selection::Reference` - For document contract
- `AnnotationRegistry <: AnnotationDocument` - Global document storing:
  - `annotations::CellVector` - All annotations
  - `bindings::CellVector` - All annotation bindings
  - `selection::Reference` - For document contract

**Note:** All types use `@document` macro which auto-converts field type annotations to `Cell` — write logical types (e.g., `content::Any`), not `Cell{Any}`. The macro also generates an immutable `I`-prefixed variant and conversion constructors. No explicit `id` field — annotations are identified by their cell references in the registry.

**Global Registry Management:**
- `global_annotation_registry::Cell{Union{Nothing, AnnotationRegistry}}` - Reactive cell holding the registry (initialized to `Cell(nothing)`)
- `get_annotation_registry()` - Reads the cell, creates the registry on first access if needed
- Registry is a reactive `Cell` so projections can depend on it and recompute when annotations change
- Documents don't need their own annotation registry field - all annotations go through the global registry
- This allows any document (JSON, XML, etc.) to be annotated without modification
- When a JSON document is opened and the user adds an annotation, the global registry is automatically created and used

**Registry Architecture Decision:**

**Considered Approaches:**
1. **Global Registry** (chosen): Single entry point for all annotations
2. **Per-Document Registry**: Optional registry field on each document

**Rationale for Global Registry:**
- **Zero modification**: Annotate any document (JSON, XML, etc.) without changing document types
- **Simpler implementation**: Single source of truth, easy to access from anywhere
- **Cross-document support**: Enables annotations that reference multiple documents
- **Lazy creation**: Registry only created when first annotation is added
- **Maximum flexibility**: Immediate use without infrastructure changes
- **Future evolution**: Can add per-document scoping later if needed

**Trade-offs:**
- Global state management (acceptable for initial implementation)
- Harder to scope annotations to specific documents (can add later)
- Persistence challenges (can be addressed with document-specific storage strategies)

**Per-Document Registry Rejected Because:**
- Requires modification to `Document` base type or wrapper pattern
- More complex implementation (handle documents with/without registries)
- Changes needed to existing document types
- Cross-document annotations harder to manage

**Design Decision: Generic `content::Any` over Predefined Annotation Subtypes**

Predefined types like `AnnotationComment`, `AnnotationHighlight`, `AnnotationTag` were considered and rejected:
- **Redundant**: `content::Any` already allows type dispatch on the content itself — projections dispatch on `typeof(annotation.content)` via `TypeDispatchingProjection`
- **Couples semantics to data**: In a projectional editor, meaning comes from the projection, not the data structure
- **Limits extensibility**: Every new annotation kind would require a new type + new projection methods
- **Precedent in codebase**: `JsonObjectEntry` uses `value::Document`, `SyntaxLeaf` uses `value::Any`, `FocusingProjection` uses `part_type::Any` — all generic, not predefined

Instead, annotation semantics emerge naturally from content type:
```julia
Annotation("This needs review")                            # comment
Annotation(StyleColor(1.0, 1.0, 0.0, 0.3))                # highlight
Annotation(JsonObject("label" => "TODO", "priority" => 1)) # tag
```

**Other Design Decisions:**
- Generic `content::Any` allows maximum flexibility for different annotation content types (the `@document` macro wraps it in a `Cell` automatically)
- Separate binding types for different binding semantics:
  - `AnnotationBindingDirect` - direct slot to target (definitive, destroyed if target destroyed)
  - `AnnotationBindingReferencePath` - reference path evaluated by projection when needed
- Future binding types can be added as new subtypes of `AnnotationBinding` (e.g., `AnnotationBindingRule`)
- `CellVector` is inherently untyped (`Vector{Cell}`) — no type constraints needed
- Global registry as a reactive `Cell` enables projections to depend on it and recompute on annotation changes
- All annotation types are Documents using `@document` macro to integrate with editor selection system
- Selection fields added to enable cursor navigation within annotation structures

## Phase 2: Reference System Extensions

### File: `program/src/common/Reference.jl` (if needed)

**Potential Additions:**
- `AnnotationReference` - Reference step for pointing to annotations by ID
- Update existing reference types to support annotation graph navigation

**Note:** May not need new reference types if existing `ReferencePath` system can handle annotation IDs through a generic document element representation.

## Phase 3: Annotation Operations

### File: `program/src/document/Annotation.jl` (same file as domain types)

Operations are defined in the domain module alongside types (following the pattern of `Widget.jl`, `Primitive.jl`).

**Operations to add:**
- `CreateAnnotationOperation` - Create a new annotation in the registry
- `DeleteAnnotationOperation` - Remove an annotation from the registry
- `BindAnnotationOperation` - Bind an annotation to a target (direct or reference-based)
- `UnbindAnnotationOperation` - Remove an annotation binding
- `UpdateAnnotationContentOperation` - Modify annotation content
- `CleanupStaleBindingsOperation` - Remove stale bindings referring to deleted objects (triggers GC)

**Implementation:**
- Each operation carries necessary parameters (e.g., annotation cell reference, target path, content)
- `evaluate_operation` methods modify the global `AnnotationRegistry`
- Operations are reactive through the cell system
- `CleanupStaleBindingsOperation` scans registry for `AnnotationBindingDirect` instances where `target_document` is no longer valid and removes them

## Phase 4: Annotation Projections

### Two Projection Approaches

**1. Annotation-centric projections** (annotation point of view):
- Start from annotations and show their referenced objects organized into a tree
- Recursive structure with multiple levels (annotation → target → annotations on target, etc.)
- Projections: `AnnotationToSyntaxTree`, `AnnotationRegistryToSyntaxTree`

**2. Decorator projections** (document point of view):
- Insertable into any sequential document projection pipeline
- Adds additional projected document elements at any level (tree, styled text, etc.)
- Projection: `DecorateWithAnnotations` - generic decorator projection

### File: `program/src/projection/primitive/AnnotationToSyntax.jl`

**Annotation-centric projections:**
- `AnnotationToSyntaxLeaf` - Project annotation content to syntax leaf
- `AnnotationBindingToSyntaxNode` - Project annotation binding with target reference
- `AnnotationRegistryToSyntaxNode` - Project entire registry as syntax tree

**Printer (`projection_print(projection, input, recursion, reference)`):**
- Convert annotations to readable syntax representation
- Show annotation bindings with target references
- Preserve graph structure (annotations referencing annotations)
- Note: signature is 4-arg `(projection, input, recursion, reference)` per codebase convention

**Reader (`projection_read(projection, iomap, event)`):**
- Translate syntax edits back to annotation operations
- Support editing annotation content and bindings

**Reference mapping:**
- `map_reference_forward(projection, iomap, reference)` — translate input-domain references to output-domain
- `map_reference_backward(projection, iomap, reference)` — translate output-domain references back to input-domain
- Default implementations from `ProjectionModule` may suffice for simple cases

### File: `program/src/projection/primitive/AnnotationDecorating.jl`

Placed in `projection/primitive/` (not `projection/generic/`) because it is annotation-domain-aware. Generic projections are domain-independent.

**Decorator projection:**
- `DecorateWithAnnotations <: Projection` - Decorator inserted into any projection pipeline
- Use `@projection` macro if it has reactive Cell fields, otherwise plain `struct <: Projection`
- Takes an input document and adds annotation decorations at appropriate levels
- Parameters: `decoration_mode::Symbol` (e.g., `:inline`, `:sidebar`, `:tooltip`)
- Reads from `global_annotation_registry` cell (reactive dependency)

**Printer (`projection_print(projection, input, recursion, reference)`):**
- Evaluates dynamic bindings (AnnotationBindingReferencePath) to find targets
- Adds decoration elements to the output document based on bindings
- Supports multiple decoration modes for different visualization needs

**Reader (`projection_read(projection, iomap, event)`):**
- Translates edits to decorations back to annotation operations
- Handles decoration-specific interactions

**Reference mapping:**
- `map_reference_forward` / `map_reference_backward` for cursor navigation through decorations

### File: `program/src/projection/primitive/AnnotationToJson.jl` (optional)

**Projection Types:**
- `AnnotationToJson` - Project annotations to JSON domain for serialization

## Phase 5: Integration Points

### File: `program/src/Projectured.jl`

- Add `AnnotationModule` to the module imports
- Export annotation types and operations

### File: `program/src/editor/Editor.jl`

- Ensure editor can access the global `AnnotationRegistry`
- Consider adding annotation-specific editor commands (deferred per user request)

## Implementation Order

1. **Annotation domain types + operations** (`Annotation.jl` — types and operations in same module)
2. **Annotation-centric projections** (`AnnotationToSyntax.jl`)
3. **Decorator projection** (`AnnotationDecorating.jl`)
4. **Integration** (update `Projectured.jl`)
5. **Testing** (create example usage)

## Key Design Principles

- **Maximum flexibility**: Generic types allow future domain-specific annotations
- **Graph structure**: Annotations can reference annotations through the registry
- **Dual binding modes**: Support both direct (static) and dynamic (reference-based) annotation binding
- **Reactive**: All annotation data uses cells for automatic dependency tracking
- **Projectional**: Annotations are first-class documents that can be projected like any other domain
- **Two projection approaches**: Annotation-centric (tree view from annotation perspective) and decorator (add annotations to any document projection)
- **Deferred complexity**: Operations and visualization kept simple per user request, extensible later

## Future Phases

### Phase 6: Multi-Document Support and Persistence

**Document Identification:**
- Add `document_id::String` field to `Annotation` type to track which document owns the annotation (the `@document` macro wraps it in a Cell)
- Add `document_id::String` field to `AnnotationBindingDirect` for cleanup and filtering
- This enables per-document annotation persistence

**Helper Functions:**
- `get_annotations_for_document(document_id)` - Filter global registry for annotations matching document_id
- `get_bindings_for_document(document_id)` - Filter global registry for bindings matching document_id
- `save_annotations_for_document(document_id)` - Extract annotations and bindings for a specific document (returns data structure for persistence)
- `load_annotations_for_document(document_id, annotations_data)` - Load saved annotations into global registry with correct document_id

**Conflict Handling for Multiple Documents:**

**Potential Conflicts:**
1. Multiple documents open simultaneously sharing the same global registry
2. Document-specific annotations loaded from storage need to be merged
3. Stale references when documents are closed/reopened
4. Annotation target identification across different documents

**Resolution Strategies:**
- **Saving**: When saving a document, call `save_annotations_for_document(document_id)` to extract only the annotations and bindings that belong to that document (based on document_id field)
- **Loading**: When loading a document with saved annotations, call `load_annotations_for_document(document_id, annotations_data)` to create new Annotation and AnnotationBinding instances with the correct document_id and add them to the global registry
- **Static bindings**: When a document is closed, run `CleanupStaleBindingsOperation` to remove stale bindings where `target_document` is no longer valid or document_id matches the closed document
- **Dynamic bindings**: `AnnotationBindingReferencePath` uses reference paths that are re-evaluated by projections when documents are reopened, so they remain valid
- **No ID conflicts**: Cell reference-based identification prevents annotation ID collisions between documents
- **Document lifecycle**: Editor should trigger cleanup when documents are closed to remove stale static bindings
