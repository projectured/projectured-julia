# Injecting Projection — Generic Collection Decorator

A domain-independent projection that splices extra elements into collection-based projection outputs at specified positions, with automatic reference index remapping — enabling any higher-level projection to insert additional elements into tightly-coupled spans without breaking the reference chain.

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

**`InjectingProjection`**:
```julia
struct InjectingProjection <: Projection
    injections::Vector{InjectionSpec}  # or a Cell for reactive injection list
end
```

**`InjectingProjectionIoMap`**:
```julia
struct InjectingProjectionIoMap <: IoMap
    projection::Any
    input::Any
    output::Any
    index_map::Vector{Int}  # output index → input index (0 for injected elements)
end
```

### projection_print

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

For events routed to an injected element (`index_map[j] == 0`): return `nothing` by default. Higher-level projections that wrap `InjectingProjection` are responsible for handling interaction with injected elements.

For events routed to an original element: remap the index back to input space and forward to the inner projection.

## Phase 2: Usage Pattern — Graph-Based Injection Collectors

`InjectingProjection` is a low-level mechanism. The injection specs it consumes are produced by **collector functions** — higher-level projections or functions that traverse the document graph, gather related data from any source, and return ready-made `InjectionSpec` items.

Both annotation injection and cross-document data propagation are the same pattern: walk the document graph, collect relevant data, produce specs. The collector is the only part that knows where the data comes from; `InjectingProjection` just splices.

### Example 1: Annotation injection

A collector queries the annotation registry for bindings targeting elements in the current pipeline's input, resolves each binding to an injection position, and builds an `InjectionSpec` with the annotation's projected visual as the element:

```julia
# A collector function traverses the annotation graph:
# 1. Query annotation registry for bindings targeting this document
# 2. For each binding, resolve the target to a collection element
# 3. Project the annotation content into an inline visual
# 4. Build InjectionSpec
spec = InjectionSpec(
    target_text_span,              # the TextString after which to inject
    EmptyReferencePath(),          # (direct mode)
    :after,                        # inject after the target
    TextGraphics(warning_icon;     # the projected annotation visual
        font=target_font)
)
```

### Example 2: Cross-document data propagation

The same mechanism enables propagating data from the broader document graph into the primary pipeline. A collector follows cross-document references and produces injection specs:

```julia
# A collector function traverses the document graph:
# 1. For each JsonObjectEntry, check if it has an `author` reference
# 2. Follow the reference to the Author document
# 3. Extract and project the author name
# 4. Build InjectionSpec to splice the name inline after the JSON value
spec = InjectionSpec(
    target_value_span,             # the TextString of the JSON value
    EmptyReferencePath(),          # (direct mode)
    :after,                        # inject after the value
    TextString(" — by " * author_name;  # projected author name
        font=annotation_font, color=gray)
)
```

### Wiring into the pipeline

```julia
# The collector produces specs; InjectingProjection consumes them:
specs = collect_injections(document, document_graph)  # any collector
pipeline = SequentialProjection(
    JsonToSyntax(),
    SyntaxToText(),
    InjectingProjection(specs),    # ← splice elements into TextText.elements
    TextToGraphics(measure=m),
)
```

**Key insight**: `InjectingProjection` operates on `TextText.elements` (a `CellVector`), not on the `TextText` itself. It needs to be aware that the collection it modifies is a field of the input document. Two approaches:

**Option A**: `InjectingProjection` takes a `TextText` and produces a new `TextText` with a modified `elements` collection. The iomap stores the index mapping for the elements level.

**Option B**: `InjectingProjection` is truly generic and operates on any `CellVector`. The pipeline step that applies it extracts `.elements`, injects, and re-wraps.

Option A is more practical for the initial implementation.

## Phase 3: TextToGraphics TextGraphics Support

### File: `program/src/projection/primitive/TextToGraphics.jl`

`TextToGraphics` currently skips non-`TextString` spans (line 219: `span isa TextString || continue`). To support inline graphics injected by `InjectingProjection`, add handling for `TextGraphics`:

- When encountering a `TextGraphics` span during word-wrap:
  1. Read its `content` (a `Document`, typically a `GraphicsCanvas`)
  2. If it's a `GraphicsCanvas`, read its `w`/`h` cells for sizing
  3. Treat it as an atomic inline box: advance the cursor by `w`, use `h` for line height
  4. Emit the content canvas at the current `(cx, cy)` position
  5. Record it in `coord_map` so hit-testing works

This makes `TextGraphics` a first-class inline element that participates in word-wrap and reflow, just like a `TextString` but rendered as graphics.

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

- **Reactive injection list**: make `InjectingProjection.injections` a `Cell` so changes in the document graph trigger re-injection without rebuilding the projection
- **Multi-domain injection**: extend `InjectingProjection` to work with `SyntaxNode.children`, `JsonArray` entries, or any `CellVector`-backed collection
- **Injection ordering**: when multiple injections target the same position, allow explicit ordering
- **Zero-width injection**: support injections that don't occupy text space but still emit a graphics marker (e.g. breakpoint dots in a gutter)
- **Composite injection**: an injected element is itself a full document that can have its own projection pipeline (e.g. a mini projected document spliced inline)
