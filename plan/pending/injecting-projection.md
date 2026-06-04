# Injecting Projection — Generic Collection Decorator

A domain-independent projection that splices extra elements into collection-based projection outputs at specified positions, with automatic reference index remapping — enabling any higher-level projection to insert additional elements into tightly-coupled spans without breaking the reference chain.

## Design Rationale

`InjectingProjection` knows nothing about domain, content, source, or state — it has exactly one job: maintain correct index remapping when elements are spliced into a collection. Everything else (what to inject, why, how to project it) is the `InjectionSource` collector's responsibility.

### The dual of `FilteringProjection`

The most direct structural parallel is already in the codebase:

| | `FilteringProjection` | `InjectingProjection` |
|---|---|---|
| Operation | removes elements | adds elements |
| IoMap | `kept_indices::Vector{Int}` | `index_map::Vector{Int}` |
| `map_reference_forward` | skip removed indices | shift past injected indices |
| `map_reference_backward` | reverse kept | reverse with `nothing` for injected |

They are duals and can be stacked in any order inside a `SequentialProjection`; the reference arithmetic composes correctly through the chain.

### Combinations with existing features

- **`SequentialProjection`** — plugs in at any step; the accumulated iomap it threads through `ctx` is exactly what `InjectionSource` needs to resolve input-domain references
- **`TypeDispatchingProjection`** — injected elements can be of any type; dispatch handles them alongside original elements
- **`AnchoredLayout`** — complementary, not competing: `AnchoredLayout` handles *overlay* positioning (annotation bubbles floating beside content), `InjectingProjection` handles *inline* positioning (icons/documents flowing within the text); both can be active simultaneously
- **`Cell` / reactive system** — `InjectionSource` reads visibility cells, per-element `is_visible`, collapsed state — ordinary cell reads; the reactive graph propagates changes with no special support
- **`TextToGraphics` word-wrap** — Phase 3's `TextGraphics` handling is purely additive; existing `TextString`/`TextNewline` processing is untouched
- **`map_reference_forward/backward`** — implements the exact same interface as every other projection; selection, cursor movement, and hit-testing compose through the standard chain
- **Annotation plan's `DecorateWithAnnotations`** — the decorator's `:inline` mode *is* `InjectingProjection`; it builds the `InjectionSource` and delegates the splicing
- **`FilteringProjection` + `InjectingProjection` in sequence** — filter elements out, inject new ones at the resulting positions; each iomap layer composes correctly

Because `InjectingProjection` is a pure index-remapping decorator, it never needs to be updated when new document types, annotation kinds, display modes, or interaction models are added.

## Problem

A projection pipeline like `JsonToSyntax → SyntaxToText → TextToGraphics` produces tightly coupled spans. For example, `SyntaxLeafToText` creates `TextText([open, value, close])` where indices 1,2,3 are hardwired in reference mapping (`map_reference_forward`/`backward`, `_leaf_cursor`, `_pos_to_selection`). Splicing an extra element between `value` and `close` shifts index 3→4, breaking all downstream reference arithmetic.

The `AnchoredLayout` (see `anchored-layout.md`) solves *overlay* positioning. This plan solves *inline* positioning: splicing elements *into* the collection flow so they participate in word-wrapping and reflow.

## Phase 1: InjectingProjection — Generic Collection Decorator

### File: `program/src/projection/generic/Injecting.jl`

A domain-independent projection that inserts extra elements into a collection at specified positions, with automatic index remapping. Follows the pattern of `FilteringProjection` (which removes elements and remaps indices).

**`InjectionSpec`** — describes one injection:
```julia
struct InjectionSpec
    target_document::Any             # direct Cell reference to inject after (or nothing)
    target_reference::ReferencePath  # reference path to inject after (or EmptyReferencePath)
    position::Symbol                 # :before or :after the target
    element::Any                     # the document element to splice in
end
```

Two anchor modes:
- **Direct**: `target_document` — scan the collection for this element by identity (`===`), inject before/after it
- **Reference-based**: `target_reference` — resolve to a collection index (e.g. `elements[2]`), inject before/after that index

**`InjectionSource`** — deferred spec builder called at print-time with the pipeline context:
```julia
struct InjectionSource
    collect::Function  # (original_input, accumulated_iomap) → Vector{InjectionSpec}
end
```

- `original_input` — the document at the start of the pipeline (e.g. `JsonObject`); used for graph traversal in the collector
- `accumulated_iomap` — the composed iomap from all pipeline steps preceding the injection point; the collector calls `map_reference_forward(accumulated_iomap, input_domain_ref)` to translate input-domain references (e.g. a JSON cell reference) into the current domain (e.g. a Text span)

**`InjectingProjection`**:
```julia
struct InjectingProjection <: Projection
    source::Union{Vector{InjectionSpec}, InjectionSource}
end
```

