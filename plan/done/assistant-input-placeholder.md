# Assistant typein field: drop quotes, show a pale "type message here" placeholder

> **Status: DONE.** Renamed `PrimitiveStringToText` → `PrimitiveStringToTextText`,
> added optional placeholder support, and rerouted the assistant input through
> `Primitive → Text → Graphics` in both projection factories. Verified: empty
> input renders `type message here` in pale gray with **no quotes**; typing
> replaces it; `test_primitive_to_text`, `test_printer`/`test_reader`/
> `test_selection(assistant_example)` pass; `.input.value` typein passes.
> (The `.model`/`.system`/`.api_key`/`.llm.reply` typein failures are
> **pre-existing** — those fields are not rendered in the assistant UI — confirmed
> identical against the HEAD projection.)

## Goal

The assistant compose field (the editable prompt at the bottom of the
`WorkbenchAssistant`) currently renders as a `PrimitiveString` projected through
the `Primitive → Syntax → Text` chain, so when it is empty it shows two literal
yellow quote glyphs `""`, and when it has text the prose is wrapped in quotes.
We want it to render as a plain, **unquoted** field that, when empty, shows a
muted/pale **`type message here`** hint that vanishes as soon as the user types.

## Approach

Instead of teaching the quoted `SyntaxLeaf` projection to hide its quotes,
project the input **directly into the text domain** with the existing
`PrimitiveString → TextText` projection (no intervening `SyntaxLeaf`, so there
are no quotes to begin with), **renamed to `PrimitiveStringToTextText`** and
extended with optional placeholder support, and route the assistant input
through it.

## Background — how the input is projected today

