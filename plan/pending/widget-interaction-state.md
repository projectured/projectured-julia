# Widget interaction state — shared `enabled` + formalized hover/pressed

> **Status: planning / not started.** Detailed plan for **Stage 1** of
> [qt-widget-gap-analysis.md](qt-widget-gap-analysis.md) ("Shared interaction
> state"). Generated 2026-06-26 against the current tree
> (`package/domain/src/...`). Verified file:line citations below.

## Goal

Give the widget layer a shared, first-class notion of **interactivity state**
beyond the existing `visible` flag:

1. A shared `enabled::Bool` field (default `true`) on interactive widgets, with
   a muted/disabled appearance driven by theme tokens.
2. **Reader-side gating:** a disabled widget refuses to emit operations.
3. Formalize the today-ad-hoc `hovered`/`pressed` cells (currently only on
   `WidgetButton`) into a documented, shared convention so the next widgets that
   need them follow one pattern.

This is the prerequisite Stage for forms (Stage 6), dialogs (Stage 3), and the
focus model (Stage 2). It is deliberately the *smallest* cross-cutting feature:
it extends the existing shared-field pattern (`visible` + box-model) rather than
introducing new machinery.

## Non-goals (explicitly deferred)

- **Focus / `focused` state and the focus ring** — that is Stage 2. The `ring`
  theme token already exists (`WidgetToGraphics.jl:129`) but no `focused` field
  is added here.
- **Hover/press for widgets that don't have it yet.** We formalize the
  *convention* and document it; we do not retrofit `hovered`/`pressed` onto every
  widget. They get added per widget when that widget grows interactive feedback.
- New widgets (spinbox, dialog, etc.) — later stages.

---

## Background: how the shared-field pattern actually works

Two facts dictate the mechanics (both verified):

1. **No inline struct defaults.** `@document` structs list fields with *no*
   `= default`; e.g. `WidgetButton` declares `visible::Bool`
   (`Widget.jl:200-217`), `WidgetCheckbox` declares `visible::Bool`
   (`Widget.jl:150-161`). The default `visible=true` comes from a hand-written
   **convenience constructor** that takes `visible::Bool=true` as a keyword,
   wraps every field in `Cell(...)`, and calls the macro-generated **all-positional**
   constructor in field order (`WidgetCheckbox` ctor `Widget.jl:163-178`,
   `WidgetButton` ctor `Widget.jl:218-235`).

   ⇒ Adding a field is a **three-edit, order-sensitive** change per widget:
   add it to the struct body, add the `enabled::Bool=true` keyword to the
   convenience ctor, and add `Cell(enabled)` in the matching positional slot.
   Getting the slot order wrong silently shifts every later field — covered by
   tests below.

2. **The printer gates on `visible` at the top** and renders an empty canvas
   when false: `w.visible == false && return SimpleIoMap(p, w, _empty_canvas())`
   (e.g. `WidgetToGraphics.jl:867`). The `enabled` appearance branch slots in
   right after this guard.

3. **Readers emit operations in `projection_read`.** Only four interactive
   leaves currently have a reader that produces an edit/action operation:
   - `WidgetCheckbox` → `ReplaceReferencedValue(w, content, !checked)`
     (`WidgetToGraphics.jl:854-858`)
   - `WidgetButton` → `InvokeWidgetActionOperation(w)` plus pressed/hover cell
     writes (`WidgetToGraphics.jl:909-922`)
   - `WidgetText` → text edits (`WidgetToGraphics.jl:794-...`)
   - `WidgetMenuItem` → selection/invoke (`WidgetToGraphics.jl:1003-...`)

   `WidgetSwitch`, `WidgetSlider`, `WidgetToggle`, `WidgetToggleGroup`,
   `WidgetRadioGroup`, `WidgetSelect` have **no own reader** in
   `WidgetToGraphics.jl` — their interaction is routed through the configuring
   `ObjectToWidget` layer / their `content`. They get the `enabled` *field* (for
   appearance + future) now; they get *gating* when/if they grow their own
   reader.

4. **Theme tokens already exist** for the disabled look — no new tokens needed:
   `muted` and `muted_foreground` (`WidgetToGraphics.jl` theme struct
   `109-152`; slate_light values `240,245`). The printer reads precomputed
   `p.*` color fields, so the disabled branch substitutes the muted token where
   the projection resolves its surface/foreground colors.

---

## Step 1 — Add the `enabled` field (reference pair: Button + Checkbox)

Land the field on the two widgets that have both a reader and a printer, as the
reviewable reference implementation, before fanning out.

For **`WidgetCheckbox`** and **`WidgetButton`**:

- **Struct:** add `enabled::Bool` immediately after `visible::Bool`
  (`Widget.jl:154` / `Widget.jl:205`). Keeping it adjacent to `visible` mirrors
  "interactivity flags grouped first" and keeps the slot easy to audit.
- **Convenience ctor:** add keyword `enabled::Bool=true`
  (`Widget.jl:163-178` / `218-235`) and insert `Cell(enabled)` in the matching
  positional slot (right after `Cell(visible)`).
- **Docstring:** note `enabled` alongside the `visible`/box-model description in
  the `WidgetButton` doc block (`Widget.jl:184-199`) and add the equivalent line
  for `WidgetCheckbox`.

**Tests:** `WidgetCheckbox(p, c)` and `WidgetButton(p, s, c)` default
`enabled == true`; `WidgetButton(...; enabled=false).enabled === false`; the
positional ctor still round-trips (guards against a wrong slot).

## Step 2 — Gate the readers

At the top of each interactive `projection_read`, before any operation is
produced, add:

```julia
w.enabled === false && return nothing
```

- `WidgetCheckbox` reader (`WidgetToGraphics.jl:854`) — both the `MousePress`
  method and keep the catch-all returning `nothing`.
- `WidgetButton` reader (`WidgetToGraphics.jl:909`) — guard so that a disabled
  button neither invokes its action **nor** flips `pressed`/`hovered` (so it
  can't show the pressed surface while disabled).

**Tests:** a disabled checkbox `MousePress` yields `nothing` (no
`ReplaceReferencedValue`); a disabled button `MousePress` yields `nothing` (no
`InvokeWidgetActionOperation`) and a `MouseDown` does not set `pressed`.

## Step 3 — Disabled appearance

In each printer, right after the `visible` guard, branch on
`w.enabled === false` to render the muted surface:

- Checkbox printer (`WidgetToGraphics.jl:820-838`): when disabled, draw the box
  with `muted` fill / `muted_foreground` outline+check instead of
  `p.background_color` / `p.checked_color`.
- Button printer (`WidgetToGraphics.jl:867-881`): when disabled, force
  `fill = muted` and the label foreground to `muted_foreground`, and **skip** the
  `pressed > hover > resting` surface selection (a disabled control has no
  interaction surface).

Resolve the muted color from the theme the same way the printer already obtains
its other `p.*` colors (thread `muted`/`muted_foreground` into the projection's
precomputed color set if not already present). Keep the change minimal: one
`enabled` branch per printer.

**Tests:** a disabled checkbox/button renders with the muted token (assert the
canvas fill color), and the disabled button ignores `hovered=true` (no hover
fill).

## Step 4 — Formalize the hover/pressed convention

No behavior change — make the existing `WidgetButton` `hovered`/`pressed` cells a
documented shared convention so the next interactive widget copies one pattern:

- Add a short section to
  [documentation/document/widget.md](../../documentation/document/widget.md)
  describing: (a) `enabled` as a shared interactivity field next to `visible`;
  (b) the `hovered`/`pressed` transient-cell convention (written by the reader
  via `ReplaceReferencedValue(self, "hovered"/"pressed", …)`, read by the printer
  to pick the surface, not serialized — mirroring the `WidgetButton` doc block at
  `Widget.jl:184-199`); (c) the rule that disabled readers return `nothing` and
  disabled printers use `muted`/`muted_foreground`.
- No new helper is required for Stage 1; if a second widget needs hover/press
  during this stage, copy the `WidgetButton` field+ctor+reader pattern.

## Step 5 — Carry `enabled` on the remaining interactive widgets (field only)

Add the `enabled::Bool=true` field (struct + ctor + `Cell(enabled)` slot) to the
other interactive controls so the document model is uniform and a configuring
projection can bind/disable them, even though their readers gate later:
`WidgetText` (`Widget.jl:111`), `WidgetTextarea` (`970`), `WidgetSelect` (`953`),
`WidgetSwitch` (`792`), `WidgetSlider` (`825`), `WidgetToggle` (`917`),
`WidgetToggleGroup` (`934`), `WidgetRadioGroup` (`843`), `WidgetMenuItem` (`322`).

Where a printer is easy to branch (switch/toggle/select), add the muted
appearance too; where the reader exists (`WidgetText`, `WidgetMenuItem`), add the
Step-2 gate. Otherwise field-only for now, with a one-line note that gating
lands when the reader does. **Do not** touch pure display/container widgets
(label, badge, card, separator, progress, skeleton, avatar, alert, composite,
toolbar, shell, scrollpane, tabbedpane, table, tree) — `enabled` is meaningless
there.

## Step 6 — Example + sweep

- Add a small `enabled`/disabled showcase to the widget example
  (`package/example/src/projection/Widget.jl`): a row with an enabled vs disabled
  button and checkbox so `run_example` / screenshots show the muted state and a
  click-swallow can be exercised.
- Run the targeted widget tests, then `test_printers()` / `test_readers()` once
  green to catch any positional-ctor slot regression across the suite.

---

## Risks / watch-outs

- **Order-sensitive positional ctor (Step 1 fact #1).** The macro-generated
  all-positional constructor takes fields in declaration order; a mis-placed
  `Cell(enabled)` shifts every later argument with no compile error. Mitigate by
  keeping `enabled` adjacent to `visible` everywhere and asserting a positional
  round-trip in tests.
- **Configuring projection interaction.** `ObjectToWidget` redirects a control's
  `ReplaceReferencedValue(self, "content", …)` onto the bound parameter cell. A
  disabled reader returning `nothing` *upstream* means that redirect never fires
  — correct, but confirm no configuring path reads the control's operation by
  identity expecting it to always be present.
- **Muted color resolution.** If a printer's `p.*` color set doesn't already
  carry `muted`/`muted_foreground`, threading it through the projection
  constructor is the only non-trivial bit of Step 3 — keep it to adding the two
  fields where needed.

## Test checklist (smallest scope first)

- `test_example(widget_example)` (printer + reader + navigation for the showcase).
- `test_printer(widget_example)` — muted appearance asserts.
- `test_reader(widget_example)` — disabled click-swallow asserts.
- Then `test_printers()` / `test_readers()` for the positional-ctor sweep.

## Step status

- [ ] Step 1 — `enabled` field on Button + Checkbox (struct + ctor + docstring)
- [ ] Step 2 — gate Button + Checkbox readers
- [ ] Step 3 — disabled muted appearance for Button + Checkbox
- [ ] Step 4 — document the `enabled` + hover/pressed convention
- [ ] Step 5 — `enabled` on remaining interactive widgets (gate where reader exists)
- [ ] Step 6 — example showcase + printer/reader sweep
