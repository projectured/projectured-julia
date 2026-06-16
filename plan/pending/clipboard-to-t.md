# Clipboard projection (port of `clipboard-to-t.lisp`)

Port the Lisp `clipboard/slice->t` and `clipboard/collection->t` projections to
Julia, providing copy / cut / note / paste / collection editing on top of the
existing `ClipboardSlice` / `ClipboardCollection` documents in
[program/src/document/Clipboard.jl](../../program/src/document/Clipboard.jl).

The `ClipboardDocument` types already exist; what is missing is the **projection**
(`clipboard-to-t` has no Julia counterpart). This plan adds that projection plus
the supporting operations and a deep-copy helper.

Reference source:
[clipboard-to-t.lisp](../../../projectured-lisp/source/projection/primitive/clipboard-to-t.lisp).

## Scope

Faithful port of `clipboard-to-t.lisp`:

- **In scope:** the internal clipboard — toggling between showing the wrapped
  content and the stored slice/collection, copy/cut/note/paste of the selected
  sub-document, and add/remove on the collection.
- **Deferred (matches the Lisp `#+nil` branch):** pasting from / copying to the
  **system** clipboard (Lisp shells out to `xclip`). Julia could later use
  `InteractiveUtils.clipboard()` or the `Clipboard.jl` package; left as a
  follow-up so the first cut mirrors the working Lisp behaviour exactly. Noted in
  "Open questions" — do not block on it.

## Architecture mapping (Lisp → Julia)

The Julia projection system differs from Lisp's printer/reader macros; the port
follows existing Julia precedents rather than transliterating:

| Lisp concept | Julia equivalent | Precedent file |
| --- | --- | --- |
| `def projection … (display-slice)` mutable flag | `mutable struct … <: Projection` with a `Bool` field | [Focusing.jl](../../program/src/projection/generic/Focusing.jl) (`FocusingProjection.part`) |
| `def printer` recursing into content | `projection_print(p, recursion, input, ctx)` calling `projection_print(recursion, recursion, child, child_context(ctx, …))` | [Copying.jl](../../program/src/projection/generic/Copying.jl), [Recursive.jl](../../program/src/projection/higherorder/Recursive.jl) |
| `make-iomap/compound` storing child iomaps | a custom `IoMap` struct holding the content / slice / element child iomaps | Copying.jl `CopyingProjectionIoMap` |
| `recurse-reader` + `operation/extend` | delegate to the content child iomap's reader, then prefix the returned operation's path with the `content` field step | Copying.jl `_prefix_op_with_steps` / `_prepend_path` |
| `gesture-case` | `@event_case` (`KeyDown(:key; ctrl)` …) | [EventCase.jl](../../program/src/device/EventCase.jl), Focusing.jl reader |
| `make-operation/functional` toggling the flag | a dedicated `Operation` that flips the projection's mutable field | Focusing.jl `ReplaceFocusPartOperation` |
| `make-operation/replace-target` | `ReplaceDocumentOperation(path, document)` | [common/Operation.jl](../../program/src/common/Operation.jl) |
| `make-operation/compound` | sequence the sub-operations (see "Compound op" below) | — |
| `eval-reference` / `selection-of` / `flatten-reference` | `evaluate_reference(document, path)`; the root document's `selection` Cell already holds the full flattened path (`set_selection!` traverses) | [reference/Reference.jl](../../program/src/reference/Reference.jl) |
| `deep-copy` | **new** `copy_document` helper — see below | — (does not exist yet) |
| `document/nothing` | `DocumentNothing()` | [document/Document.jl](../../program/src/document/Document.jl) |

## Tasks

### 1. Deep-copy helper (prerequisite)

There is **no** `deep_copy` / `copy_document` in the Julia codebase yet; copy,
cut (its copy half), note, and `Shift+Ctrl+V` paste all need it.