- `WorkbenchAssistant.input` is a `PrimitiveString` (`PrimitiveString("")` by
  default) — [program/src/document/Workbench.jl:298](../../program/src/document/Workbench.jl#L298),
  [Workbench.jl:308](../../program/src/document/Workbench.jl#L308). It is the
  **only** `PrimitiveString` reachable through the workbench/assistant documents
  (grep confirms: the only other editor-layer mention is the `_text_to_string`
  accessor).
- `WorkbenchAssistantToWidgetSplitPane.projection_print` builds the input pane
  as `WidgetScrollPane(a.input; …)` —
  [program/src/projection/primitive/WorkbenchToWidget.jl:310](../../program/src/projection/primitive/WorkbenchToWidget.jl#L310).
  The scroll pane projects its content through the **outer recursion**, so the
  `PrimitiveString` is routed by the top-level `TypeDispatchingProjection`'s
  `PrimitiveDocument` entry (see the comment at
  [WorkbenchToWidget.jl:301-307](../../program/src/projection/primitive/WorkbenchToWidget.jl#L301-L307)).
- Today that entry runs `Primitive → Syntax → Text → Graphics`:
  ```julia
  PrimitiveDocument => SequentialProjection(
      RecursiveProjection(PrimitiveToSyntax()),
      RecursiveProjection(SyntaxToText()),
      text_to_graphics)
  ```
  - assistant-only: [example/src/projection/Assistant.jl:25-28](../../example/src/projection/Assistant.jl#L25-L28)
  - full workbench: [example/src/projection/Workbench.jl:24](../../example/src/projection/Workbench.jl#L24)
- The string-to-syntax step `PrimitiveStringToSyntaxLeaf` is what injects the
  quotes: its `SyntaxLeaf` opening/closing glyphs are the literal `"` —
  [PrimitiveToSyntax.jl:120-126](../../program/src/projection/primitive/PrimitiveToSyntax.jl#L120-L126).
  **We leave this projection untouched** — other primitive-string sites still
  want quotes.

### What already exists: `PrimitiveStringToText`

[program/src/projection/primitive/PrimitiveToText.jl](../../program/src/projection/primitive/PrimitiveToText.jl)
already defines `PrimitiveStringToText`
([PrimitiveToText.jl:106-183](../../program/src/projection/primitive/PrimitiveToText.jl#L106-L183)):
it projects a `PrimitiveString` **directly** into a single-span `TextText`
(`elements[1].content`) with **no quotes**, and it already carries the full
editing surface we need:

- reference maps `value{s:e} ⇄ elements[1].content{s}`
  ([PrimitiveToText.jl:34-45](../../program/src/projection/primitive/PrimitiveToText.jl#L34-L45)),
- `KeyPress` / `KeyDown` / `ReplaceSelectionOperation` readers operating on
  `s.value` ([PrimitiveToText.jl:127-183](../../program/src/projection/primitive/PrimitiveToText.jl#L127-L183)).

It is exported but **currently unwired** (grep: only the `using`/`export` lines
in `Projectured.jl` and its own unit test reference it), so renaming and
extending it is safe — no production consumers to disturb, and the placeholder
defaults to off.

## Plan

### 1. Rename `PrimitiveStringToText` → `PrimitiveStringToTextText`

The new name follows the `<Source>To<TargetType>` convention already used by
`PrimitiveStringToSyntaxLeaf` (the target document type is `TextText`). Rename
every reference:

- [program/src/projection/primitive/PrimitiveToText.jl](../../program/src/projection/primitive/PrimitiveToText.jl):
  the struct + keyword constructor ([:108-113](../../program/src/projection/primitive/PrimitiveToText.jl#L108-L113)),
  the section comment ([:106](../../program/src/projection/primitive/PrimitiveToText.jl#L106)),
  the `map_reference_forward`/`map_reference_backward`/`projection_print`/three
  `projection_read` method signatures ([:115-183](../../program/src/projection/primitive/PrimitiveToText.jl#L115-L183)),
  the `export` list ([:30](../../program/src/projection/primitive/PrimitiveToText.jl#L30)),
  and the composite's dispatch entry
  `PrimitiveString => PrimitiveStringToTextText(; string_kw...)`
  ([:197](../../program/src/projection/primitive/PrimitiveToText.jl#L197)).
- [program/src/Projectured.jl](../../program/src/Projectured.jl): the `using
  .PrimitiveToTextModule` list ([:373](../../program/src/Projectured.jl#L373))
  and the `export` list ([:658](../../program/src/Projectured.jl#L658)).
- [test/src/projection/PrimitiveToTextTest.jl](../../test/src/projection/PrimitiveToTextTest.jl):
  the import ([:2](../../test/src/projection/PrimitiveToTextTest.jl#L2)), the
  section comment, and the ~11 `PrimitiveStringToText()` constructor calls.

(`PrimitiveBoolToText`/`PrimitiveNumberToText` and the `PrimitiveToText`
composite factory keep their names.)

### 2. Add placeholder support to `PrimitiveStringToTextText`

Add two keyword args to the (renamed) struct + constructor (default off, so the
composite's plain behavior is unchanged):

- `placeholder::String` (default `""`) — hint shown when the value is empty.
- `placeholder_color::StyleColor` (default = `color`) and optionally
  `placeholder_font` (default = `font`).

In `projection_print`
([:120-125](../../program/src/projection/primitive/PrimitiveToText.jl#L120-L125)),
make the single span reactive over emptiness: when
`something(s.value, "") == ""` **and** `placeholder != ""`, emit the
`placeholder` text in `placeholder_color`/`placeholder_font`; otherwise the live
value in `color`/`font`. Because the span is already a `TextString(() -> …)`
thunk, the check happens inside the thunk so the hint appears/disappears live.
Leave the selection cell `_value_selection_to_text(s)` and all
`projection_read` methods unchanged — they edit `s.value` directly and are
unaffected by what the span displays.

### 3. Route the assistant input through the text chain

In both assistant projection factories, replace the `PrimitiveDocument` entry's
`Primitive → Syntax → Text` chain with a direct `Primitive → Text` chain,
passing the placeholder via `PrimitiveToText`'s existing `string_kw`
([PrimitiveToText.jl:193-199](../../program/src/projection/primitive/PrimitiveToText.jl#L193-L199)):

```julia
PrimitiveDocument => SequentialProjection(
    RecursiveProjection(PrimitiveToText(string_kw=(
        color=fg,                                # the assistant's dark fg
        placeholder="type message here",
        placeholder_color=color_solarized_gray))),
    text_to_graphics)
```

- assistant-only: [example/src/projection/Assistant.jl:25-28](../../example/src/projection/Assistant.jl#L25-L28)
  — `fg` is already in scope ([Assistant.jl:17](../../example/src/projection/Assistant.jl#L17)).
- full workbench: [example/src/projection/Workbench.jl:24](../../example/src/projection/Workbench.jl#L24)
  — `fg` is in scope ([Workbench.jl:4](../../example/src/projection/Workbench.jl#L4)).

This drops the `SyntaxToText` stage for the `PrimitiveDocument` entry, so the
quotes disappear structurally; the placeholder comes from the extended
projection. `PrimitiveToText` still maps bool/number too, so the entry remains
valid for any primitive.

Scoping note (record as a code comment): the assistant input is the only
`PrimitiveString` rendered through this entry, so the change is surgical — only
the input gets the prose styling and placeholder. If a future feature renders
another editable `PrimitiveString` here, give it its own discriminator rather
than letting it inherit the prose styling.

Pick the muted color from [program/src/document/Color.jl](../../program/src/document/Color.jl):
`color_solarized_gray` (128,128,128) matches the existing placeholder
convention; `color_gray159`/`color_gray175` is a paler option if it reads too
dark on the assistant's cream background. Tune during verification.

### 4. Verify

Risks specific to showing placeholder text while the editable value is empty:

1. **Cursor still shows at column 0.** Selection maps to
   `elements[1].content{0}`; with no quotes the caret should sit at x=0 in front
   of the hint.
2. **Typing replaces the hint.** First `KeyPress` makes `value` non-empty, so
   the span thunk stops returning the placeholder. Confirm the hint disappears.
3. **Click/selection mapping (main thing to watch).** A click maps an
   x-coordinate to a `content` index via the rendered span width. With a hint
   shown but a 0-length value, the backward map
   `elements[1].content{s:e} => value{s}` could produce an out-of-range
   `value[k]`. Confirm clicking the empty field still yields a valid `value[0:0]`
   selection.

Run the **narrowest** tests (per CLAUDE.md — do **not** run `test_all`):

- `test_cell()` is not needed; first re-run the renamed projection's own unit
  test: the `PrimitiveToTextTest.jl` testset (confirms the rename compiles and
  the no-placeholder behavior is intact).
- `test_printer(assistant_example)` — output no longer contains literal quotes
  and shows the hint when empty.
- `test_selection(assistant_example)` and `test_typein(assistant_example)` —
  cursor/click/selection and character insertion work on empty and non-empty
  field.
- `test_reader(assistant_example)` for the edit round-trip.
- Visually: `write_image_example(assistant_example)` / `run_example(assistant_example)`
  to eyeball the pale hint and absence of quotes.
- Smoke-check the full workbench render to confirm no other field regressed (the
  input is the only `PrimitiveString` through this entry).

## Out of scope / follow-ups

- A dedicated prose-input document type (only needed if another editable
  `PrimitiveString` later shares this dispatch entry).
- Multi-line placeholder or per-state styling beyond a single pale hint line.
