# ProjecturedBase — architecture

Contributor-facing guide to the internal structure of the `ProjecturedBase`
package. `ProjecturedBase` is the **domain-independent vocabulary and
frameworks** — sitting between the kernel engine and the concrete domain
slices (`kernel ← base ← visual ← domain`). Its membership rule is *"the
type is generic enough that every domain reuses it, so it doesn't belong
in any single slice"*.

## Concept folders

base is an **acyclic DAG of concept folders** — sliced like the `domain`
package, not stacked in ordered layers. Each folder is one cohesive concept and
holds whatever kinds it needs: its documents *and* its projections *and* its
operations, together. Dependencies flow one way (a lower concept never names a
higher one), and the guard validates the DAG through the topological include
order of `ProjecturedBase.jl` — no `layers` indices are declared (see
[test/ProjecturedBaseTest.jl](../test/ProjecturedBaseTest.jl), `test_base_layering`).

**Membership rule:** a type belongs in base only if it is **shipped for reuse by
every domain** and is **domain-independent** (no domain concept in its
structure). `Collection`, `Primitive`, `Versioning` pass; `Json`, `Xml`, … don't
— they are per-slice domain content.

### domain/ — what a document domain *is*

- **`DocumentCore.jl`** — `DocumentBase`, `DocumentNothing`, `DocumentInsertion`,
  `DocumentReference`: the empty document, the insertion placeholder, and a
  reference-holding document. Kernel document/reference contracts only.
- **`Domain.jl`** — the `@domain` macro (generates a domain's root / `*Nothing` /
  `*Insertion` kit + Insert gesture + insertion traits from one line) and the
  reflection-based insertion completion (`insertion_candidates`,
  `complete_insertion`, `resolve_insertion`). `DocumentNothing` /
  `DocumentInsertion` implement the traits it anchors.

### collection/ — the reactive containers and their projections

The container how-to is [collection.md](collection.md).

- **`Collection.jl`** + the flattened fragments `CellVector` / `CellMatrix` /
  `CellTable` / `ListNode`: the reactive sequence and grid containers every domain
  reuses. Registers `child_reference_steps(::CellVector)` onto the kernel's
  `OperationModule` so the pre-order walk driving `SelectNextInsertionOperation`
  picks up `CellVector` elements without the kernel naming the concrete type.
- **`Sorting.jl`** (`SortingProjection`) and **`Filtering.jl`**
  (`FilteringProjection`) — the collection-shaped projections (sort / keep by a
  key or predicate); they dispatch on `CellVector`.

### primitive/ — the scalar documents and their reader

- **`Primitive.jl`** — `PrimitiveBool`, `PrimitiveNumber`, `PrimitiveString`,
  `PrimitiveInsertion`: the editable scalar documents with selection + identity.
  Owns `ReplaceStringRangeOperation` / `ReplaceNumberRangeOperation` and registers
  their `reroot_operation` methods onto the kernel's `OperationModule`.
- **`ReaderDefaults.jl`** — the Primitive-op branches of the default `read_intent`
  (`read_intent(::Projection, iomap, ::Replace…RangeOperation)`), more specific
  than the kernel's catch-all via multiple dispatch. Primitive's reader half.

### projection/ — the domain-free projection algebra (no documents)

The projection *machinery* (the four generic functions, IO maps, `@projection`,
the template engine, gesture bindings) lives in the kernel; every **concrete**
domain-independent projection lives here. None of these owns a document — they
operate over *any* input by structure.

- **`generic/`** — `IdentityProjection`, `ReversingProjection`,
  `ConstantProjection`, `FocusingProjection` (domain-independent by structure).
- **`higherorder/`** — the combinators: `ChainingProjection`,
  `TypeDispatchingProjection`, `RecursiveProjection`, `SwitchingProjection`,
  `PredicateDispatchingProjection`, `ReferenceDispatchingProjection`,
  `NestingProjection`, `WindowInputUnwrappingProjection`. (The two `RuleIoMap`
  disambiguations keyed on `RecursiveProjection` live in
  `primitive/ReaderDefaults.jl`, since the kernel's `ProjectionTemplate` cannot
  name a base projection.)
- **`compound/`** — `HigherOrderCompound.jl` / `GenericCompound.jl`: the compound
  projection aggregates (build on `Recursive` / `ReferenceDispatching` / `Nesting`).
- **`Searching.jl`** (`SearchingProjection`, collects objects whose field matches a
  `Regex`) and **`Copying.jl`** (`CopyingProjection`, domain-independent deep copy;
  the workhorse most compound projections build on).

### dragging/, versioning/, reflection/ — optional feature slices

Each is a domain-neutral overlay: a document paired with the projection that
interprets or eliminates it.

- **`dragging/`** — `Dragging.jl` (`DraggingState`, a transparent reorder-region
  wrapper) + `DraggingProjection.jl` (a press→drag→drop reader emitting a
  `MoveRangeOperation` that relocates raw `Cell`s within a `CellVector`,
  preserving identity; transparent printer).
- **`versioning/`** — `Versioning.jl` (`VersionedObject` / `ObjectVersion` /
  `VersionProperties` + the `VersionCriterion` hierarchy and `select_version`) +
  `VersioningToAny.jl` (`VersioningToAnyProjection`: selects one version by
  criterion and projects its value in place of the wrapper; a School-A reader
  re-roots value edits under `versions[i].value`).
- **`reflection/`** — `BoundedSync.jl` (the `UnsyncedDocument` marker document +
  the `SyncPolicy` / `DepthPolicy` policies implementing the kernel's
  policy-parameterised `sync_document!` seam) + `DocumentReflection.jl` (reflects
  an arbitrary Julia object into a `ReflectedNode` tree, synced under the same
  policy and marker). The rendering projection `ReflectionToWidget` lives in
  `visual/widget/`, across the seam.

### serialization/ — exact binary persistence

- **`BinarySerialization.jl`** — exact, lossless binary persistence via Julia's
  `Serialization` stdlib. The one customization: a `Cell` serializes as **just its
  value**, pruning the reactive graph at every cell boundary. Kernel-only imports.

A human-readable **`fileformat/`** folder (`NaturalFormat` + `DocumentFile`) is
planned once those framework skeletons are inverted off their hard-coded
per-domain wiring onto the seam pattern; see
[the plan](../../../plan/pending/base-package-structure.md).

`ScreenDocument` / `WindowManaging` do not live in base — window things are
`visual/screen/`; only the Display device and display-size seam stay in the kernel.

## Alias preamble

Files under this package's `main/` folders reference kernel modules via
relative `..XxxModule` imports (e.g. `import ..CellModule: Cell`). Those
resolve through the `const CellModule = ProjecturedKernel.CellModule`
declarations at the top of `ProjecturedBase.jl`. The base guard's
`alias_names(top_file)` collector recognises them as valid dep targets
even though `CellModule` is not defined by any base file.

## Downward edges

base imports only kernel contracts (through the `..XxxModule` aliases): the cell,
document, reference, selection, operation, event, projection, iomap, gesture, and
printer-context modules. That is the whole import surface — no visual, no domain.