- [ ] Add `copy_document(document)` that recursively clones a document subtree,
      allocating fresh `Cell`s (so the copy is independent of the original's
      reactive graph and selection). Place it next to the document core
      (`document/Document.jl` / `DocumentApi`), exported for projection use.
- [ ] Decide between a purpose-built recursive walk over `@document` fields vs.
      leaning on `Base.deepcopy`. Prefer an explicit walk: `Base.deepcopy` would
      also clone backend/reactive cross-links and the `selection` cell, which we
      likely want reset, not duplicated. Verify against how `@document` structs
      store fields (Cell-wrapped) before committing.
- [ ] Unit-test the helper independently (clone, mutate original, assert copy
      unchanged).

### 2. Projections

In a new file `program/src/projection/primitive/ClipboardToT.jl`
(`ClipboardToTProjectionModule`):

- [ ] `mutable struct ClipboardSliceToTProjection <: Projection` with field
      `display_slice::Bool` (default `false`). Constructor
      `ClipboardSliceToTProjection(; display_slice=false)`.
- [ ] `mutable struct ClipboardCollectionToTProjection <: Projection` with field
      `display_collection::Bool` (default `false`).

### 3. IoMap + printer

- [ ] Define an `IoMap` struct per projection holding: the projection, input,
      output, and the child iomaps (`content`, plus `slice` / per-element). Model
      after `CopyingProjectionIoMap`.
- [ ] `projection_print(p::ClipboardSliceToTProjection, recursion, input::ClipboardSlice, ctx)`:
      recurse into `input.content` (and `input.slice` when present) via
      `projection_print(recursion, recursion, …, child_context(ctx, FieldReference("content")|FieldReference("slice")))`.
      Output = the slice iomap's output when `display_slice`, else the content
      iomap's output. (Lisp wraps in `graphics/canvas`; in Julia the output type
      is simply the recursed child's output — no extra wrapper needed unless a
      sibling projection expects a canvas; confirm by how the editor consumes it.)
- [ ] `projection_print(p::ClipboardCollectionToTProjection, recursion, input::ClipboardCollection, ctx)`:
      recurse into `content` and into each `elements[i]`
      (`child_context(ctx, FieldReference("elements"), PositionReference(i))`).
      Output = element outputs when `display_collection`, else content output.

### 4. Reference mapping (School-A delegation)

Per [[prefer-school-a-delegation]] — delegate through the stored child iomaps;
do not re-walk document types.

- [ ] `map_reference_forward` / `map_reference_backward`: peel the leading
      `content` (or `slice` / `elements[i]`) field step and delegate the rest to
      the matching child iomap, re-wrapping the result. Which child is active
      depends on the display flag, mirroring which output the printer chose.

### 5. Readers

`projection_read(p, recursion, change::Change, iomap)` for each projection:
own gestures first (first match wins), then fall through to delegating into the
content child iomap and prefixing the returned op with the `content` step.

`ClipboardSliceToTProjection` gestures (Lisp scancodes → Julia keys):

- [ ] `KeyDown(:slash; ctrl)` (Lisp `kp-divide+ctrl`) → toggle `display_slice`
      via a new toggle operation (task 6).
- [ ] `KeyDown(:c; ctrl)` — copy: `copy_document(evaluate_reference(input, selection))`,
      then `ReplaceDocumentOperation(ReferencePath(FieldReference("slice")), copy)`.
- [ ] `KeyDown(:x; ctrl)` — cut: compound of (write slice) + (replace selection
      target with `DocumentNothing()`). See "Compound op".
- [ ] `KeyDown(:n; ctrl)` — note: like copy but **without** `copy_document`
      (stores the live object).
- [ ] `KeyDown(:v; ctrl)` — paste: if `input.slice` set,
      `ReplaceDocumentOperation(selection_path, input.slice)`.
- [ ] `KeyDown(:v; ctrl, shift)` — paste copy: same but `copy_document(input.slice)`.

`ClipboardCollectionToTProjection` gestures:

- [ ] `KeyDown(:asterisk; ctrl)` (Lisp `kp-multiply+ctrl`) → toggle
      `display_collection`.
- [ ] `KeyDown(:equals; ctrl)` (Lisp `kp-plus+ctrl`, "+") → add selected object to
      collection: `CollectionInsertOperation` on the `elements` container.
- [ ] `KeyDown(:minus; ctrl)` (Lisp `kp-minus+ctrl`) → remove selected element:
      `CollectionDeleteOperation`.
- [ ] Confirm the chosen physical keys against [Keyboard.jl](../../program/src/device/Keyboard.jl)
      — the Lisp keypad scancodes have no exact Julia symbol; pick reasonable
      main-keyboard equivalents and record them in this plan.

Delegation tail (both readers):

- [ ] When no own-gesture matches, call the content child iomap's reader
      (`projection_read(child.projection, recursion, change, child)`), then prefix
      the resulting operation's path with `FieldReference("content")` (reuse the
      `_prefix_op_with_steps` pattern from Copying.jl, or factor a shared helper).

### 6. Operations

- [ ] `ToggleClipboardSliceDisplayOperation(projection)` and
      `ToggleClipboardCollectionDisplayOperation(projection)` (or one
      parameterised op): `evaluate_operation` flips the projection's mutable
      `display_*` field. Mirror `ReplaceFocusPartOperation`.
- [ ] **Compound op** for cut: either reuse an existing compound/sequence
      mechanism if one exists, or have the reader return a small list the editor
      loop already knows how to apply. **Check first** whether the editor's
      `evaluate_operation` loop accepts a vector of operations or whether a
      `CompoundOperation` type must be added — Lisp uses `make-operation/compound`.
      Record the decision here.
- [ ] Copy/note/paste reuse `ReplaceDocumentOperation`; confirm `slice` (typed
      `Any` in `ClipboardSlice`) holds a `Document` so `ReplaceDocumentOperation`
      (which requires `document::Document`) applies — adjust the field's runtime
      contract or the op signature if not.

### 7. Wiring

- [ ] `include("projection/primitive/ClipboardToT.jl")` in
      [program/src/Projectured.jl](../../program/src/Projectured.jl) (after the
      document/operation modules it depends on) and re-export the projection +
      operation symbols, matching the existing `ClipboardModule` block there
      (lines ~55 / ~320 / ~633).

### 8. Tests

- [ ] `test/src/projection/ClipboardToTTest.jl` modelled on
      [CopyingProjectionTest.jl](../../test/src/projection/CopyingProjectionTest.jl):
  - printer: content shows through; toggling `display_slice` / `display_collection`
    switches the output; per-element projection for the collection.
  - reader: each gesture yields the expected operation (copy writes slice, paste
    replaces selection target, cut produces the compound, add/remove mutate the
    collection, toggle flips the flag).
  - `copy_document`: independence after mutation.
- [ ] Register the test in the suite and run the **narrowest** scope only
      (`test_clipboard_to_t()` or the single new function) per the repo's testing
      guidance — never `test_all`.

## Open questions / things to verify during implementation

1. **System clipboard** — confirm we are deferring the `xclip`/`Clipboard.jl`
   path (the Lisp `#+nil` branch). Default: yes, defer.
2. **Output wrapper** — does any consumer require the clipboard projection's
   output to be a `graphics/canvas`-equivalent, or is the recursed child output
   sufficient? Check how the editor/example renders the clipboard root.
3. **Compound operation support** — does an op-sequence/compound exist, or must it
   be added for cut?
4. **`slice` typing** — `ReplaceDocumentOperation` needs a `Document`; verify
   `ClipboardSlice.slice` carries one at runtime.
5. **Example/root wiring** — is there an existing example that makes a
   `ClipboardSlice`/`ClipboardCollection` the editor root, or does one need to be
   added so the projection is exercised end to end? (No current references found
   outside the document module.)
