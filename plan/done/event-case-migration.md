# Migrate event dispatch to `@event_case`

> **Status: done — all three phases shipped.** Phase 1: `Focusing`,
> `PrimitiveToSyntax`, `PrimitiveToText`, `WorkbenchAssistant`. Phase 2:
> `WidgetToGraphics` (four routing tables) and `LayoutToGraphics` (one shared
> `_route_layout_event` helper for the four identical layout readers). Phase 3:
> `TextToGraphics` (chord/decline/navigation + backspace/delete) and
> `SyntaxToText` (tree-navigation table). Modifier policy settled per site:
> deliberate ctrl chords adopt **exact** matching (`KeyDown(:period; ctrl)`,
> Ctrl+Home/End); the alt/structural decline guards and the
> Ctrl+Alt+Home/Ctrl+Space chords in `SyntaxToText` stay **loose** (via
> `when`-guards) so any alt-modified or structural arrow remains a tree gesture
> — matching the plan's "readability, not behaviour change" directive. Every
> migrated reader passes its reader/repl/selection (and where relevant
> tree-navigation/click-roundtrip) test; one file per commit. Pre-existing
> branch failures (`dbcatalog`/`sql_syntax` click roundtrips, widget-example
> selection `state_count`, the unicode text-selection ordering bug, and the
> assistant-MVP scenes) were confirmed present on baseline and left untouched.


The `@event_case` macro already exists and is tested — see
[`program/src/device/EventCase.jl`](../../program/src/device/EventCase.jl)
and [`test/src/device/EventCaseTest.jl`](../../test/src/device/EventCaseTest.jl).
It is a first-match-wins dispatch table over the keyboard/mouse event types
in [`device/Keyboard.jl`](../../program/src/device/Keyboard.jl) and
[`device/Mouse.jl`](../../program/src/device/Mouse.jl), the sibling of
`@reference_case`. This plan covers replacing the hand-rolled
`evt isa …` / `evt.key === …` / `evt.modifiers.…` branching in the projection
readers with it.

The goal is readability, not behaviour change: start where the win is real
(keyboard/modifier tables) and leave the sites where the macro adds nothing.

## Two structural shapes

Readers dispatch on events in two ways, and only one is a clean win:

1. **Untyped method + internal `isa`** — e.g. `projection_read(p, iomap, evt)`
   that does its own `evt isa KeyDown`. These are the clean `@event_case`
   wins.
2. **Type-dispatched methods** — e.g.
   `projection_read(p, iomap, evt::KeyDown)`. Julia already did the type
   split via multiple dispatch; `@event_case` only helps the *internal*
   `.key`/`.modifiers` branch, so it is worth it only when that branch is a
   real multi-key table — not for one or two `if evt.key ==` checks. Merging
   the per-type methods into one untyped reader is a bigger refactor; do it
   only where it genuinely simplifies.

## The decision that affects every site: modifier exactness ⚠️

`@event_case` matches listed modifiers **exactly**: `KeyDown(:comma; ctrl)`
means ctrl held *and* shift/alt/meta absent. Almost all existing code is
**loose** — `is_ctrl(event)`, or `evt.modifiers.ctrl && …` without checking
the others. So a naive migration *tightens* behaviour (a shortcut stops
firing when an extra modifier happens to be held).

Per site, pick one:

- **Adopt exact** (recommended where the code is a deliberate shortcut) —
  usually the more-correct behaviour, and the cleanest pattern.
- **Preserve loose** — omit the `;` block and keep the predicate in a guard:
  `when(KeyDown(:comma), is_ctrl(evt)) => …`.

