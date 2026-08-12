# Gesture pipeline: recognition + reified bindings + context-sensitive collection

> **Status (2026-08-12): DONE**, and further extended. Branch
> `worktree-reified-gesture-bindings` no longer exists, but the work is on
> `main`: `package/kernel/main/binding/` (`BindingLayer.jl`, `GestureBinding.jl`,
> `Gestures.jl`) is a full kernel layer, and
> `package/gesturehelp/main/GestureHelpDecorator.jl` defines
> `GestureHelpProjection` as described in Stage 4. Since this plan was written
> the API was substantially renamed and grown into a broader "binding intent"
> design: `document_gestures`/`projection_gestures`/`collect_gestures` (named
> below) do not exist under those names any more — the current surface is
> `get_document_gesture_bindings`, `fire_gesture_bindings`,
> `get_applicable_gesture_bindings`, and `collect_binding_intents` (see the
> `GestureBindingModule` docstring). `@gestures` itself is unchanged and is now
> used far beyond JSON — chart, fsm, json, pane, sequencechart, yaml, text,
> process, syntax, xml, julia, and workbench all define `@gestures` tables. One
> item below is re-confirmed still open: **drag** is still not recognised as a
> single gesture at the `GestureRecognizer` level (still "(future)" in its
> module docstring) — the drag support that does exist
> (`package/dragging/main/DraggingProjection.jl`) implements its own
> press→drag→drop state machine directly on raw `MouseDown`/`MouseMove`/`MouseUp`
> events, bypassing the recognizer rather than resolving the blocked item.

> **Status (implemented on branch `worktree-reified-gesture-bindings`).**
> Stages 0–4 **done**. Stage 4's **live help window** is now a `GestureHelpProjection`
> sibling-window opened via the tooltip-as-window rail (2026-06-24, superseding the
> reverted editor seam — see the ✅ note in Stage 4); it is **default-on** in
> `run_example` (F1).
>
> **Reification follow-ups (2026-06-25):** **all the document/projection editing readers
> are now reified** — `VersioningToAny`, `DocumentInsertion`, document-level
> `@gestures PrimitiveString` (de-duping both primitive projections), and the
> mode-dependent, assistant-shared **Conversation composer** (one `_composer_bindings`
> table that both `composer_read` fires and `projection_gestures` shows) — plus
> `collect_gestures` descent for the Clipboard/Versioning decorators. The remaining tail
> is **only** the geometry-coupled mouse-select *describe* (enumeration-only) and
> speculative no-consumer infra (chord/multi-click patterns); no `@event_case` editing
> reader remains.
>
> All targeted tests green; JSON `document_read` parity holds at
> the pre-existing 47/1/0 baseline. New tests: `test_gesture_binding` (34+),
> `test_json_gesture_collection` (10), `test_gesture_map` (14), `test_gesture_help` (33),
> `test_focusing` (6). Key decisions and the resolution of the open questions are recorded
> inline and under **“Decisions made during implementation”** at the end.

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
- **[../obsolete/gesture-help.md](../tentative/gesture-help.md)** — the `Ctrl-?`
  help. **Superseded by this plan:** its `merge_help` accumulation becomes the
  `collect_gestures` chain traversal here, and its per-reader `@gesture_case` is
  reframed as document-level `@gestures` + a `projection_gestures` seam. Retained
  for historical reference only — chiefly its detailed Lisp prior-art writeup
  (`command.lisp` / `merge-commands` / `help-to-text`), which is the model for
  Stage 4 and the `accessible` refinement below.

> Path note: this plan was written against the repo's old, pre-restructure
> `program/src/...` namespace. File paths quoted below have been updated to
> their current locations (mostly `package/kernel/main/...` and per-domain
> `package/<domain>/main/...`, per [documentation/domains.md](../../documentation/domains.md)).
> Several of the *symbol names* quoted below (`document_read`, `document_gestures`,
> `projection_gestures`, `collect_gestures`, `@event_case`/`EventCase.jl`) were
> also renamed after this plan shipped — see the status banner at the top for
> the current names.

---

## Current status (what already exists)

- ✅ **Recognizer** — `GestureRecognizer` (`package/kernel/main/gesture/GestureRecognizer.jl`)
  turns raw events into gestures; `MouseDown`+`MouseUp` → `MousePress`. Driven by
  `next_gesture!` in `Editor.read!`.
