# Reference Inspector display improvements

Improve the hover click-reference inspector's panel (and, for free, the
selection tooltip — both render through the same two projections).

Screenshot feedback: the `compact` / `human-readable` labels look like body
text; the reference shows no type checkpoints; the human-readable lines read as
disconnected `the X of the Type` rows with verbose fully-qualified type names.

## Changes

### 1. Header-styled section labels — `ReferenceInspectorToText`
[package/domain/src/projection/primitive/ReferenceInspectorToText.jl](../../package/domain/src/projection/primitive/ReferenceInspectorToText.jl)

- Add `header_font` (default `font_liberation_sans_bold_30`) and `header_color`
  (default `color_solarized_blue`) fields. Render "Compact" / "Human-readable"
  as larger, bold, colored headers (a different font family + size + color from
  the monospace body). The header's trailing `TextNewline` uses `header_font`
  so the line gets the taller header height.

### 2. Reference carries `TypeReference` checkpoints — `ReferenceInspectorToText`

- Before rendering, annotate the reference against the inspector's `target`:
  `canonical = annotate_reference_types(target, reference)` (idempotent; skip
  when `target === nothing` or the reference is empty/nothing). Render **both**
  the compact and human-readable forms from `canonical`.
- The compact form then shows `::Type` tokens (the user's "reference should
  contain TypeReference steps"). The human-readable form uses the checkpoints as
  its type source (see #3) and the document is no longer required for it.

### 3. Connected human-readable narrative — `ReferenceToHumanReadableText`
[package/domain/src/projection/primitive/ReferenceToText.jl](../../package/domain/src/projection/primitive/ReferenceToText.jl)

Target reading (reverse order, innermost first):

```
the 11th position of a String which is
the name of a NedParam which is
the 4th element of a CellVector which is
the params of a NedSimpleModule which is
the 2nd element of a CellVector which is
the children of a NedFile
```

- `_walk_long!`: **skip `TypeReference` steps** for line generation (no more
  "the elements of type X" rows), but thread the checkpoint's type forward as
  the `parent_type` of the next navigation step. Falls back to
  `evaluate_reference(document, prefix)` when no checkpoint is present (plain
  refs still work).
- Type tail: `of the {FQN}` → `of a/an {ShortType}` (article by leading vowel;
  short type via `nameof`).
- Append a gray italic ` which is` connector to every line **except the last**
  (the outermost) during final assembly.

### 4. Short type names — `ReferenceToText` (compact)

- `_emit_step_short!(::TypeReference)` renders `nameof(step.type)` instead of the
  fully-qualified `string(step.type)`. Shared `_short_type` helper in the module
  (both projections live in `ReferenceToTextModule`).

### 5. Bigger follower window — `HoverProbeProjection`
[package/domain/src/projection/higherorder/HoverProbe.jl](../../package/domain/src/projection/higherorder/HoverProbe.jl)

- Bump default `size` from `(820, 240)` to `(1000, 400)` to fit the headers, the
  (now longer, checkpoint-bearing) compact line, and the `which is` narrative.
  The compact line still word-wraps via the existing `WordWrapping` step.

## Risk / scope

- `ReferenceToText` / `ReferenceToHumanReadableText` are shared (also the
  selection tooltip). No test asserts on their phrasing or type-name format, so
  the prose/type changes are low-risk; the checkpoint-skipping actually fixes the
  pre-existing tooltip wart where canonical selections emitted junk
  "elements of type X" lines.
- `annotate_reference_types` is idempotent and guards every descent with
  try/catch + `hasproperty`, so a stale/cross-domain/projection-ref would-be
  path degrades gracefully.

## Tests

- Extend `HoverProbeTest`: assert the inspector text contains a `::` type token
  (checkpoints reached the compact form) and a `which is` connector
  (narrative), still contains both header words.
- Re-run `test_reference_inspector_text`, `test_hover_probe`,
  `test_hover_probe_pipeline`, plus `test_tooltip` (shares the projections).
