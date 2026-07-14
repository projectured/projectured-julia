# Split the document interface along the concept DAG

Break the documentation-level cycle in the document layer by **redistributing each
interface declaration to the lowest layer whose concepts it references** (AR-LOWEST-PACKAGE),
instead of bundling them all in `document/Interface.jl` (layer 2).

## Problem

`document/Interface.jl` is a layer-2 file whose docs reference concepts introduced
only much later — `Reference` (l3), `Operation` (l4), `gesture` (l5), `backend`
(l6), `projection` (l7), and base-package machinery (`common/Operation.jl`,
`GestureBindingModule`, `@gestures`). A reader in load order meets all of these
undefined.

This is not a wording problem. The concepts form a **mutually-recursive cluster** —
`Document` ↔ `Reference` ↔ `Operation` ↔ `gesture` ↔ `projection` — the domain
editing model, spread across layers 2–7 for *code* reasons. The code has no cycle
because the seams are **open generics** (`function read_gesture end`, no signature):
the declaration is content-free, the typed meaning is added as methods later. But a
content-free stub *documented* in full must name what fills it, so the docs carry a
forward dependency the code doesn't.

## Insight — the bare types form a DAG

Separate "the bare type" from "the API/seam that references other concepts" and the
cycle disappears:

- `abstract type Document end` — needs nothing.
- `Reference` — a path into a `Document` — needs `Document`.
- `Operation` — an edit against a document's references — needs `Document`, `Reference`.
- `gesture` — an input event — needs nothing.
- `read_gesture` — `gesture → Operation` — needs `gesture`, `Operation`.

No bare type needs a not-yet-defined type. Only the *APIs* reach upward — and each
can be **declared at the layer where its concept completes**, so its documentation
only ever references introduced concepts.

## Principle — AR-LOWEST-PACKAGE, not a new folder

