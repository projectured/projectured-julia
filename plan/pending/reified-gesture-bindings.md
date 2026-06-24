# Gesture pipeline: recognition + reified bindings + context-sensitive collection

> **Status (implemented on branch `worktree-reified-gesture-bindings`).**
> Stages 0–3 **done**; Stage 4 **rendering + help-gesture predicate done**, the
> live editor overlay invocation **deferred** (a clearly-scoped follow-up — see the
> note in Stage 4). All targeted tests green; JSON `document_read` parity holds at
> the pre-existing 47/1/0 baseline. New tests: `test_gesture_binding` (34+),
> `test_json_gesture_collection` (10), `test_gesture_map` (14). Key decisions and
> the resolution of the open questions are recorded inline and under
> **“Decisions made during implementation”** at the end.

> **Merged 2026-06-24.** This is now the single umbrella plan for the whole gesture
> pipeline — **recognition** (events → gesture, *no intent*) **and** mapping
> (gesture → operation, reified). `event-to-gesture.md` was folded in here as
> **Stage 0 (recognition)** and retired to
> [`../done/event-to-gesture.md`](../done/event-to-gesture.md) (the full recogniser
> design record). Its recogniser spine, click-out-of-backend, multi-click, and key
> chords are **done**; the one open recognition item — **drag** — is tracked in
> Stage 0 below (blocked on [dragging.md](../done/dragging.md)). The clean seam between the
> two halves is exactly *"a gesture carries no intent"*.

Make the **gesture → operation** mapping a *reified, projection-independent
data structure* attached to the document types (and, via a sibling seam, to
projections), so that:

1. the simple case is **declarative / pattern-matching** (`@gestures` on a
   document, reusing the `@event_case` pattern surface);
2. the same single declaration both **fires** the operation and is
   **inspectable as data** (gesture + human description + applicability); and
3. a projection can **collect and present every gesture available in the
   current editor state**, so the user discovers possibilities without being in
   that context.

This unifies three existing plans into one staged line of work:

- **[event-to-gesture.md](../done/event-to-gesture.md)** (retired to `done/`) — the
  input/recognition side, now **fully absorbed here as Stage 0 (recognition)**. Its
  recogniser spine + composites (multi-click, chords) are done; its idea of
  *"distinct, first-class gesture types"* was realized as the `GesturePattern` types
  (Stage 1) over the raw/synthesised events rather than per-kind gesture structs +
  `@gesture_case`; and its deferred reader migration is **superseded** by this plan's
  `@gestures` reification (same readers, declarative tables instead of
  `@gesture_case`). The full recogniser design record lives in
  [`../done/event-to-gesture.md`](../done/event-to-gesture.md).
- **[domain-gesture-mapping-separation.md](domain-gesture-mapping-separation.md)**
  — the `document_read` seam. Already landed for Text + Syntax; this plan adds
  the missing **data layer** (`document_gestures`) and ports JSON onto it.
- **[../obsolete/gesture-help.md](../obsolete/gesture-help.md)** — the `Ctrl-?`
  help. **Superseded by this plan:** its `merge_help` accumulation becomes the
  `collect_gestures` chain traversal here, and its per-reader `@gesture_case` is
  reframed as document-level `@gestures` + a `projection_gestures` seam. Retained
  for historical reference only — chiefly its detailed Lisp prior-art writeup
  (`command.lisp` / `merge-commands` / `help-to-text`), which is the model for
  Stage 4 and the `accessible` refinement below.

> Path note: like the sibling plans, references below use the repo's logical
> `program/src/...` namespace, which maps onto the real
> `package/kernel/src/...` (kernel) and `package/domain/src/...` (domain) tree.

---

## Current status (what already exists)

- ✅ **Recognizer** — `GestureRecognizer` (`program/src/editor/GestureRecognizer.jl`)
  turns raw events into gestures; `MouseDown`+`MouseUp` → `MousePress`. Driven by
  `next_gesture!` in `Editor.read!`.
- ✅ **`document_read` seam** — declared in `program/src/api/Document.jl`
  (`document_read(document, gesture) -> Operation|Nothing`), documented as *"the
  projection-independent half of a domain's reader."* Implemented for `TextText`
  (`program/src/document/Text.jl`) and `SyntaxNode` (`program/src/document/Syntax.jl`);
  delegated to from `SyntaxToText` / `TextToGraphics`.