- ✅ **`document_read` seam** — declared in `package/kernel/main/document/DocumentInterface.jl`
  (`document_read(document, gesture) -> Operation|Nothing`), documented as *"the
  projection-independent half of a domain's reader."* Implemented for `TextBlock`
  (`package/text/main/Text.jl`) and `SyntaxNode` (`package/syntax/main/Syntax.jl`);
  delegated to from `SyntaxToText` / `TextToGraphics`.
- ✅ **`@event_case`** — the first-match pattern table over event structs
  (`package/kernel/main/event/EventPattern.jl`); its parser (`_parse_pattern` /
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
(`package/kernel/main/gesture/GestureRecognizer.jl`) turns raw device events into
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

New module `package/kernel/main/binding/GestureBinding.jl`
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
  removed from `api/DocumentApi.jl`), so **what fires is provably the set that is
  shown**. Concrete `document_read(::SyntaxNode/::TextBlock, …)` methods remain
  more specific and still win.

## Stage 2 — generic fallback + `projection_gestures` seam + collector (kernel) ✅

- **Generic event fallback** in `package/kernel/main/projection/Projection.jl`: folded into
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

In `package/json/main/Json.jl`: `@gestures JsonDocument` (the shared
type-to-replace set, with a `when(_json_replaceable(doc, sel))` precondition for
the char-cursor / target / not-on-entry guards), `@gestures JsonArray` (`,`-insert),
`@gestures JsonObject` (`,`-insert, Tab). Moved `_array_insert` / `_object_insert`
/ `_object_tab` / `_is_char_cursor` / `_sel!` here, plus new helpers `_replace`,
`_replace_number`, `_json_replaceable`. Deleted the per-leaf and array/object
`KeyPress`/`KeyDown` readers in `package/json/main/JsonToSyntax.jl`
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