Note that omitting the `;` block entirely leaves modifiers **unconstrained**
(this is deliberate: it keeps character insertion working, since a shifted
capital letter carries `shift = true` —
[`Sdl.jl:237`](../../program/src/backend/Sdl.jl#L237)). So a key with no
modifier check today (e.g. `:backspace`) migrates safely to `KeyDown(:backspace)`
with no `;`.

The default for this work is **adopt-exact**, flagging any site where that is
a judgement call. Either way, every migrated reader must pass its
reader/repl/selection test before moving on (see Testing below).

## Deferred: two files with in-progress work

[`TextToGraphics.jl`](../../program/src/projection/primitive/TextToGraphics.jl)
and [`SyntaxToText.jl`](../../program/src/projection/primitive/SyntaxToText.jl)
had uncommitted in-progress changes (the `TreeNavigateOperation` work) at the
time this plan was written. Migrating them then would have collided. **Defer
both** until that work is committed; migrate them as the final phase.
`TextToGraphics`'s `KeyDown` chord/nav/delete table is the single richest
win once it is unblocked.

## Site inventory

### Tier 1 — clear wins (keyboard / modifier tables)

| Site | Today | Migration note |
| --- | --- | --- |
| [`Focusing.jl:70-89`](../../program/src/projection/generic/Focusing.jl#L70-L89) | `KeyDown && is_ctrl`, then `:comma` / `:period` | `KeyDown(:comma; ctrl)` / `KeyDown(:period; ctrl)`. Exactness call (today loose `is_ctrl`). Keep the `ReplaceSelectionOperation` branch as its own method. |
| [`PrimitiveToSyntax.jl:163-198`](../../program/src/projection/primitive/PrimitiveToSyntax.jl#L163-L198) | `KeyPress` (ctrl-guard) + `KeyDown` backspace/delete | Optionally merge into one untyped reader: ctrl-guarded `KeyPress` insert + `KeyDown(:backspace)` / `KeyDown(:delete)`. Backspace/delete have no modifier check today → omit `;` (loose preserved, safe). |
| [`PrimitiveToText.jl:146-168`](../../program/src/projection/primitive/PrimitiveToText.jl#L146-L168) | Same shape as above | Same approach. |
| [`WorkbenchAssistant.jl:674-695`](../../program/src/editor/WorkbenchAssistant.jl#L674-L695) | `KeyPress` ctrl-guard; `KeyDown` `:return` + `alt?` | `KeyDown(:return; alt) => SubmitJuliaOperation` / `KeyDown(:return) => SubmitProseOperation`. Editor layer — verify with repl/typein tests. |
| **`TextToGraphics.jl`** (chord/nav/delete table) | big `evt isa KeyDown` table | **Deferred (WIP).** Richest win once unblocked. |
| **`SyntaxToText.jl`** (`KeyDown` passthrough) | — | **Deferred (WIP).** |

### Tier 2 — routing tables (moderate, optional)

- [`WidgetToGraphics.jl`](../../program/src/projection/primitive/WidgetToGraphics.jl)
  `if evt isa MouseScroll … elseif evt isa MousePress … else …` blocks:
  [658-671](../../program/src/projection/primitive/WidgetToGraphics.jl#L658-L671),
  [967-990](../../program/src/projection/primitive/WidgetToGraphics.jl#L967-L990),
  [1215-1219](../../program/src/projection/primitive/WidgetToGraphics.jl#L1215-L1219),
  [1342-1377](../../program/src/projection/primitive/WidgetToGraphics.jl#L1342-L1377).
  The branches do coordinate math, so the result binds `x, y, dx, dy, button` —
  readable but not dramatically shorter. Migrate only for consistency.
- [`LayoutToGraphics.jl`](../../program/src/projection/primitive/LayoutToGraphics.jl) —
  four identical `MousePress` / `MouseScroll` guard pairs
  ([359-360](../../program/src/projection/primitive/LayoutToGraphics.jl#L359-L360)
  and three twins). Best handled by one shared helper that uses `@event_case`
  once, rather than four inline conversions.

### Tier 3 — leave as-is (no gain)

Single-line guards `evt isa X || return nothing` — `WidgetToGraphics`
474 / 509 / 542 / 573 / 726 / 1410 / 1456, and
[`GraphicsCaching.jl:129`](../../program/src/projection/primitive/GraphicsCaching.jl#L129).
The macro does not beat a one-line guard.

## Phasing

1. **Phase 1 (Tier 1, non-WIP):** Focusing → PrimitiveToSyntax →
   PrimitiveToText → WorkbenchAssistant. One file per commit; run the
   narrowest covering test after each. This also dogfoods the macro against
   real code.
2. **Phase 2 (Tier 2):** WidgetToGraphics routing blocks + a shared
   LayoutToGraphics helper — only if we want full consistency. Same per-file
   test discipline.
3. **Phase 3 (deferred):** TextToGraphics + SyntaxToText, after the
   `TreeNavigateOperation` work is committed.

## Testing

Per [`CLAUDE.md`](../../CLAUDE.md): run the narrowest test that covers each
change — e.g. `test_reader(json_example)` / `test_repl(...)` /
`test_primitive_to_text()` / `test_text_to_graphics()`. Reader behaviour is
exactly what these cover, so regressions (especially from modifier
tightening) surface immediately. Reach for the broad sweeps
(`test_readers()` / `test_selections()` / `test_repls()`) only as a final
check after Phase 1, and `test_all()` rarely. See
[`guide/testing.md`](../../guide/testing.md).

## Open decisions

1. **Modifier exactness default** — adopt-exact (recommended) vs.
   preserve-loose-via-guards. Settle per site, defaulting to exact.
2. **Scope** — Phase 1 only (the real wins) vs. also Phase 2 routing blocks.