- ✅ **`@event_case`** — the first-match pattern table over event structs
  (`program/src/device/EventCase.jl`); its parser (`_parse_pattern` /
  `_parse_rule`) is reused by `@gestures`.
- ✅ **The data layer (this plan).** `document_read` can now be *enumerated* as
  well as *fired*: the JSON authoring gestures live in reified
  `document_gestures` tables and reach the projection via the generic fallback.

---

## Decisions carried from design discussion

- **Full reified patterns** — `GesturePattern` structs implementing both
  `matches` and `describe` (not a bare predicate + string), so help is rich.
- **Generic reader fallback** — wire `document_read` into the base
  `projection_read` so leaf projections need no authoring reader.
- **Build the help projection** in this line of work (proves the reification).
- **Prototype on JSON only first.**
- **Collector = full projection chain** (the `merge_help` generalization), but
  **collector + both seams land first with only JSON reified**; the remaining
  contributors are clearly-scoped follow-ups (the collector degrades gracefully
  — un-reified layers contribute nothing until ported).

---

## Stage 0 — recognition (events → gesture) ✅ except drag

The input half of the pipeline: the `GestureRecognizer`
(`program/src/editor/GestureRecognizer.jl`) turns raw device events into
*gestures*, where **a gesture is just a combination of events and carries no
intent** — what a gesture *means* is decided downstream (Stages 1–3), never by the
recogniser. Folded in from the retired
[event-to-gesture.md](../done/event-to-gesture.md), which holds the full design
record; status:

- ✅ **Recogniser spine** — owned by `Editor`, driven once per event via
  `next_gesture!` in `Editor.read!`.
- ✅ **Click out of the backend** — `MouseDown`+`MouseUp` → `MousePress` is
  recognised here, not in the SDL backend (backend-agnostic, unit-tested).
- ✅ **Multi-click** — `MousePress.count` (1/2/3…), incremented for consecutive
  same-button clicks within a 5 px / 0.3 s window; `:count` added to the
  `@event_case` table; back-compatible.
- ✅ **Key chords** — a synthesised `KeyChord(keys::Vector{KeyDown})` event
  (e.g. `Ctrl-C Ctrl-K`) from a per-recogniser chord table that **defaults empty**
  (opt-in, zero behaviour change). `next_gesture!` loops to absorb a buffered prefix.
- ⏳ **Drag** — `MouseDown` → `MouseMove`… → `MouseUp` → begin/update/end.
  **Blocked**: reconcile drag routing with [dragging.md](../done/dragging.md) before
  implementing. The only open recognition item.

These gestures (raw `KeyDown`/`MousePress`/`KeyChord`/… events) are exactly what
the Stage 1 `GesturePattern`s match — the recogniser was realized this way (events
as the gesture vocabulary) rather than as per-kind gesture structs + `@gesture_case`.
The new composites (`count`, `KeyChord`) are available building blocks for the
Stage 1 patterns and the follow-ups (a `KeyChordPattern`, `count` matching).

---

## Stage 1 — reified bindings + `@gestures` (kernel) ✅ [JSON-reified]

New module `program/src/common/GestureBinding.jl`
(`package/kernel/src/common/GestureBinding.jl`), included in `ProjecturedKernel.jl`
right after `EventCase.jl`.

- **`GesturePattern`** abstract + `KeyPressPattern`, `KeyDownPattern`,
  `KeyUpPattern`, `MousePressPattern`/`Down`/`Up`, `MouseMovePattern`,
  `MouseScrollPattern`, each with `matches(pattern, event)::Bool` and
  `describe(pattern)::String`. **KeyPress patterns ignore modifiers** (the OS
  folds Shift into the char; Ctrl-combinations never produce text input), so the
  old defensive `ctrl` guard was dropped; **KeyDown patterns match modifiers
  exactly** (`@event_case` model). Patterns carry an optional event `guard`
  closure for `when(PATTERN, cond)` (e.g. `isdigit(char)`).
- **`GestureBinding`**: `pattern`, `operation(doc,event)->Operation|Nothing`,
  `applicable(doc,selection)::Bool` (event-independent state precondition),
  `description::String`, `domain::String`.
- **Registry by document type with supertype inheritance.** The own bindings
  live in **`document_gestures_own(::Type{T})` methods** (emitted by `@gestures`),
  *not* a mutable Dict — a Dict mutated at a domain module's load time would be
  lost across precompilation. `document_gestures(T)` walks the supertype chain
  over those methods (caching the merged result in a runtime Dict).