**Rendering (done).** `GestureMap` document (`package/gesturehelp/main/GestureMap.jl`)
of `GestureRow`s (gesture / description / domain / applicable), built by
`gesture_map(bindings, doc)` (applicability evaluated against `doc`'s selection).
`GestureMapToSyntax` (`package/gesturehelp/main/GestureMapToSyntax.jl`)
renders `describe(pattern) → description` rows grouped by a domain heading, greyed
+ `(n/a)`-tagged when not applicable (the v1 of Lisp's `accessible` colouring),
onto the existing `SyntaxToText → TextToGraphics` pipeline. `is_help_gesture(event)`
(kernel) recognizes the help summons — **F1** (`event isa KeyDown && key === :f1`).
Lisp's `Ctrl-H` / `Ctrl-?` is left for later: `Ctrl-?` needs `Ctrl+Shift+/`
handling, so F1 is the unambiguous v1. (Now that key chords landed in Stage 0, a
chord could also summon help, but that would need a `KeyChordPattern` / a chord
entry in the recogniser's table — neither wired; F1 stays the v1.)

**Invocation / overlay lifecycle — ✅ implemented as a projection (2026-06-24).**

> **Architecture correction.** The first cut put the overlay in the *editor*
> (`help_overlay(editor)` seam + `Editor.help_saved` document/projection swap +
> F1-gated branches in `read!`, commit `4d64447`). That is *fishy*: it special-cases
> the core read-print loop and reaches *up* from `collect_gestures(editor)` to grab
> editor state. In ProjecturEd **everything is a projection** — context-sensitive
> help is a *view* concern, so it belongs in a decorator projection, not the editor.
> **The editor seam is to be reverted** in favour of the design below. (The editor
> already routes every gesture through `projection_read(editor.projection, …)`
> [`Editor.jl:170`], and decorator projections override the 4-arg `Change` reader
> [`Projection.jl:142`], so a top-of-chain projection intercepts F1 with no editor
> change at all.)

**Placement decision (2026-06-24): help is a _new window_, opened beside the
content** (not a pane-replacement), so the user sees **both** the context and the
available operations and can close the help when done. This maps **exactly** onto the
existing tooltip-as-window rail — no new windowing machinery:

`TooltipDecoratorProjection`
([`TooltipDecorator.jl`](../../package/visual/main/tooltip/TooltipDecorator.jl))
is a content-level decorator whose reader emits `OpenWindowOperation` /
`CloseWindowOperation` (carrying a `content::Document`); those bubble up to
`WindowManagerProjection` ([`WindowManager.jl`](../../package/kernel/src/projection/higherorder/WindowManager.jl)),
which appends/removes a real `WindowDocument` on the `ScreenDocument` and projects its
content through the same recursion. The gesture-help window is the same shape.

### ✅ Implemented (2026-06-24) — even simpler than the sketch above

The decorator **already prints its inner content**, so on F1 it collects over *its own
inner iomap* — no re-projection of the target, no `GestureHelp` wrapper document, no
separate `GestureHelpRenderProjection`. The help window's content is a plain (snapshot)
`GestureMap`, rendered by an ordinary `GestureMap => …` type-dispatch arm.

- **`GestureHelpProjection`** (`domain/projection/higherorder/GestureHelpDecorator.jl`) —
  content-level **decorator**, transparent printer (output is the inner's output, same
  object; retains `inner_iomap`). **Reader (4-arg `Change`):** the wrapped editor has
  priority (if it produced an op, that wins); else on `is_help_gesture` (F1) it
  `collect_gestures(p.inner, recursion, iomap.inner_iomap)` — the projection-form
  collector over the chain it just printed — builds `gesture_map(bindings, iomap.input)`,
  and emits `OpenWindowOperation(id=:gesture_help, style=:normal, content=gm)`. The op
  bubbles up unchanged (`_prefix_op`'s `else`) through `ScreenToScreen` to
  `WindowManagerProjection`, which opens a real sibling window — the tooltip rail. F1
  reaches the decorator because the `EventEnvelope` is dispatched into the focused
  window's content sub-iomap.
- **F1 toggles** via a shared mutable `GestureHelpState` (open flag): the example
  pipeline rebuilds the decorator per dispatch, so the state object — not the projection
  instance — is threaded through every decorator to keep the toggle stable. Second F1 →
  `CloseWindowOperation(:gesture_help)`. (Snapshot, not live: re-pressing F1 closes; press
  again to re-open against the now-current selection. Reactive liveness is a later
  refinement — `gesture_map` builds rows eagerly.)
- **`collect_gestures(NestingProjection)`** (`kernel/.../Nesting.jl`) — mirrors the
  reader's delegation to `elements[1]` over the child iomap, so collection descends
  through the example pipeline's per-window `NestingProjection(projections[i])` wrapper to
  the reified Sequential/document tables below it.
- **Wiring (`Examples.jl` `_multi_window_projection`):** wrap each window's content in
  `GestureHelpProjection(inner = NestingProjection(projections[i]; …), state = help_state)`
  (one shared `help_state`), and front the reference dispatch with a **type seam** so
  dynamically-opened windows render by content type:
  `TypeDispatchingProjection(WindowDocument => ScreenToScreen(), GestureMap =>
  SequentialProjection(GestureMapToSyntax(), RecursiveProjection(SyntaxToText()),
  WordWrapping(measure), TextToGraphics(measure)), Any => ref_dispatch)`. The seam is
  transparent for existing content (`Any → ref_dispatch`), and the `WindowDocument` arm is
  only hit when the manager re-projects a freshly-opened window — so **no regression**
  (the base variant never opened windows before). This makes help **default-on** in
  `run_example` (no `tooltip=true` needed).

**Close:** F1 toggle only, for now. The native window **close button**
(`WindowCloseRequest`) is *not* wired to remove a window for any window type yet (would
change main-window behaviour) — a scoped `WindowCloseRequest → CloseWindowOperation`
(by id/style) is a follow-up, as is `Esc`-to-close from within the help window.

> No `showing`/`help_saved` state, no editor branch, no document mutation by the editor.
> F1 → `OpenWindowOperation` (bubbles up) → `WindowManager` opens the window; the help
> window renders the collected gestures and F1 toggles it. Pure projection + the window rail.

**Tests** (`test/projection/GestureHelpTest.jl`, `test_gesture_help`, 33): decorator F1 →
`OpenWindowOperation` whose `GestureMap` rows equal `collect_gestures` over the inner
iomap; toggle close; non-help pass-through; transparent printer; an **end-to-end** mini
screen pipeline (F1 opens/closes a real window); and a roundtrip through the **real**
`_multi_window_projection` + `make_json_projection_example` rendering to graphics — which
collects **23** rows (JSON 9 + syntax tree-nav + text), proving *fire == show* across the
whole content pipeline, not just the leaf document. Regression-checked:
`test_printer(json/workbench)`, `test_repl(json)` green (they use `example.projection`
directly, already independent of `_multi_window_projection`).

> Commits: revert `24a5b58`; decorator + collect + unit/e2e tests `edfcf42`, `753bc86`;
> wiring + integration test `30610e2`.

## Follow-up passes (seams already built; reify incrementally)

- ✅ **Live help window (2026-06-24)** — a sibling window opened via the
  tooltip-as-window rail. F1 in the focused content fires a `GestureHelpProjection`
  content decorator, which collects over its own inner iomap and emits
  `OpenWindowOperation(:gesture_help, content=gesture_map(…))`; the `WindowManager` opens
  a real window beside the content rendering the collected gestures; F1 toggles it.
  Default-on in `run_example`. Editor-seam first cut (`4d64447`) reverted (`24a5b58`).
  Decorator + `collect_gestures(NestingProjection)` + tests `edfcf42`/`753bc86`; wiring
  `30610e2`. Follow-ups: reactive (live) help instead of snapshot; native close-button /
  `Esc`-to-close; wire the `tooltip`/`inspector` pipeline variants too (only the default
  `_multi_window_projection` is wired).
- **Decision (2026-06-24): gestures match modifiers _exactly_.** A gesture is
  identified by its exact modifier set, so `Left`, `Shift+Left`, `Ctrl+Left`,
  `Alt+Left` are *distinct* gestures and an unbound combination simply declines.
  This is what let SyntaxNode **and** TextBlock reify with **no kernel change**: the
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
- ✅ **`TextBlock` reified (2026-06-24).** Its `document_read` is now an
  `@gestures TextBlock` table — char insert (`KeyPress(_, t)`), Ctrl+. collapse,
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
  - ✅ **`FocusingProjection` (2026-06-24)** — `Ctrl+,` focus-out / `Ctrl+.` focus-in
    now author `projection_gestures` and fire via `read_projection_gesture`
    (focus-out gated by `applicable = !isempty(part)`; focus-in self-declines via a
    `_focus_in` helper). Added the missing test coverage — `test_focusing` (6), incl.
    exact-modifier (a bare comma is not focus-out). Note: a multi-line
    `(doc,event) -> begin…end` lambda will not parse inside a `GestureBinding(...)`
    arg list — extract a named helper (single-expression lambdas are fine).
  - ✅ **`VersioningToAnyProjection` (2026-06-25, `4ce634d`)** — `Ctrl+Shift+S` create
    version / `Ctrl+Delete` delete version now author `projection_gestures` and fire via
    `read_projection_gesture`; value-child delegation + op re-rooting unchanged. Green:
    `test_versioning_to_any` (53), `test_clipboard_to_any` (66).
  - ✅ **`DocumentInsertion` / `InsertionToSyntaxLeaf` (2026-06-25, `feaf40c`)** — char
    insert / Commit (Return→`p.commit`) / Cancel (Escape→`DocumentNothing`) /
    Backspace / Delete reified as `projection_gestures` (Commit/Cancel stay projection-
    level — they need `p.commit`). Bare patterns kept loose (`mods=nothing`) to preserve
    the old `@event_case` semantics exactly. Green: `test_document_insertion` (14),
    `test_conversation_editor` (29).
  - ✅ **`ConversationComposerToWidget` (2026-06-25)** — the mode-dependent composer is
    reified as **one** `_composer_bindings(draft)` table that branches on the active part
    type (`PrimitiveString` / `DocumentInsertion` / `JuliaInsertion` / `Json|XmlInsertion`),
    which **both** `composer_read` *fires* (a small first-match loop, preserving its
    `(draft, evt)` signature — so the **shared assistant panel** path is unchanged) **and**
    `projection_gestures` *exposes* (so the help window shows exactly what fires). The
    projection reader's `ComposerSubmitOperation`→host-submit post-processing is untouched.
    Modifier semantics preserved exactly (the old `@event_case` `[:shift]`/`[:alt]` exact
    rows precede the bare any-modifier row). Char-insert now ignores modifiers (KeyPress
    convention, like Text/JSON/Primitive). Green: `test_conversation_editor` (38, incl. a
    new fire==show show-side test), `test_assistant_mvp` (only the pre-existing collapse-
    width fail), `test_repl(conversation)` (221 key-event paths green; the 4 MousePress
    `FieldError(...:children)` fails are pre-existing on main — conversation mouse not wired).
  - ⏳ Generic mouse-select describe for `TextToGraphics` / `WidgetToGraphics` /
    `LayoutToGraphics` (enumeration-only — the click hit-testing stays geometry-coupled;
    the *keyboard* parts already delegate to `document_read`).
- ✅ **Document-level `@gestures PrimitiveString` (2026-06-25, `efcdcf9`)** — char
  insert / Backspace / Delete were duplicated verbatim in `PrimitiveStringToTextBlock`
  and `PrimitiveStringToSyntaxLeaf` (both producing a `StringReplaceRangeOperation` in
  the `value[range]` vocabulary). Reified once at the document level; both projections
  reach it through the generic `document_read` fallback and their per-projection readers
  are deleted. Convention note: KeyPress ignores modifiers (matches Text/JSON), so the
  old defensive ctrl-printable reject is gone (two tests updated). Green:
  `test_primitive` (33), `test_primitive_to_text` (46), `test_object_to_widget` (46),
  `test_widget_text_editing` (9).
- **`collect_gestures` combinator coverage** — ✅ `Nesting` (with the help window),
  ✅ `Clipboard` (both) + ✅ `Versioning` decorators descend into their content/value
  child (2026-06-25, `c9a6c1c`; test: collect over a clipboard wrapping a `PrimitiveString`
  yields both `Copy` and `Insert character`). ⏳ Remaining (lower value / subtler):
  `Copying` + `WindowManager` + `EnvelopeUnwrapping` + `Predicate/Reference-Dispatching`,
  and teaching the collector to *follow the selection* into the focused sub-document for
  `Focusing` / non-root-relative domains (the leaf default already shows focus in/out +
  the root's gestures, so this is a de-duplication refinement, not a gap).
- Make `_is_char_cursor` `skip_type_checkpoints` if document-layer char-cursor
  greying is wanted (see Stage 3 note). *(Inert/pre-existing — no behavioural benefit
  until per-gesture greying is wanted; left as-is.)*
- **Composite-gesture patterns** (now that Stage 0's multi-click + chords landed):
  add a `KeyChordPattern` so `@gestures` can bind a `KeyChord` → operation and
  describe it (e.g. `"Ctrl+C Ctrl+K"`), and let `MousePressPattern` optionally match
  the `MousePress.count` for double/triple-click bindings. `MousePressPattern`
  currently ignores `count` (so every click still matches); **neither is wired (no
  consumer yet)** — left as speculative until a gesture actually needs a chord/multi-click.
- **gesture-help is sourced from reified bindings, not a keymap.** The "available
  gestures" catalogue comes from the readers'/documents' handled-gesture sets — i.e.
  `collect_gestures` over reified `@gestures` / `projection_gestures`. Because a
  gesture carries no intent (Stage 0), there is no separate named-intent keymap to
  enumerate; reifying more domains (above) is what grows the catalogue.

---

## Files

- **New:** `package/kernel/main/binding/GestureBinding.jl` (patterns, `GestureBinding`,
  `document_gestures_own`/`document_gestures`, `@gestures`, `read_document_gesture`,
  `document_read` catch-all, `projection_gestures`, `collect_gestures` leaf default,
  `applicable_gestures`, `is_help_gesture`); included in `ProjecturedKernel.jl`.
- **Edit:** `package/kernel/main/document/DocumentInterface.jl` (removed the `= nothing` default; the
  catch-all now comes from `GestureBindingModule`).
- **Edit:** `package/kernel/main/projection/Projection.jl` (generic event fallback in the leaf
  default reader).
- **Edit:** `Sequential.jl` / `TypeDispatching.jl` / `Recursive.jl`
  (`collect_gestures` combinator methods); `Editor.jl` (`collect_gestures(editor)`).
- **Edit:** `package/json/main/Json.jl` (`@gestures` + relocated/new helpers).
- **Edit:** `package/json/main/JsonToSyntax.jl` (dropped migrated
  readers + dead imports; kept structural flat-offset override).
- **New (domain):** `package/gesturehelp/main/GestureMap.jl` +
  `package/gesturehelp/main/GestureMapToSyntax.jl`; included in
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
