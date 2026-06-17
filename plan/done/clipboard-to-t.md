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

- [x] Add `copy_document(document)` that recursively clones a document subtree,
      allocating fresh `Cell`s (so the copy is independent of the original's
      reactive graph and selection). Place it next to the document core
      (`document/Document.jl` / `DocumentApi`), exported for projection use.
- [x] Decide between a purpose-built recursive walk over `@document` fields vs.
      leaning on `Base.deepcopy`. Prefer an explicit walk: `Base.deepcopy` would
      also clone backend/reactive cross-links and the `selection` cell, which we
      likely want reset, not duplicated. Verify against how `@document` structs
      store fields (Cell-wrapped) before committing.
- [x] Unit-test the helper independently (clone, mutate original, assert copy
      unchanged).

### 2. Projections

In a new file `program/src/projection/primitive/ClipboardToT.jl`
(`ClipboardToTProjectionModule`):

- [x] `mutable struct ClipboardSliceToTProjection <: Projection` with field
      `display_slice::Bool` (default `false`). Constructor
      `ClipboardSliceToTProjection(; display_slice=false)`.
- [x] `mutable struct ClipboardCollectionToTProjection <: Projection` with field
      `display_collection::Bool` (default `false`).

### 3. IoMap + printer

- [x] Define an `IoMap` struct per projection holding: the projection, input,
      output, and the child iomaps (`content`, plus `slice` / per-element). Model
      after `CopyingProjectionIoMap`.
- [x] `projection_print(p::ClipboardSliceToTProjection, recursion, input::ClipboardSlice, ctx)`:
      recurse into `input.content` (and `input.slice` when present) via
      `projection_print(recursion, recursion, …, child_context(ctx, FieldReference("content")|FieldReference("slice")))`.
      Output = the slice iomap's output when `display_slice`, else the content
      iomap's output. (Lisp wraps in `graphics/canvas`; in Julia the output type
      is simply the recursed child's output — no extra wrapper needed unless a
      sibling projection expects a canvas; confirm by how the editor consumes it.)
- [x] `projection_print(p::ClipboardCollectionToTProjection, recursion, input::ClipboardCollection, ctx)`:
      recurse into `content` and into each `elements[i]`
      (`child_context(ctx, FieldReference("elements"), PositionReference(i))`).
      Output = element outputs when `display_collection`, else content output.

### 4. Reference mapping (School-A delegation)

Per [[prefer-school-a-delegation]] — delegate through the stored child iomaps;
do not re-walk document types.

- [x] `map_reference_forward` / `map_reference_backward`: peel the leading
      `content` (or `slice` / `elements[i]`) field step and delegate the rest to
      the matching child iomap, re-wrapping the result. Which child is active
      depends on the display flag, mirroring which output the printer chose.

### 5. Readers

`projection_read(p, recursion, change::Change, iomap)` for each projection:
own gestures first (first match wins), then fall through to delegating into the
content child iomap and prefixing the returned op with the `content` step.

`ClipboardSliceToTProjection` gestures (Lisp scancodes → Julia keys):

- [x] `KeyDown(:slash; ctrl)` (Lisp `kp-divide+ctrl`) → toggle `display_slice`
      via a new toggle operation (task 6).
- [x] `KeyDown(:c; ctrl)` — copy: `copy_document(evaluate_reference(input, selection))`,
      then `ReplaceDocumentOperation(ReferencePath(FieldReference("slice")), copy)`.
- [x] `KeyDown(:x; ctrl)` — cut: compound of (write slice) + (replace selection
      target with `DocumentNothing()`). See "Compound op".
- [x] `KeyDown(:n; ctrl)` — note: like copy but **without** `copy_document`
      (stores the live object).
- [x] `KeyDown(:v; ctrl)` — paste: if `input.slice` set,
      `ReplaceDocumentOperation(selection_path, input.slice)`.
- [x] `KeyDown(:v; ctrl, shift)` — paste copy: same but `copy_document(input.slice)`.

`ClipboardCollectionToTProjection` gestures:

- [x] `KeyDown(:asterisk; ctrl)` (Lisp `kp-multiply+ctrl`) → toggle
      `display_collection`.
- [x] `KeyDown(:equals; ctrl)` (Lisp `kp-plus+ctrl`, "+") → add selected object to
      collection: `CollectionInsertOperation` on the `elements` container.
- [x] `KeyDown(:minus; ctrl)` (Lisp `kp-minus+ctrl`) → remove selected element:
      `CollectionDeleteOperation`.
- [x] Confirm the chosen physical keys against [Keyboard.jl](../../program/src/device/Keyboard.jl)
      — the Lisp keypad scancodes have no exact Julia symbol; pick reasonable
      main-keyboard equivalents and record them in this plan.

Delegation tail (both readers):

- [x] When no own-gesture matches, call the content child iomap's reader
      (`projection_read(child.projection, recursion, change, child)`), then prefix
      the resulting operation's path with `FieldReference("content")` (reuse the
      `_prefix_op_with_steps` pattern from Copying.jl, or factor a shared helper).

### 6. Operations

- [x] `ToggleClipboardSliceDisplayOperation(projection)` and
      `ToggleClipboardCollectionDisplayOperation(projection)` (or one
      parameterised op): `evaluate_operation` flips the projection's mutable
      `display_*` field. Mirror `ReplaceFocusPartOperation`.
- [x] **Compound op** for cut: either reuse an existing compound/sequence
      mechanism if one exists, or have the reader return a small list the editor
      loop already knows how to apply. **Check first** whether the editor's
      `evaluate_operation` loop accepts a vector of operations or whether a
      `CompoundOperation` type must be added — Lisp uses `make-operation/compound`.
      Record the decision here.