- **`@gestures DocType begin [when(<precondition>)] PATTERN => "desc" => rhs … end`**
  — reuses the `@event_case` parser for the LHS. The right side parses
  right-associatively as `PATTERN => ("desc" => rhs)`, so the human description
  sits between gesture and action (the description is optional; it defaults to
  `describe(pattern)`). The optional leading **`when(<expr over doc, sel>)`**
  statement becomes each binding's `applicable`. The macro emits the
  **module-qualified** `document_gestures_own(::Type{DocType})` method so it
  extends the kernel generic from any caller module (a bare `function
  document_gestures_own` would be hygienically gensym'd into a fresh local).
- **Sharing across types: inheritance + `@gesture_set`/`splice`.** A rule common
  to a whole type family goes on the common abstract supertype (`@gestures
  JsonDocument` → inherited by every JSON value). For a set shared by *unrelated*
  types with no common supertype, **`@gesture_set name begin … end`** defines a
  reusable `const name::Vector{GestureBinding}` (same body grammar, own
  precondition + `domain` tag), and **`splice(name)`** inside any `@gestures`
  block includes it in position; spliced bindings are shared objects, not copies.
  Both macros share one parser (`_parse_gesture_block`).
- **`read_document_gesture(doc, event)`** — the single interpreter that walks
  `document_gestures(typeof(doc))` first-match (`matches && applicable`, skipping
  a binding whose `operation` returns `nothing`). It is wired in as the
  `document_read(::Document, ::Any)` catch-all (the `= nothing` default was
  removed from `api/Document.jl`), so **what fires is provably the set that is
  shown**. Concrete `document_read(::SyntaxNode/::TextText, …)` methods remain
  more specific and still win.

## Stage 2 — generic fallback + `projection_gestures` seam + collector (kernel) ✅

- **Generic event fallback** in `program/src/common/Projection.jl`: folded into
  the existing leaf-default `projection_read(::Projection, iomap, operation)` —
  a raw `KeyPress`/`KeyDown`/`MousePress` delegates to
  `document_read(iomap.input, evt)` when `iomap.input isa Document`. (Folded into
  the default rather than added as a new `::Projection` 3-arg method, which would
  be **ambiguous** with the higher-order projections' 3-arg shims. Higher-order
  projections route events through their own 4-arg readers and never reach this
  leaf default.)
- **`projection_gestures(p, iomap)`** seam, default empty (kernel
  `GestureBindingModule`).
- **`collect_gestures(projection, recursion, iomap)`** — the data-driven
  generalization of `projection_read`'s 4-arg routing: a leaf default (in
  `GestureBindingModule`) = `projection_gestures(p, iomap)` ∪
  `document_gestures(iomap.input)`; combinator methods **beside their
  `projection_read` counterparts** — `Recursive` (pass-self), `TypeDispatching`
  (input-type dispatch), `Sequential` (gather every stage). Remaining combinators
  fall to the leaf default (degrade gracefully). `collect_gestures(editor)` over
  the latest iomap, and `applicable_gestures(doc, bindings)` filter by the
  selection. *(The JSON reader is root-relative, so applicability evaluated against
  the root document + its selection matches what the reader would fire; non-root-
  relative domains will want the collector to follow the selection to the focused
  sub-document — a follow-up once more domains are reified.)*

## Stage 3 — JSON migration (domain) ✅ [the original ask]

In `program/src/document/Json.jl`: `@gestures JsonDocument` (the shared
type-to-replace set, with a `when(_json_replaceable(doc, sel))` precondition for
the char-cursor / target / not-on-entry guards), `@gestures JsonArray` (`,`-insert),
`@gestures JsonObject` (`,`-insert, Tab). Moved `_array_insert` / `_object_insert`
/ `_object_tab` / `_is_char_cursor` / `_sel!` here, plus new helpers `_replace`,
`_replace_number`, `_json_replaceable`. Deleted the per-leaf and array/object
`KeyPress`/`KeyDown` readers in `program/src/projection/primitive/JsonToSyntax.jl`
(and trimmed the now-dead imports), keeping the structural
`ReplaceSelectionOperation` flat-offset override.

