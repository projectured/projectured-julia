# Separate domain gesture→operation mapping out of the projection

Move the **domain-document-specific** gesture→operation mapping (the
geometry-independent navigation and editing logic) out of the projection reader
and into the **domain document source file**. Today that logic lives inside
`TextToGraphics` (text domain) and `SyntaxToText` (syntax domain); extracting it
makes it reusable by any projection of those domains — most importantly by the
`ConsoleBackend` pipeline, which drops `TextToGraphics` and therefore currently
loses all character-level navigation and editing.

> Related plans:
> [console-backend.md](../done/console-backend.md) (the consumer — its "no
> character-level text editing" limitation is exactly what this unblocks),
> [event-to-gesture.md](event-to-gesture.md) (the input side — gestures as
> first-class objects), and
> [syntaxtotext-delegation.md](syntaxtotext-delegation.md) (its **A6** keeps the
> tree-navigation helpers in place; this plan *relocates* them to the document,
> so the two must be reconciled — see "Coordination" below).

## Motivation

The reader chain threads a `Change(gesture, operation)` from the output domain
back to the source domain. A navigation/edit gesture (arrow, Home/End,
Backspace, character insert, …) is turned into an `Operation` by whichever
projection reader owns the relevant domain, then mapped backward to the source
by the rest of the chain.

For the Text domain that conversion lives in
[`TextToGraphics`](../../program/src/projection/primitive/TextToGraphics.jl)
(`projection_read(::TextToGraphics, iomap, evt)`, ~L106–328). For the Syntax
domain it lives in
[`SyntaxToText`](../../program/src/projection/primitive/SyntaxToText.jl)
(`projection_read(::SyntaxNodeToText, iomap, evt::KeyDown)`, ~L280–306, plus the
`_tree_navigate` / `_is_tree_selection` / `_promote_to_structural` /
`_descend_to_text_cursor` helpers).

The problem: **the mapping is welded to one specific projection.** The JSON SDL
pipeline is

```
JsonToSyntax → SyntaxToText → TextToGraphics   (→ Graphics, SDL)
```

and the console pipeline drops the last step:

```
JsonToSyntax → SyntaxToText → EnvelopeUnwrapping   (→ TextText, ConsoleBackend)
```

Because the Text-domain gesture mapping is *inside* `TextToGraphics`, the
console pipeline has no handler for character left/right, Ctrl+Home/End,
Backspace/Delete, or character insertion — even though **none of those need
pixel geometry**; they only read the `TextText` span structure and its
selection. The console-backend plan documents this as a hard limitation
("Character cursor movement … and backspace/delete all live in TextToGraphics …
The console pipeline omits TextToGraphics, so those are unavailable").

The fix is to recognize that this logic is a property of the **domain document**,
not of the projection that happens to render it to graphics.

## The geometry split (the crux)

`TextToGraphics`'s reader mixes two kinds of gesture handling. Only the first
kind moves:

**Geometry-independent (→ move to `Text.jl`).** Reads only `TextText.elements`
(span structure) and `TextText.selection`:
- `KeyPress(c)` → `StringReplaceRangeOperation` (character insert) — L106–113.
- `KeyDown(:backspace)` / `KeyDown(:delete)` → `StringReplaceRangeOperation`
  (`_key_delete_op`, L118–149).
- `KeyDown(:left)` / `KeyDown(:right)` → cross-span character cursor movement
  (L254–283), using the `span_infos` length table.
- `KeyDown(:home; ctrl)` / `KeyDown(:end; ctrl)` → jump to first/last span char
  (L245–246).
- The **decline rules** that let tree gestures fall through to the syntax layer
  (Alt+arrows, plain arrows while the selection is structural, Tab) and the
  `KeyDown(:period; ctrl)` → `ToggleCollapseOperation` recognition (L210–234).
  These are geometry-free predicates over the selection; they move with the rest
  but must preserve their *fall-through* semantics (return `nothing`, not the
  event) so the chain keeps walking inward.

**Geometry-dependent (→ stays in `TextToGraphics`).** Needs the laid-out
coordinate map `iomap.char_to_coord`:
- `KeyDown(:home)` / `KeyDown(:end)` (no Ctrl) → visual line start/end
  (L284–294).
- `KeyDown(:up)` / `KeyDown(:down)` → visual line movement with sticky cursor x
  (L295–325).
- `MousePress(:left)` → click hit-test → cursor position (L194–204).

So the console gets the full geometry-free editing subset for free; visual
up/down/Home/End and mouse remain SDL-only (the console has no pixel layout and
no mouse — a future console line-model could add its own up/down later).

For the **Syntax domain** the entire keyboard mapping is already
geometry-independent — `_tree_navigate` walks the input `SyntaxNode` tree and
its selection *paths*. All of it moves to `Syntax.jl`. (The mouse hit-testing
in `SyntaxNodeToText`'s 4-arg reader, L229–246, stays — it is geometry/output
driven via `_node_at_collapse_glyph` / `_pos_to_tree_selection`.)

## Design

### 1. New document-layer generic: `document_read`

Declare in
[program/src/api/Document.jl](../../program/src/api/Document.jl) (the natural
home — it already declares the document-level `clear_selection!` /
`set_selection!` interface):

```julia
"""
    document_read(document, gesture) -> Union{Operation, Nothing}

Map a backend-agnostic input gesture to an Operation expressed against
`document` itself (i.e. against `document`'s own reference vocabulary, reading
only `document`'s structure and `document.selection`). Returns `nothing` when
the document does not handle the gesture, so a projection reader can fall back
to its own geometry-dependent handling or let the gesture propagate.

This is the projection-independent half of a domain's reader: any projection
whose output (or input) is `document` can obtain navigation/editing operations
without re-implementing them, and a backend that renders the domain directly
(e.g. ConsoleBackend on a bare TextText) gets them for free.
"""
function document_read end
document_read(::Document, gesture) = nothing   # default: not handled
```

`document_read` produces operations in the **document's own domain** (e.g. a
`ReplaceSelectionOperation`/`StringReplaceRangeOperation` whose reference is
rooted at the `TextText`). Those operations then flow back through the existing
`map_reference_backward` chain to the source domain — exactly as the operations
that `TextToGraphics` produces today already do.

Naming note: `document_read` mirrors `projection_read`. If a clearer term
surfaces during implementation (`navigate`, `read_gesture`, `document_gesture`)
it is a pure rename; the shape is what matters.

### 2. Text domain — `program/src/document/Text.jl`

Add `document_read(text::TextText, gesture)` methods covering the
geometry-independent set above. Relocate (don't rewrite) the helpers they need
from `TextToGraphics`:
- `_text_selection_range`, `_text_replace_path`, `_span_content` (already pure
  `TextText` walkers — they belong in the document file).
- `_cursor_position`, `_build_selection_path`, `_is_structural_selection`, and
  the `span_infos` length-table construction used by left/right and Ctrl+Home/End.

Keep these as module-internal helpers in `TextModule`; export only
`document_read` (via the API module). The character-insert / delete operations
are `StringReplaceRangeOperation` (already imported in `Text.jl`'s neighborhood
via `OperationApiModule`); confirm/extend the imports.

### 3. Syntax domain — `program/src/document/Syntax.jl`

Add `document_read(node::SyntaxNode, gesture)` handling Ctrl+Alt+Home (root
select), Ctrl+Space (structural⇄text toggle), and Alt/structural arrows. Move
`_tree_navigate`, `_is_tree_selection`, `_promote_to_structural`,
`_descend_to_text_cursor` (and any small helpers they call) from `SyntaxToText`
into `Syntax.jl`. These already operate purely on the `SyntaxNode` and its
selection path.

### 4. Projection readers delegate

- **`TextToGraphics`**: at the top of `projection_read(p, iomap, evt)`, try
  `op = document_read(iomap.input, evt); op === nothing || return op`. Keep only
  the geometry-dependent arms (visual up/down/Home/End, mouse). The `KeyPress`
  and `MousePress` methods: `KeyPress` delegates to `document_read`; `MousePress`
  stays.
- **`SyntaxToText`** (`SyntaxNodeToText`): in the `KeyDown` reader, delegate to
  `document_read(iomap.input, evt)`. The 4-arg `Change` reader keeps its mouse
  hit-test (geometry) and now only needs the keyboard delegation. Reconcile with
  [syntaxtotext-delegation.md](syntaxtotext-delegation.md) **A6**: that plan says
  "keep the tree-navigation helpers" — meaning keep them *reachable from the
  reader*, which delegation preserves; they simply live in `Syntax.jl` now.
  Land whichever plan first and have the second rebase onto it.

### 5. The console payoff — reuse the existing `SyntaxToText` reader (no new projection)

The console pipeline already contains `SyntaxToText`, the projection whose
**output is the `TextText`**. No new projection is needed: extend that existing
reader so that when it receives a *gesture with an empty operation slot* (the
console case) that it does not handle as a syntax gesture, it calls
`document_read(iomap.output, gesture)` to produce a text-domain operation and
then maps it backward to syntax with the existing
`map_reference_backward` path.

This dovetails with the `Change(gesture, operation)` threading and needs no
double-handling guard:

- **SDL** (`… → SyntaxToText → TextToGraphics`): by the time the `Change`
  reaches `SyntaxToText`, `TextToGraphics` has already filled the **operation**
  slot (via its own `document_read` delegation). `SyntaxToText` takes its
  existing op-mapping path and never touches the gesture — unchanged behavior.
- **Console** (`… → SyntaxToText → EnvelopeUnwrapping`): the operation slot is
  still empty when the `Change` reaches `SyntaxToText`, so it runs the
  gesture path: first its own syntax `document_read` (tree nav), then, on
  `nothing`, the text-domain `document_read(iomap.output, …)`.

So the only change for the console is a fallback arm in `SyntaxToText`'s
existing gesture reader — the existing readers *are* the reuse mechanism, which
is the whole point of relocating the mapping onto the document. The
`EnvelopeUnwrappingProjection` already in the console pipeline keeps doing its
one job (stripping the `EventEnvelope`); the console example
([example](../../example/src/projection/Json.jl) /
`make_json_console_projection_example`) needs no new wrapper. The SDL pipeline
needs no change — `TextToGraphics` calls `document_read` directly.

## Why this is safe / behavior-preserving

The SDL pipeline produces the identical operations: `TextToGraphics` calls the
same code, only relocated. The relocated helpers are already pure `TextText` /
`SyntaxNode` walkers with no projection or geometry dependency (verified: they
read `iomap.input`, never `iomap.char_to_coord`, the layout cells, or
`p.measure`). The console pipeline *gains* behavior (character editing) that was
previously absent.

## Phases

1. **Text extraction (primary value).** Steps 1, 2, 4 (TextToGraphics half).
   Verify SDL text behavior unchanged.
2. **Console wiring.** Step 5 (the `SyntaxToText` gesture fallback). Verify the
   console gains character editing.
3. **Syntax extraction.** Steps 3, 4 (SyntaxToText half), reconciled with
   syntaxtotext-delegation.

Each phase is independently shippable and leaves the tree green.

## Verification (narrowest covering tests first — never `test_all`)

- Phase 1: `test_text_navigation(json_example)` and `test_example(json_example)`;
  spot a nested case with `test_text_navigation(json_example; check_reaches_all=true)`.
  Add `test_example(text_example)` for the bare Text domain.
- Phase 2: extend `test_console_backend` (the IOBuffer-driven harness in the
  console-backend work) to drive `Right`/`Left`/`Backspace`/character insert and
  assert the resulting domain operations — this is the concrete proof the
  separation works off `TextToGraphics`.
- Phase 3: `test_syntax()`, `test_syntax_to_text()`, `SyntaxTreeNavigationTest`,
  `CollapseRoundtripTest`, plus `test_example(json_example)` /
  `test_example(xml_example)`.

## Files

- **Edit:** `program/src/api/Document.jl` (declare `document_read` + default).
- **Edit:** `program/src/document/Text.jl` (text `document_read` + relocated helpers).
- **Edit:** `program/src/document/Syntax.jl` (syntax `document_read` + relocated helpers).
- **Edit:** `program/src/projection/primitive/TextToGraphics.jl` (delegate; drop moved code).
- **Edit:** `program/src/projection/primitive/SyntaxToText.jl` (delegate; drop
  moved code; add the empty-operation-slot fallback to `document_read(iomap.output, …)`).
- **Edit (export):** `program/src/Projectured.jl` — re-export `document_read`.
- **Doc:** note the principle in
  [guide/projection-system.md](../../guide/projection-system.md) (readers split:
  domain-owned geometry-free mapping lives on the document; geometry-dependent
  mapping stays in the projection) and the Text/Syntax document guides.

## Open questions

- **Insert/delete in the console.** `StringReplaceRangeOperation` from
  `document_read` must map cleanly back through `SyntaxToText` →
  `JsonToSyntax`; this path already works for SDL, but confirm the console's
  lack of a window/`ScreenToScreen` re-rooting layer doesn't change the target
  reference (the EnvelopeUnwrapping note says no re-rooting is needed — verify
  with an insert).
- **Where the decline rules live.** The "let this gesture fall through to the
  syntax layer" predicates currently sit in `TextToGraphics`. Moving them to
  `document_read(::TextText)` means a `nothing` return both for "I don't handle
  this" and "I decline so syntax can" — which is the same signal. Confirm the
  chain ordering (text then syntax) still produces the same outcome once both
  domains expose `document_read`.
- **Gesture vs. raw event.** This plan uses today's raw events (`KeyDown`,
  `KeyPress`, `MousePress`) as the `gesture` argument. If
  [event-to-gesture.md](event-to-gesture.md) Phase 2 lands a semantic gesture
  vocabulary, `document_read` switches its `@event_case` arms to `@gesture_case`
  mechanically — the document-level home for the mapping is unchanged.