Accepts either a pre-built list (for static injection) or an `InjectionSource` (for dynamic injection from the document graph).

**`InjectingProjectionIoMap`**:
```julia
struct InjectingProjectionIoMap <: IoMap
    projection::Any
    input::Any
    output::Any
    index_map::Vector{Int}       # output index → input index (0 for injected elements)
    injected_iomaps::Vector{Any} # per-injected-element iomap from its own sub-projection
end
```

`injected_iomaps[k]` is the iomap returned by the k-th injected element's own sub-projection. It is used by `projection_read` to route events into the injected document's reader.

### projection_print

0. If `source` is an `InjectionSource`, call `source.collect(original_input, accumulated_iomap)` to obtain the `Vector{InjectionSpec}`. Both `original_input` (the pipeline's initial input) and `accumulated_iomap` (composed iomap from all preceding steps) are threaded through `ctx` by `SequentialProjection`.
1. Read the input collection elements
2. For each `InjectionSpec`, resolve where it goes:
   - Direct: scan for `target_document ===` match, get input index
   - Reference: parse the reference path to get the input index
3. Build output collection with injected elements spliced in at the computed positions
4. Build `index_map`: for each output element, store the original input index (or `0` for injected elements)
5. Return `InjectingProjectionIoMap`

### map_reference_forward

Translate an input-domain collection reference to the output domain:
```
input[i] → output[j]  where j accounts for injections before position i
```
Lookup: find `j` such that `index_map[j] == i`. If `i` was removed (shouldn't happen — injecting only adds), return `nothing`.

### map_reference_backward

Translate an output-domain collection reference to the input domain:
```
output[j] → input[index_map[j]]  if index_map[j] > 0
output[j] → nothing              if index_map[j] == 0 (injected element)
```

### projection_read

For events routed to an injected element (`index_map[j] == 0`): look up the corresponding `injected_iomaps[k]` and forward the event to that iomap's projection reader. This allows the injected document to handle interaction (toggle collapsed/expanded, scroll, edit) through its own reader without the main pipeline knowing about it.

For events routed to an original element: remap the index back to input space and forward to the inner projection.

## Phase 2: Usage Pattern — Graph-Based Injection via InjectionSource

`InjectingProjection` is a low-level mechanism. Injection specs are produced by a **collector** supplied as an `InjectionSource` — a callback called at print-time with the full pipeline context. This is the bridge between input-domain knowledge (e.g. which JSON element has an annotation) and injection-point-domain knowledge (which Text span to inject after).

The collector receives `(original_input, accumulated_iomap)` and:
1. Traverses the document graph from `original_input` (e.g. walks the annotation registry)
2. For each relevant binding, calls `map_reference_forward(accumulated_iomap, input_domain_ref)` to resolve the input-domain target to the current domain
3. Projects the associated document (annotation, cross-document data, etc.) to an element in the injection-point domain — **independently**, using its own sub-pipeline
4. Returns a `Vector{InjectionSpec}` with current-domain targets and pre-projected elements

The injected element never flows through the main pipeline steps. It is projected directly to the injection-point domain by the collector.

### Example: Annotation injection

Annotations are bound to JSON elements in the annotation registry. The pipeline wires the `InjectionSource` inline between `SyntaxToText` and `TextToGraphics`; the accumulated iomap (iomap₁ ∘ iomap₂) is passed to the collector at print-time:

```julia
SequentialProjection(
    JsonToSyntax(),          # step 1 → iomap₁
    SyntaxToText(),          # step 2 → iomap₂  (composed: iomap₁ ∘ iomap₂)
    InjectingProjection(     # step 3 — called with (json_doc, iomap₁∘iomap₂)
        InjectionSource() do input, full_iomap
            # traverse annotation graph in JSON domain
            # map_reference_forward(full_iomap, json_ref) → text_span
            # project annotation → TextGraphics
            [InjectionSpec(text_span, :after, TextGraphics(icon))]
        end
    ),
    TextToGraphics(),        # step 4 — sees TextGraphics as inline box
)
```

**What the collector does internally:**
1. Walk the annotation registry, find annotations targeting JSON elements in `input`
2. For each: `text_span = map_reference_forward(full_iomap, json_string_ref)` — translates the JSON-domain reference to the Text-domain span
3. Project `annotation.content → [sub_pipeline] → icon_canvas` — independently, using its own inner pipeline
4. Return `InjectionSpec(text_span, :after, TextGraphics(icon_canvas))`

**Key insight**: The injected element is projected independently by the collector straight to `TextGraphics`. It never flows through `JsonToSyntax` or `SyntaxToText` — those are for the main document only.

The same pattern applies to any cross-document data propagation (author names, type hints, lint warnings from an analysis document): the collector traverses whatever graph is relevant and returns specs with elements already in the injection-point domain.

### Complex injected documents

An injected element can be arbitrarily complex — not just a static icon. For example, an email document attached to a JSON field can have its own collapsed/expanded projection:

```julia
# The collector projects the email through its own sub-pipeline:
email_canvas = projection_print(EmailToGraphics(collapsed=email.is_collapsed), email_doc, ...)
# Wrap the resulting GraphicsCanvas as a TextGraphics inline box:
TextGraphics(email_canvas; font=base_font)  # dimensions read from email_canvas.w / .h
```

**Reactive collapsed/expanded**: `email_canvas.w` and `email_canvas.h` are reactive cells. When `email.is_collapsed` changes (e.g. user clicks the icon), the sub-projection recomputes, the canvas dimensions change, and `TextToGraphics` automatically re-lays out the paragraph with the new inline box size — without any special handling in the main pipeline.

**Interaction routing**: clicks on the injected email box are forwarded via `injected_iomaps[k]` to the email's own projection reader, which handles toggle, scroll, text selection, etc. The main document's reader never sees these events.

### Visibility control

Show/hide of injected elements is handled via reactive cells — no new projection machinery required.

**Global toggle** — a single `Cell{Bool}` that the collector reads, registering a dependency. When toggled, all downstream cells including `TextText.elements` are invalidated; `TextToGraphics` re-lays out the paragraph on the next render:

```julia
show_annotations = Cell(true)

InjectionSource() do input, full_iomap
    show_annotations[] || return InjectionSpec[]   # cell read → dependency registered
    # normal collection: walk registry, map refs, project visuals ...
    specs
end
```

**Per-element visibility** — same pattern with a cell per annotation or injected document:

```julia
binding.annotation.is_visible[] || continue   # skip hidden annotations
```

**Operation** — writing to the cell is all that is needed:

```julia
evaluate_operation(op::HideAnnotationsOperation) = show_annotations[] = false
evaluate_operation(op::ShowAnnotationsOperation) = show_annotations[] = true
```

No iomap rebuilding, no projection changes — the cell system propagates the invalidation and the paragraph reflows automatically.

### SequentialProjection threading requirement

`SequentialProjection` must thread `original_input` and the composed iomap through `ctx` at each step so that `InjectingProjection.projection_print` can extract them and forward them to the collector.

### Injection point and element domain

`InjectingProjection` operates on `TextText.elements` (a `CellVector`), not on the `TextText` itself. It takes a `TextText` as input and produces a new `TextText` with a modified `elements` collection. The iomap stores the index mapping at the elements level.

## Phase 3: TextToGraphics TextGraphics Support

### File: `program/src/projection/primitive/TextToGraphics.jl`

`TextToGraphics` currently skips non-`TextString` spans (line 219: `span isa TextString || continue`). To support inline graphics injected by `InjectingProjection`, add handling for `TextGraphics`:

- When encountering a `TextGraphics` span during word-wrap:
  1. Read its `content` (a `Document`, typically a `GraphicsCanvas`)
  2. Read its `w`/`h` cells for sizing — these are reactive, so a collapsed-to-expanded toggle causes automatic reflow
  3. Treat it as an atomic inline box: advance the cursor by `w`, use `h` for line height
  4. Emit the content canvas at the current `(cx, cy)` position
  5. Record it in `coord_map` so hit-testing and event routing work

This makes `TextGraphics` a first-class inline element that participates in word-wrap and reflow, just like a `TextString` but rendered as an arbitrary `GraphicsCanvas` — which may itself be the result of a complex independent projection (e.g. a collapsed email icon or a full expanded email view).

## Phase 4: Integration

### File: `program/src/Projectured.jl`

- Add `include("projection/generic/Injecting.jl")`
- Export `InjectingProjection`, `InjectingProjectionIoMap`, `InjectionSpec`

## Implementation Steps

1. Create `InjectingProjection` in `projection/generic/Injecting.jl` with index remapping
2. Add `TextGraphics` handling to `TextToGraphics` word-wrap engine
3. Wire into `Projectured.jl`
4. Add tests

## Future Extensions

- **Reactive injection source**: wrap the `InjectionSource` in a `Cell` so that changes in the document graph (annotations added/removed, cross-document references updated) trigger re-collection without rebuilding the projection
- **Multi-domain injection**: extend `InjectingProjection` to work with `SyntaxNode.children`, `JsonArray` entries, or any `CellVector`-backed collection
- **Injection ordering**: when multiple injections target the same position, allow explicit ordering
- **Zero-width injection**: support injections that don't occupy text space but still emit a graphics marker (e.g. breakpoint dots in a gutter)
- **Composite injection**: an injected element is itself a full document with its own projection pipeline and interaction model — ranging from a simple icon to a fully interactive sub-editor (collapsed/expanded email, expandable chart, nested form)
