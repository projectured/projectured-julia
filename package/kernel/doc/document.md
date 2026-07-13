# The document layer

Layer 2 of the kernel — the **document contract** every concrete document
subtypes and every projection consumes. This page is the layer's structural
overview; for the plain-English "what is a document" guide (domain, document,
selection, operation, projection) see the repo-level
[documentation/concepts.md](../../../documentation/concepts.md).

The layer lives in [main/document/](../main/document/), inside one aggregator
module (`DocumentModule`) split across three fragments that share its namespace:

```
DocumentModule.jl        (DocumentModule)              — the aggregator
        │ imports Cell (from CellModule) and exports every public name
        ├─ Interface.jl   — the contract: Document abstract type + selection
        │                   generics (get/clear/set/with) + read_gesture seam
        ├─ Document.jl    — the shared machinery: generic Base.show, the
        │                   Cell-struct codegen (_cell_* helpers reused by
        │                   @iomap), the @document macro, and the value protocol
        │                   (copy_document, cell_kind, rekind, snapshot,
        │                   hydrate, sync_document!)
        └─ Forward.jl     — the @forward* family (@forward, @forward_vector,
                            @forward_map): expose a nested field's protocol on a
                            wrapper document via generated delegating methods
```

The interface and machinery are only ever imported together, so they share
one `DocumentModule` namespace instead of being separate modules — a
separation would just multiply import headers. They still live in separate
files for readability, but as **fragments** (0-module files sharing the
aggregator's namespace), not separate modules; there is no API boundary
between them.

Concrete engine documents do not live in this layer: `Collection` and
`Primitive` live in `base`, `ScreenDocument` in `visual`. The **document
layer is the contract**; concrete documents belong to the packages built on
top of it.

## The two contracts every concrete document must satisfy

1. **Selection field.** Every `@document struct` must declare a
   `selection::Reference` field (the field name is fixed). The macro stores it
   in a `Cell`; `document.selection` reads through it via the generated
   `getproperty`, so `get_selection(doc)` returns a `ReferencePath` (or
   `nothing`), not the Cell. The default `get_selection(::Document) = doc.selection`
   supplied here works for any document that follows this convention; documents
   with a differently stored selection override it.
2. **Field names ARE the reference vocabulary.** A `FieldReference("foo")` in
   a reference path is resolved by `getfield(document, :foo)` — so struct
   field names are public API. Renaming a field silently breaks every stored
   reference. Choose field names deliberately.

## The selection generics

The four functions declared in `Interface.jl` — `get_selection`,
`clear_selection!`, `set_selection!`, `with_selection` — form the selection
contract. `clear_selection!` and `set_selection!` are open generics with the
generic default supplied by `OperationModule`; concrete documents rarely
override them. `with_selection` is the
one-expression build-and-select form (used by examples, fixtures, clipboard
payloads, and the gesture→replace builders). `get_selection` reads through
the conventional `selection` field.

`@with_selection` is the macro form, for when the selected path has to be *typed
against the document being built* — the `@reference` DSL types a path at runtime,
against the value, so the document has to be bound before the path can be built:

```julia
@with_selection JsonBool(false)             # select the built node whole
@with_selection JsonString("") value{0}     # caret at the path, typed by construction
```

This is what every `@insertion` factory uses; without it each one
needs a `let d = …; with_selection(d, @reference(d, …)) end`.

`read_gesture(document, gesture) -> Union{Operation, Nothing}` is the
projection-independent half of a domain's reader: it maps a backend-agnostic
gesture to an operation expressed against `document`'s own reference
vocabulary. The catch-all implementation on `::Document` lives in the device
layer's `GestureModule` — it walks the reified `@gestures` table, so a domain
authored with `@gestures` needs no hand-written `read_gesture`.

## The shared machinery

`Document.jl` collects the machinery every concrete document reuses:

- **Base.show for `Document`** — a depth-limited debug rendering keyed off
  the `:document_depth` IOContext, so nested documents do not explode. Field
  reads go through `getproperty` (unwrapping Cells); the `selection` field is
  omitted as noise.
- **`@document` macro** — the entry point. It generates the kind-parameterized
  stem (the parametric cell-typed struct, its fast-path auto-wrapping
  constructor, the `R`/`I`/`M` kind aliases and ctors) and layers the Rule Y /
  Rule C constructors on top; its keyword-constructor support comes from the
  cell layer's exported Cell-struct codegen builders (`cell_struct_kw_params`,
  `cell_struct_kwctor` — see the `@cell_struct` section in [cell.md](cell.md), the
  same codegen `@iomap` and `@projection` delegate to wholesale).
- **`@forward` / `@forward_vector` / `@forward_map`** (in `Forward.jl`) —
  helpers that automatically forward `getproperty` from a wrapper document onto
  a nested field, for compound documents that delegate.
- **Value protocol** — `copy_document`, `cell_kind`, `rekind`, `snapshot`,
  `hydrate`, `sync_document!`: rekind/snapshot switch a whole tree between
  cell kinds (reactive ↔ mutable ↔ immutable) for the reactive-shadow pattern.

## Testing pressure

Kernel tests for this layer use ONLY a test-local `@document struct ToyNode`,
never `Collection` or `Primitive`. That constraint — you cannot reach for the
engine documents as fixtures — is what keeps the interface sufficient. If the
contract cannot be exercised without the concrete documents, it is not
actually a contract. See
[test/document/DocumentContractTest.jl](../test/document/DocumentContractTest.jl).
