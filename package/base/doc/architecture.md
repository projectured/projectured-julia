# ProjecturedBase — architecture

Contributor-facing guide to the internal structure of the `ProjecturedBase`
package. `ProjecturedBase` is the **domain-independent vocabulary and
frameworks** — layered between the kernel engine and the concrete domain
slices (`kernel ← base ← visual ← domain`). Its membership rule is *"the
type is generic enough that every domain reuses it, so it doesn't belong
in any single slice"*.

## Layers

```
Layer 1 — document       Collection, DocumentCore, Primitive, Dragging
                         (concrete engine documents everything ships with)
Layer 2 — projection     generic/ (Identity, Reversing, Constant, Focusing) +
                         higherorder/ (Chaining, TypeDispatching, Recursive,
                         Switching, PredicateDispatching, ReferenceDispatching,
                         Nesting, EnvelopeUnwrapping) + Sorting, Filtering,
                         Searching, Copying, ReaderDefaults, DraggingProjection
                         (the domain-independent projection algebra + reader
                         defaults; the projection interface/engine stays in kernel)
Layer 3 — serialization  BinarySerialization
                         (domain-independent persistence framework)
```

Depend downward-only: `serialization → projection → document → kernel`.
Machine-enforced by the layered guard in
[test/runtests.jl](../test/runtests.jl); LAYERS is
`["document","projection","serialization"]`.

## What lives in each layer

### document — the concrete engine documents

The how-to for the shipped collection containers (`CellVector`, `CellMatrix`,
`CellTable`, `ListNode`) and the Primitive documents is the base
document-layer guide, [collection.md](collection.md).

**Membership test for this layer:** a document type belongs in base/document if
it is **shipped for reuse** by every domain (not editor-loop machinery) and is
**domain-independent** (no domain concept in its structure). Collection and
Primitive pass; Json, Xml, etc. don't — they are per-slice domain content.

- **`Collection.jl`** — the `CollectionModule` aggregator; one fragment file
  per shape under `collection/` (`CellVector`, `CellMatrix`, `CellTable`,
  `ListNode`): the reactive sequence and grid containers every domain
  reuses. Registers the seam method
  `child_reference_steps(::CellVector)` onto the kernel's
  `OperationModule` so the pre-order document walk driving
  `SelectNextInsertionOperation` picks up CellVector elements without
  the kernel referencing the concrete type.

- **`DocumentCore.jl`** — `DocumentBase`, `DocumentNothing`,
  `DocumentInsertion`, `DocumentReference`: domain-independent document
  vocabulary (the empty document, the insertion placeholder, a
  reference-holding document). Depends only on the kernel document/reference
  contracts. Moved down from the domain `core/` slice, which it emptied.

- **`Dragging.jl`** — `DraggingDocumentModule`: `DraggingState`, a
  transparent wrapper marking a sub-tree as a drag-and-drop reorder region.
  Kernel-only document contracts; the gesture interpretation lives in the
  projection layer's `DraggingProjection`. Moved down from the domain
  `dragging/` slice (nothing about reordering a `CellVector` is
  domain-specific).

- **`Primitive.jl`** — `PrimitiveBool`, `PrimitiveNumber`,
  `PrimitiveString`, `PrimitiveInsertion`: the editable
  domain-independent scalar documents with selection + identity. Owns
  `ReplaceStringRangeOperation` / `ReplaceNumberRangeOperation`, the two
  splice-range operations, and registers their `reroot_operation`
  methods onto the kernel's OperationModule.

`ScreenDocument.jl` does not live here — the couple `ScreenDocument ↔
WindowManagingProjection` belongs in `visual/screen/` per the architecture
rules (window things are visual; only the Screen device and display-size
seam stay in the kernel).

### projection — the domain-independent projection algebra

The projection *machinery* (the four generic functions, IO maps, the
`@projection` macro, the projection-template engine, gesture bindings) lives in
the kernel's projection layer. Every **concrete** projection is
domain-independent framework and lives here.

The generic + higher-order combinators lead the layer (they depend only on the
kernel projection interface, and the document-shaped projections below build on
them — Sorting uses `IdentityProjection`; the compound aggregates use
`Recursive`/`ReferenceDispatching`/`Nesting`):

- **`generic/`** — the generic (domain-independent-by-structure) projections:
  `IdentityProjection`, `ReversingProjection`, `ConstantProjection`,
  `FocusingProjection`.
- **`higherorder/`** — the higher-order combinators: `ChainingProjection`,
  `TypeDispatchingProjection`, `RecursiveProjection`, `SwitchingProjection`,
  `PredicateDispatchingProjection`, `ReferenceDispatchingProjection`,
  `NestingProjection`, `EnvelopeUnwrappingProjection`. (Both folders moved down
  from the kernel projection layer — they are domain-independent framework, not
  engine. The two `RuleIoMap` disambiguations keyed on `RecursiveProjection`
  live beside the reader defaults in `ReaderDefaults.jl`, since the kernel's
  `ProjectionTemplate` cannot name a base projection.)

The document-shaped projections consume/produce base document types (CellVector,
Primitive) but are otherwise domain-agnostic:

- **`Sorting.jl`** — `SortingProjection`: sorts collection children by
  a key.
- **`Filtering.jl`** — `FilteringProjection`: keeps children matching a
  predicate.
- **`Searching.jl`** — `SearchingProjection`: collects objects whose
  field matches a Regex.
- **`Copying.jl`** — `CopyingProjection`: domain-independent deep copy
  with iomaps; the workhorse most compound projections build on.
- **`ReaderDefaults.jl`** — the Primitive-op branches of the
  default `read_intent`. Adds more-specific
  `read_intent(::Projection, iomap, ::Replace…RangeOperation)` methods
  that take precedence over the kernel's catch-all via multiple
  dispatch.
- **`DraggingProjection.jl`** — `DraggingProjection`: a higher-order
  projection over `DraggingState` whose reader runs a press→drag→drop
  state machine, emitting a `MoveRangeOperation` that relocates raw `Cell`s
  within a `CellVector` (preserving element identity). Transparent printer.
  Imports only kernel gesture/operation modules + the base document types;
  moved down from the domain `dragging/` slice.

### serialization — the persistence frameworks

- **`BinarySerialization.jl`** — exact, lossless binary persistence via
  Julia's `Serialization` stdlib. The one customization: a `Cell`
  serializes as **just its value**, pruning the reactive graph at every
  cell boundary. Kernel-only imports.

Planned additions to this layer: `NaturalFormat.jl` (framework +
per-slice format registry) and `DocumentFile.jl` (extension-dispatched
entry point). See the plan file for scope.

## Alias preamble

Files under this package's `main/` folders reference kernel modules via
relative `..XxxModule` imports (e.g. `import ..CellModule: Cell`). Those
resolve through the `const CellModule = ProjecturedKernel.CellModule`
declarations at the top of `ProjecturedBase.jl`. The base guard's
`alias_names(top_file)` collector recognises them as valid dep targets
even though `CellModule` is not defined by any base file.

## Downward edges

- `..CellModule`, `..DocumentModule`, `..ReferenceModule`,
  `..OperationModule` (kernel).
- `..MouseModule`, `..ModifiersModule` (kernel — the mouse gesture + modifier
  types `DraggingProjection`'s reader dispatches on).
- `..GestureModule` (kernel — alias only; unused now that `ScreenDocument`
  lives in `visual`, not here).
- `..BackendModule` (kernel — alias only; the `Backend` abstract a future
  serialization framework might target, currently unused).

That's the whole import surface. No visual, no domain.