- [x] Copy/note/paste reuse `ReplaceDocumentOperation`; confirm `slice` (typed
      `Any` in `ClipboardSlice`) holds a `Document` so `ReplaceDocumentOperation`
      (which requires `document::Document`) applies — adjust the field's runtime
      contract or the op signature if not.

### 7. Wiring

- [x] `include("projection/primitive/ClipboardToT.jl")` in
      [program/src/Projectured.jl](../../program/src/Projectured.jl) (after the
      document/operation modules it depends on) and re-export the projection +
      operation symbols, matching the existing `ClipboardModule` block there
      (lines ~55 / ~320 / ~633).

### 8. Tests

- [x] `test/src/projection/ClipboardToTTest.jl` modelled on
      [CopyingProjectionTest.jl](../../test/src/projection/CopyingProjectionTest.jl):
  - printer: content shows through; toggling `display_slice` / `display_collection`
    switches the output; per-element projection for the collection.
  - reader: each gesture yields the expected operation (copy writes slice, paste
    replaces selection target, cut produces the compound, add/remove mutate the
    collection, toggle flips the flag).
  - `copy_document`: independence after mutation.
- [x] Register the test in the suite and run the **narrowest** scope only
      (`test_clipboard_to_t()` or the single new function) per the repo's testing
      guidance — never `test_all`.

## Open questions / things to verify during implementation — RESOLVED

1. **System clipboard** — **Deferred** (confirmed). Only the internal clipboard
   is ported; the Lisp `#+nil` `xclip` branch is left out.
2. **Output wrapper** — **No wrapper needed.** The output is the active child's
   output directly: the `content` child output in content mode, the `slice`
   child output in slice mode, and (collection) a `CellVector` of the projected
   `elements` in collection mode. Because toggling swaps which child document is
   the output (rather than mutating one in place), the toggle operations drop
   `editor.iomap` to force the next `print!` to rebuild — mirroring
   `ReplaceDocumentOperation`'s root-swap handling. This avoided needing a
   `graphics/canvas`-equivalent stable wrapper.
3. **Compound operation support** — **Added** `CompoundOperation(operations)` to
   `common/Operation.jl` (`OperationModule`). Its `evaluate_operation` runs each
   member op against the same editor in turn. The cut gesture returns one.
4. **`slice` typing** — `ReplaceDocumentOperation` requires `document::Document`.
   The reader guards every copy/cut/note/paste path with `isa Document`
   (`_selected` returns the evaluated sub-document; helpers bail out when it is
   not a `Document`), so the op is only built with a genuine `Document`.
5. **Example/root wiring** — **Deferred.** No example currently makes a
   `ClipboardSlice`/`ClipboardCollection` the editor root; none was added. The
   projection is exercised end-to-end by `test/src/projection/ClipboardToTTest.jl`
   instead.

## Implementation notes / decisions

- **`copy_document`** lives in a new `program/src/common/DocumentCopy.jl`
  (`DocumentCopyModule`), included right after `document/Collection.jl` so it can
  import `CellVector`. It is an explicit recursive walk (not `Base.deepcopy`):
  each `@document` field is cloned into a **fresh** `Cell`, `selection` is reset
  to `nothing`, `CellVector` elements are cloned element-wise, and plain
  immutable leaves are returned as-is.
- **Keyboard symbols.** The Julia keyboard layer maps every printable key to the
  single `:char` fallback, so letter/punctuation keys could not be told apart in
  a `KeyDown`. To make the Lisp keypad chords reachable, `backend/Sdl.jl`'s
  `sdl_keysym_to_symbol` was extended to emit distinct symbols for the keys this
  projection binds. Chosen physical keys → symbols:
  - slice: `Ctrl+/` (`:slash`) toggle, `Ctrl+C` (`:c`) copy, `Ctrl+X` (`:x`) cut,
    `Ctrl+N` (`:n`) note, `Ctrl+V` (`:v`) paste, `Ctrl+Shift+V` paste-copy.
  - collection: `Ctrl+*` (`:asterisk`, keypad-multiply) toggle, `Ctrl+=`
    (`:equals`, main `=` / keypad `+`) add, `Ctrl+-` (`:minus`, main `-` / keypad
    `-`) remove. The keypad scancodes the Lisp used are also mapped where they
    exist.
- **Reference mapping is asymmetric** (unlike `ScreenToScreen`, whose output
  mirrors its input shape): the clipboard output has no clipboard-shaped wrapper,
  so `map_reference_forward` peels the clipboard field step and returns the
  child's output reference unwrapped, while `map_reference_backward` delegates to
  the child and *prepends* the field step. The active child (content vs.
  slice/elements) is chosen by the display flag, matching which output the
  printer produced.
- **Delegation tail.** Non-clipboard gestures (and clipboard gestures that turn
  out to be no-ops, e.g. paste with no stored slice) fall through to the
  `content` child reader, and the returned op is re-rooted under `content` via
  `_prefix_op`/`_prepend`. This matches Lisp's `merge-commands` semantics
  (gesture-case first, then the content command).
- **Wiring.** `ClipboardToT.jl` is included after the device modules
  (`Keyboard`/`EventCase`) and `Focusing.jl`, since it depends on `@event_case`.
  New exported symbols: `ClipboardSliceToTProjection`,
  `ClipboardCollectionToTProjection`, their IoMaps, the two toggle operations,
  `copy_document`, and `CompoundOperation`.
- **Tests:** `test_clipboard_to_t()` (registered in `ProjecturedTest.jl` and
  `test_projections`) covers `copy_document` independence, both printers'
  display toggle, slice reference mapping, every slice gesture (toggle / copy /
  note / cut-compound / paste / paste-copy), and the collection gestures
  (toggle / add / remove). 53 assertions, all passing.
