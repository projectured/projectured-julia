# Annotation Domain

The Annotation domain provides a generic system for decorating any document element with annotations. Annotations live in a global reactive registry separate from the documents they annotate — no modification to existing document types is required.

**Key Concept**: Annotation semantics emerge from the content type, not from predefined annotation subtypes. A comment is an annotation whose content is a string; a highlight is an annotation whose content is a color. Projections dispatch on `typeof(annotation.content)` to determine rendering.

## Types

- **Annotation**: Generic annotation holding arbitrary content
- **AnnotationBindingDirect**: Binds an annotation to a target via direct cell reference (definitive — stale if target is destroyed)
- **AnnotationBindingReferencePath**: Binds an annotation to a target via a reference path (dynamic — evaluated when needed)
- **AnnotationRegistry**: Global document storing all annotations and their bindings

## Concepts

### Annotations Are Content-Typed

Rather than defining subtypes for each annotation kind, a single `Annotation` type holds a `content` field that can be any document. The projection system uses type dispatching to render annotations differently based on their content:

```julia
# A comment — content is a string
Annotation("This needs review")

# A highlight — content is a color
Annotation(StyleColor(1.0, 1.0, 0.0, 0.3))

# A structured tag — content is an object
Annotation(JsonObject("label" => "TODO", "priority" => 1))
```

### Two Binding Modes

Annotations are bound to targets through binding objects:

- **Direct binding**: Holds a direct reference to the target document in a cell slot. This is definitive — the annotation is permanently bound to that specific document instance. If the target is destroyed, the binding becomes stale.

- **ReferencePath binding**: Holds a reference path that is evaluated dynamically by projections. This enables annotations on documents that may not yet be loaded, or that are identified by their position in a tree rather than by identity.

### Global Registry

All annotations and bindings are stored in a single global registry. This design enables:

- Annotating any document (JSON, XML, Text, etc.) without modifying its type
- Cross-document annotations that reference elements in different documents
- A graph structure where annotations can themselves be annotated
- Lazy creation — the registry only exists when the first annotation is added

### Annotation Graph

Because annotations are documents and targets can be any document, annotations can reference other annotations. This creates a graph structure enabling:

- Replies to annotations (annotation whose target is another annotation)
- Meta-annotations (annotating an annotation with additional metadata)
- Annotation threads (chains of reply annotations)

## Examples

```julia
# Create an annotation
comment = Annotation("Consider renaming this variable")

# Bind it to a target document directly
binding = AnnotationBindingDirect(comment, some_json_string)

# Bind it to a target dynamically via reference path
binding = AnnotationBindingReferencePath(comment, @reference entries{1}.value)

# Access the global registry
registry = get_annotation_registry()

# Annotations and bindings are stored in the registry's collections
push!(registry.annotations, Cell(comment))
push!(registry.bindings, Cell(binding))
```

## Selection

Each annotation type has a `selection::Reference` field for cursor navigation. Selection paths descend into:

- Annotation content: `.content` — enters the content document
- Binding annotation: `.annotation` — enters the referenced annotation
- Binding target: `.target_document` (direct) or `.reference` (reference path)
- Registry collections: `.annotations{i}` or `.bindings{i}` — enters collection elements

## Projection Approaches

Annotations support two complementary projection strategies:

- **Annotation-centric**: Start from the registry and project annotations as a tree, showing targets organized under their annotations
- **Decorator**: Insert into an existing document's projection pipeline to add visual decorations (inline markers, sidebars, tooltips) at annotated locations

## Key Features

- Any document can be annotated without modification to its type
- Annotation meaning is determined by content, not by subtype
- Graph structure supports annotations on annotations
- Reactive — changes to annotations propagate through the projection pipeline
- Two binding modes for different binding semantics