Do **not** create a `concepts/` or `api/` folder of forward declarations — that is
the separate `api/` layer AR-PROJECTION-PLACEMENT explicitly forbids ("interfaces live with their
concept"). Instead, each declaration sinks to `max(layer of every type it
mentions)`:

| Current declaration (in `Interface.jl`, l2) | Types it mentions | Target layer | Target home |
|---|---|---|---|
| `abstract type Document end` | — | 2 document | stays (a minimal `Document.jl`-type file) |
| `@document` / `@forward*` machinery | `Cell` (l1) | 2 document | stays |
| "a document carries a `selection` field" (abstract) | — | 2 document | stays (obligation only) |
| `get_selection` / `set_selection!` / `clear_selection!` / `with_selection` | `Document`(2), `Reference`(3) | 3 reference | `ReferenceModule` (or a `reference/Selection.jl` fragment) |
| `read_gesture` | `Document`(2), `gesture`(5), `Operation`(4) | 5 device | `GestureModule` (which already imports it) |

Result: the document layer keeps the `Document` type + the `@document` codegen; the
selection API lives with `Reference`; `read_gesture` lives with `gesture`. Each
layer's first file introduces its own concept with everything below already known.

## Cost — contract cohesion

"The Document contract" stops being one file: the type is at l2, the selection API
at l3, the gesture seam at l5. Mitigation: [`concepts.md`](../../documentation/concepts.md)
becomes the single place that tells the whole story (it is *allowed* to assume the
full cluster); each layer's file holds only its piece plus a one-line pointer to
`concepts.md`.

## Blast radius

`get_selection` / `set_selection!` / `clear_selection!` / `with_selection` /
`read_gesture` are exported API used across the whole chain — ~18 explicit `import`
sites plus call sites in kernel, base, visual, domain, odbc, video, sdl. Moving their
module home means:

- Remove their declarations/exports from `DocumentModule`; add to `ReferenceModule`
  (selection) and `GestureModule` (`read_gesture`), with exports.
- Update every explicit `import ..DocumentModule: get_selection …` →
  `import ..ReferenceModule: …` (and `read_gesture` → `..GestureModule`).
- Update the higher-package aliases: `DocumentApiModule = ProjecturedKernel.DocumentModule`
  (visual/domain) no longer covers these names; add `ReferenceApiModule` /
  `GestureApiModule` aliases (or migrate the imports to the existing reference/gesture
  aliases) and fix the ~dozen `import …DocumentApiModule: …` sites.
- The umbrella (`Projectured`) re-exports mechanically, so flat `using Projectured`
  consumers are unaffected.

## Layering-guard implications

- `get_selection`'s default (`document.selection`) references `Document` from the
  reference layer — a downward (3→2) edge, valid. `ReferenceModule` already imports
  `DocumentModule` (`@document`), so no new cross-layer direction.
- `read_gesture` in the device layer references `Document`(2)/`Operation`(4) — both
  below layer 5, valid. `GestureModule` (l5) already imports `read_gesture` today.
- `check_private_imports` must still see only exported symbols cross-layer — the moved
  generics must be exported from their new modules.
- Run `test_kernel_layering()` (and the base/visual/domain guards) after: the include
  order and every edge must stay a valid topological sort.

## Implementation steps

1. ✅ **document layer**: shrink `Interface.jl` to the `Document` abstract type + the
   abstract "carries a selection field" obligation; keep `@document`/`@forward`.
2. ✅ **reference layer**: add the selection generics (declarations + the `get_selection`
   default) to `ReferenceModule`; export them; document them with `Reference` in scope.
   Landed as a new fragment `reference/Selection.jl`.
3. ✅ **device layer**: move `read_gesture` (declaration + docstring) into `GestureModule`;
   export it; document it with `gesture`/`Operation` in scope. The open generic sits
   just above the `@gestures`-driven catch-all in `GestureBinding.jl`.
4. ✅ **imports/aliases**: update every explicit import site across all packages; add/adjust
   the `*ApiModule` aliases in visual/domain; drop the moved names from `DocumentModule`'s
   exports. Added `ReferenceApiModule`/`GestureApiModule` aliases in
   `ProjecturedVisual.jl`/`ProjecturedDomain.jl`.
5. ✅ **concepts.md**: write the one-place narrative of the document editing model
   (Document → Reference → Operation → gesture → projection); add per-file pointers.
   Section "The document editing model — one cluster spread across layers"
   added between the five-ideas walk and the design-principles section, with a
   per-concept "where it lives" table; `document/Interface.jl`,
   `reference/Selection.jl`, and the `read_gesture` docstring in
   `device/GestureBinding.jl` all carry a one-line pointer to it.
6. ✅ **guards/tests**: `test_kernel_layering()` + `test_base/visual/domain_layering()`;
   precompile each package; `test_kernel()` and a broad sweep. All four layering
   guards green (7/7, 6/6, 5/5, 5/5); `test_kernel()` 323/323, `test_base()`
   82/82, `test_visual()` 51789/51790 (1 pre-existing broken), `test_domain()`
   132649/132649+15 broken with 10 pre-existing `FakeLlm`/`ScriptedLlm`
   fixture-import errors that also fire on the pre-restructure baseline
   (unrelated to this plan).

## Acceptance

- ✅ Reading the kernel in load order never hits an undefined concept in a
  docstring — `Reference` and `Operation` no longer appear in `document/Interface.jl`;
  `gesture` and `Operation` no longer appear at layer 2 at all.
- ✅ Each moved generic is exported from its new module and every consumer still
  resolves it — verified by precompile + the four per-package layering guards
  (`check_private_imports` on the kernel guard enforces cross-layer exports).
- ✅ All layering guards green; all packages precompile.

## Related

- Pairs with the AR-NO-CONSUMER-DOCS seam carve-out: an interface/seam file may name the *concepts*
  it bridges (as forward pointers) but not the specific higher-*package* modules that
  implement it. After this split, each seam sits at the layer of its concepts, so even
  the concept references become backward, not forward.
- Same "sink to the concept's layer" move as relocating `Time.jl`/`Clock` to the
  document layer.