> Note: `_is_char_cursor` is effectively inert at the document layer because
> selection paths now carry `TypeReference` checkpoints between steps (it does not
> `skip_type_checkpoints`). This is **pre-existing** (copied verbatim) and does not
> affect behavior: a real character cursor inside a string/number is consumed
> upstream by `TextToGraphics` before reaching JSON; the digit-on-number decline
> is enforced by `_replace_number`'s own `target isa JsonNumber` guard. Left as-is
> for parity; worth fixing when char-cursor greying is wanted at the document layer.

## Stage 4 — help projection + invocation (domain) ✅ rendering / ⏸ invocation

**Rendering (done).** `GestureMap` document (`program/src/document/GestureMap.jl`)
of `GestureRow`s (gesture / description / domain / applicable), built by
`gesture_map(bindings, doc)` (applicability evaluated against `doc`'s selection).
`GestureMapToSyntax` (`program/src/projection/primitive/GestureMapToSyntax.jl`)
renders `describe(pattern) → description` rows grouped by a domain heading, greyed
+ `(n/a)`-tagged when not applicable (the v1 of Lisp's `accessible` colouring),
onto the existing `SyntaxToText → TextToGraphics` pipeline. `is_help_gesture(event)`
(kernel) recognizes the help summons — **F1** (`event isa KeyDown && key === :f1`).
Lisp's `Ctrl-H` / `Ctrl-?` is left for later: `Ctrl-?` needs `Ctrl+Shift+/`
handling, so F1 is the unambiguous v1. (Now that key chords landed in Stage 0, a
chord could also summon help, but that would need a `KeyChordPattern` / a chord
entry in the recogniser's table — neither wired; F1 stays the v1.)

**Invocation / overlay lifecycle (deferred — follow-up).** Building the overlay
(`GestureMap` + `GestureMapToSyntax`) is **domain-coupled**, but `read!` lives in
the **kernel**, which cannot reference domain types. A clean implementation needs
a small kernel seam (`help_overlay(editor)` default → nothing; a domain method
builds the pipeline), an Editor field holding the saved document/projection/iomap,
and read!-level handling: on `is_help_gesture` swap in the overlay (force reprint);
on any next gesture restore the prior state. Deferred to keep the core loop change
out of this (otherwise green) pass; the building blocks (`collect_gestures(editor)`,
`gesture_map`, `GestureMapToSyntax`, `is_help_gesture`) are all in place, so the
wiring is a contained follow-up. The render path is proven by `test_gesture_map`.

## Follow-up passes (seams already built; reify incrementally)

- **Wire the live help overlay** (Stage 4 invocation, above): kernel
  `help_overlay` seam + Editor saved-state + read! show/dismiss.
- **Decision (2026-06-24): gestures match modifiers _exactly_.** A gesture is
  identified by its exact modifier set, so `Left`, `Shift+Left`, `Ctrl+Left`,
  `Alt+Left` are *distinct* gestures and an unbound combination simply declines.
  This is what let SyntaxNode **and** TextText reify with **no kernel change**: the
  modifier logic lives in the pattern (exact), and the only thing operations need —
  the selection — they already get via `doc.selection`. The old readers matched
  bare arrows *loosely* (any modifiers) and filtered the declines out by hand;
  exact matching is equivalent for every tested/real input (verified: the nav/reader
  suites drive arrows only with `Modifiers()` / `Modifiers(ctrl=…)` / `…(alt=…)`,
  and every `Shift` in the suite is a distinct gesture like `Shift+Return`).
  *Convention wrinkle / possible follow-up:* in the shared `@event_case`/`@gestures`
  parser a bare `KeyDown(:left)` (no `;`) means *any* modifiers; an exact "plain
  Left" is the explicit empty set `KeyDown(:left;)`. Flipping the default so bare =
  exact-none would match the mental model but touches `@event_case` semantics +
  JSON's `KeyDown(:tab)`, so it is left as a separate cleanup.
- ✅ **`SyntaxNode` reified (2026-06-24).** Its tree-navigation `document_read`
  method is now an `@gestures SyntaxNode` table — Ctrl+Alt+Home (select root),
  Ctrl+Space (toggle structural/text cursor), Alt+arrow (`KeyDown(k; alt)`) and
  plain-arrow (`KeyDown(k;)`, exact none) tree-navigate. The selection-dependent
  rules live in the operation (reads `doc.selection`, returns `nothing` to decline).
  Behaviour unchanged: `test_tree_navigations` (40), `_complete` (144),
  `test_syntax_to_text` (124), `test_syntax_tree_selection` (29) all green.
- ✅ **`TextText` reified (2026-06-24).** Its `document_read` is now an
  `@gestures TextText` table — char insert (`KeyPress(_, t)`), Ctrl+. collapse,
  Backspace/Delete, Ctrl+Home/End jump, Ctrl+Left/Right word-motion, Left/Right
  char-motion — and the method plus the `_text_keypress_op`/`_text_delete_op`
  helpers were replaced by per-rule operation helpers (`_text_insert`,
  `_text_delete`, `_text_jump`, `_text_word_motion`, `_text_char_motion`). The old
  reader's explicit declines vanish under exact matching: `Alt+arrow`/`Tab` have no
  binding and propagate inward; the plain-arrow-while-structural decline lives in
  the char-motion op. Char-motion uses `KeyDown(:left;)` (exact none) so `Alt+Left`
  doesn't match it. Behaviour unchanged: `test_typeins` (111),
  `test_text_navigations` (6390 pass; the 4 fails are pre-existing Ctrl+Home-seed /
  adaptagrams-shim / conversation-v1 baselines — Ctrl+Home's pattern + logic are
  byte-identical to before), `_complete` (1443), `test_text_to_graphics` (55),
  `test_primitive_to_text` (45), `test_text` (19).
- **Projection-level fire==show interpreter** ✅ **(2026-06-24).** Added
  `read_projection_gesture(projection, iomap, event)` to `GestureBindingModule` —
  the projection-layer analogue of `read_document_gesture`: it fires the first
  matching binding from `projection_gestures(projection, iomap)` (passing
  `iomap.input` + its selection as `doc`/`sel`), so a projection whose reader
  delegates here *fires* exactly the table `collect_gestures` *shows*.
- Reify projection-level contributors via `projection_gestures` + the interpreter:
  - ✅ **Clipboard (2026-06-24)** — `ClipboardSliceToAnyProjection` (Ctrl+/ toggle,
    Ctrl+C/X/N copy/cut/note, Ctrl+V paste, Ctrl+Shift+V paste-copy) and
    `ClipboardCollectionToAnyProjection` (Ctrl+* toggle, Ctrl+= add, Ctrl+- remove)
    now author `projection_gestures` and fire via `read_projection_gesture`; the
    School-A content-child delegation is unchanged. Exact-modifier patterns make
    Ctrl+Shift+V (paste-copy) and Ctrl+V (paste) distinct. Behaviour unchanged:
    `test_clipboard_to_any` (all subtests incl. slice gestures 24, paste 12,
    collection 11), `test_gesture_binding` (46), `test_json_gesture_collection`
    (10), `test_gesture_map` (14) green. *(applicable left as `true` for v1 — the
    ops self-decline; per-gesture greying for help is a refinement.)*
  - ⏳ `FocusingProjection` (`Ctrl+,` / `Ctrl+.`) — same pattern; needs a
    characterisation test first (no existing coverage).
  - ⏳ `ConversationComposerToWidget` (Return / Shift+Return / Tab), generic
    mouse-select describe for `TextToGraphics` / `WidgetToGraphics`.
- Add `collect_gestures` methods for the remaining combinators (Nesting, Copying,
  Focusing, WindowManager, EnvelopeUnwrapping, Predicate/Reference-Dispatching) as
  their layers are reified, and teach the contextual collector to follow the
  selection into the focused sub-document for non-root-relative domains.
- Make `_is_char_cursor` `skip_type_checkpoints` if document-layer char-cursor
  greying is wanted (see Stage 3 note).
- **Composite-gesture patterns** (now that Stage 0's multi-click + chords landed):
  add a `KeyChordPattern` so `@gestures` can bind a `KeyChord` → operation and
  describe it (e.g. `"Ctrl+C Ctrl+K"`), and let `MousePressPattern` optionally match
  the `MousePress.count` for double/triple-click bindings. `MousePressPattern`
  currently ignores `count` (so every click still matches); neither is wired (no
  consumer yet) — these are the consumer side of Stage 0's new gestures.
- **gesture-help is sourced from reified bindings, not a keymap.** The "available
  gestures" catalogue comes from the readers'/documents' handled-gesture sets — i.e.
  `collect_gestures` over reified `@gestures` / `projection_gestures`. Because a
  gesture carries no intent (Stage 0), there is no separate named-intent keymap to
  enumerate; reifying more domains (above) is what grows the catalogue.

---

## Files

- **New:** `program/src/common/GestureBinding.jl` (patterns, `GestureBinding`,
  `document_gestures_own`/`document_gestures`, `@gestures`, `read_document_gesture`,
  `document_read` catch-all, `projection_gestures`, `collect_gestures` leaf default,
  `applicable_gestures`, `is_help_gesture`); included in `ProjecturedKernel.jl`.
- **Edit:** `program/src/api/Document.jl` (removed the `= nothing` default; the
  catch-all now comes from `GestureBindingModule`).
- **Edit:** `program/src/common/Projection.jl` (generic event fallback in the leaf
  default reader).
- **Edit:** `Sequential.jl` / `TypeDispatching.jl` / `Recursive.jl`
  (`collect_gestures` combinator methods); `Editor.jl` (`collect_gestures(editor)`).
- **Edit:** `program/src/document/Json.jl` (`@gestures` + relocated/new helpers).
- **Edit:** `program/src/projection/primitive/JsonToSyntax.jl` (dropped migrated
  readers + dead imports; kept structural flat-offset override).
- **New (domain):** `program/src/document/GestureMap.jl` +
  `program/src/projection/primitive/GestureMapToSyntax.jl`; included in
  `ProjecturedDomain.jl`; `GestureBindingModule` aliased in `ProjecturedDomain.jl`.
- **Re-export:** automatic via the umbrella's mechanical pass (no edit needed).

## Verification (narrowest covering tests first — never `test_all`) — results

- ✅ Kept green: `JsonToSyntax` printer, `SyntaxToText`/`TextToGraphics` nav,
  `test_xml_to_syntax`, `test_tree_navigations`, `test_collapse_roundtrip`,
  `test_primitive_to_text`, `test_syntax_tree_selection`.
- ✅ `GestureBindingTest` (`test_gesture_binding`, 34): `matches`/`describe`,
  supertype inheritance, `applicable`, interpreter routing.
- ✅ **`document_read` parity** (`test_json_to_syntax_reader`): 47/1/0 — identical
  to the pre-existing baseline (the line-117 array-insert selection quirk is
  pre-existing), for `n f t " [ : { ,` Tab and digits incl. the guard cases.
- ✅ `collect_gestures` state tests (`test_json_gesture_collection`, 10): root
  scalar vs. array whole/element vs. whole-object-entry vs. no-selection produce
  the expected applicable set.
- ✅ Help-projection render test (`test_gesture_map`, 14).

## Open questions — resolved

- **Where the block precondition lives in the macro surface** → a leading
  **`when(<expr over doc, sel>)`** statement (reads cleanly, parses as a one-arg
  `when` call distinct from the per-rule two-arg `when(PATTERN, cond)` guard).
- **`describe` for positional/mouse gestures** → generic labels ("Left click",
  "scroll", …) until Stage 0 intent names land.
- **Collector dedup key** → structural `pattern`/order; no dedup needed for the
  JSON prototype (each binding has a distinct pattern). Revisit when multiple
  domains contribute overlapping gestures.
- **Precise `accessible` via backward mapping** → deferred. v1 greys rows from
  each binding's `applicable` guard only; the full Lisp behaviour (map each
  descriptor backward through the pipeline) waits until the contextual collector
  is proven across more domains.

## Decisions made during implementation

- **Method-based registry, not a Dict** — own bindings live in
  `document_gestures_own(::Type{T})` methods so they survive precompilation; the
  macro emits a module-qualified method def to extend the kernel generic across
  module boundaries.
- **Single interpreter, not per-type generated readers** — `@gestures` only
  registers the table; one `document_read(::Document)` interpreter fires it, which
  *guarantees* fire == show parity by construction.
- **Generic fallback folded into the existing leaf default** — avoids method
  ambiguity with the higher-order 3-arg `projection_read` shims.
- **KeyPress ignores modifiers; KeyDown matches them exactly** — faithful to the
  backend (Ctrl never yields text input) and keeps chords (Ctrl+., Ctrl+Alt+Home)
  precise; the old defensive `ctrl` guard in the JSON reader was dropped.
- **F1 as the help gesture** (not Ctrl-? yet) — unambiguous without the
  char-under-Ctrl disambiguation.
- **Live overlay invocation deferred** — needs a kernel↔domain seam + core-loop
  change; building blocks are in place (see Stage 4).
