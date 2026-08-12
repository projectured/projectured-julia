# Hoist editable text-projection config into documents

> **Status (2026-08-12): NOT STARTED.** `ProjectionConfiguringProjection` still
> exists and is not retired (`package/widget/main/ProjectionConfiguring.jl`).
> No `HighlightedContent` / `FilteredContent` document or doc-driven composer
> projection exists anywhere under `package/`. The `@test_broken` symptom this
> plan opens with is still present, same root cause, now at
> `package/substrate/test/projection/ProjectionConfiguringTest.jl:135`. Paths
> below are corrected for the current per-domain package layout (the file no
> longer needs the generic "each domain is its own package" layout note, since
> every path is now translated).

> **Decision (2026-08-12): this plan proceeds.** The owner chose to retire
> `ProjectionConfiguringProjection`. An editable projection parameter lives on a
> document field, not on a projection struct, so selection, undo, serialization
> and versioning apply to it. This plan owns the retirement, and Step 8 stands.
>
> **Rejected.** Keep the projection and fix the caret another way: it leaves the
> configuration outside the document, so the four uniformity gains stay out of
> reach. Keep both mechanisms side by side: two ways to do one thing. Defer the
> call: four plans stay blocked.

Retire `ProjectionConfiguringProjection` (pcp). Its editable parameters
(`TextHighlighting.pattern`, `TextFiltering.pattern` / `invert` etc.) live on
projection structs, which are not `@document`s and therefore have no
`selection::Reference` — so the control widgets rendered from them have no
durable focus/caret, which is exactly why `pcp` swallows control-slot
`ReplaceSelectionOp`s (`ProjectionConfiguring.jl:117-121`
[package/widget/main/ProjectionConfiguring.jl], "the control caret
is derived"). That in turn is why the widget layer's selection-authoritative
KeyPress routing can never reach the control bar (`WidgetToGraphics.jl:2634`
[package/widget/main/WidgetToGraphics.jl], `_selected_split_slot` returns 0
when no selection is set).

The failing subtest currently `@test_broken`ed at
`ProjectionConfiguringTest.jl:135`
(`package/substrate/test/projection/ProjectionConfiguringTest.jl`; was `:106`
before the per-domain package split moved and renumbered the file; original
commit `f16ce8b`) is the visible symptom.

## Design

Editable projection parameters move onto real `@document` wrapper nodes that
live in `editor.document`. Selection, undo/redo, serialization, versioning,
and widget focus all become uniform because "editable parameter" and
"document field" become the same thing.

```
Before                              After
─────────────────────────────────   ────────────────────────────────────
editor.document                     editor.document
  = TextBlock("alpha dolor")           = HighlightedContent(
                                          pattern = "dolor",
                                          case_insensitive = false,
                                          color = color_yellow,
                                          content = TextBlock("alpha dolor"),
                                          selection = nothing)
editor.projection
  = ChainingProjection(              editor.projection
      ProjectionConfiguring-           = ChainingProjection(
        Projection(                        HighlightedContentComposer(),
          inner=TextHighlighting(          renderer)
                  "dolor")),
      renderer)
```

`HighlightedContent` is a normal `@document`, so:

- `HighlightedContent.selection` is a real `Reference` cell. Focusing the
  pattern textbox is `doc.selection = @reference pattern{k}`. It survives
  across prints because the document does.
- `WidgetToGraphics`'s selection-authoritative rule is preserved unchanged.
  No autofocus special case.
- `pcp` Case 3 is unnecessary — control-slot `ReplaceSelectionOp`s become
  normal document-scoped selection ops that the standard reader handles.
- Undo/redo, serialization, `@gestures`, gesture-help, tests: all uniform.

### Wrappers stay chained; do not flatten

If we want both highlighting and filtering, the wrapper nesting stays deep:

```julia
HighlightedContent(
    pattern = ...,
    content = FilteredContent(
        pattern = ...,
        invert = ...,
        content = TextBlock(...)))
```

**Do not** merge these into a single flat `TextView` document with combined
config fields. Each layer has its own semantic (a highlight pattern and a
filter pattern are distinct concepts; the user may want to focus into
either), each layer has its own `.selection`, and reference paths stay
locally interpretable at each level. The nesting is exactly the composition
the projection chain currently expresses — just moved from projection space
into document space, where it belongs.

## Migration path

**Path 1 (recommended) — parallel.** Keep `TextHighlighting` /
`TextFiltering` as fixed-config projections for their many read-only
call-sites. Add wrapper `@document`s and doc-driven projections alongside.

- Extract the shared highlight/filter logic (regex compilation, span
  scanning) into pure functions taking `(pattern, case_insensitive, ...)`.
- Both the existing projection and the new doc-driven projection call these
  primitives. No duplication.

**Path 2 — full migration.** Retire `TextHighlighting` / `TextFiltering`
entirely; everything routes through the doc wrappers. Buys a cleaner
taxonomy at the price of ~40 test call-site rewrites. Not recommended
unless we hit a maintenance reason to unify.

## Scope inventory

**Only 2 real callers of `pcp`** (paths current as of 2026-08-12; the domain
examples moved to their own packages since this plan was written):

- `package/workbench/example/projection/Wrapper.jl:117` — `make_text_configuring_projection` factory.
- `package/projectured/example/Gallery.jl:253,255` — the gallery entries calling `make_text_configuring_projection(TextHighlighting("dolor"))` and `make_text_configuring_projection(TextFiltering("dolor"))`.

Definitions / re-exports (mechanical to update):

- `package/widget/main/ProjectionConfiguring.jl` — the module.
- Its `include` line in `package/widget/main/ProjecturedWidget.jl` and its
  re-export in `package/widget/main/ProjecturedWidget.jl`'s dependents (the
  module now lives in its own `widget` package, not a shared `visual`/`domain`
  package, so there is no separate cross-package re-export line left to edit).
- Doc-comment mentions in `package/widget/main/{ObjectToWidget,Widget}.jl`.

Tests:

- `package/substrate/test/projection/ProjectionConfiguringTest.jl` — 5 testsets,
  ~140 lines, one currently `@test_broken` at line 135.
- Export list: `package/substrate/test/ProjecturedSubstrateTest.jl` (the
  successor of `ProjecturedVisualTest.jl`).

Configurable text projections (in scope):

| projection | fields |
|---|---|
| `TextHighlighting` | `pattern::Cell`, `case_insensitive::Cell`, `color::StyleColor` |
| `TextFiltering`   | `pattern::Cell`, `case_insensitive::Cell`, `invert::Cell` |

Fields re-verified 2026-08-12 at `package/text/main/TextHighlighting.jl:49-53`
and `package/text/main/TextFiltering.jl:50-54` — unchanged from the plan.

`WordWrapping` (`max_width`, `measure`) and `TextFirstLine` (empty) have no
user-editable state; out of scope.

Direct `TextHighlighting(...)` / `TextFiltering(...)` call-sites (all
untouched under Path 1):

- `package/substrate/example/projection/{TextHighlighting,TextFiltering}.jl` — the
  gallery entries for the projections themselves (fixed pattern, no control).
- `package/substrate/test/projection/TextHighlightingTest.jl` — 7 `print_document(TextHighlighting(...), ...)` cases.
- `package/substrate/test/projection/TextFilteringTest.jl` — 8 similar cases.
- `package/substrate/test/projection/ObjectToWidgetTest.jl` — `TextHighlighting` used as a fixture for `ObjectToWidget`.

## Steps

1. **Extract shared primitives.** Refactor the pattern-scanning core out of
   `TextHighlighting` / `TextFiltering` into pure functions in
   `package/text/main/` (e.g. `_scan_highlights(text, pattern, case_insensitive)`,
   `_filter_lines(text, pattern, case_insensitive, invert)`). Both the
   existing projection and the new doc-driven projection call these.
2. **Introduce `HighlightedContent`.** New `@document` at
   `package/text/main/HighlightedContent.jl`, alongside a
   `HighlightedContentToText` projection that reads its config from
   `iomap.input.{pattern,case_insensitive,color}` and produces the same
   highlighted `TextBlock` output the existing `TextHighlighting` projection
   produces.
3. **Introduce `FilteredContent`.** Symmetric: `package/text/main/
   FilteredContent.jl` + `FilteredContentToText`.
4. **Doc-composer projection.** Small projection that takes a wrapper doc
   with a `content` sub-slice and any number of scalar/config sub-slices,
   projects the config sub-slice via `ObjectToWidget` (the control bar), the
   content sub-slice via a recursion-provided per-content projection, and
   stacks them in a `WidgetSplitPane`. This is `pcp` with the config-state
   hoisted out into the wrapper doc — much smaller, no Case 3, no
   `control_widget` field on the iomap. Consider whether an existing
   composer (e.g. via `WorkbenchToWidget`'s pane machinery) already covers
   this before writing a new one.
5. **Retarget `make_text_configuring_projection`.** Now takes
   `content_doc` (a `TextBlock`), returns `(wrapper_doc, projection)` where
   `wrapper_doc = HighlightedContent(pattern="dolor", content=content_doc)`
   and `projection` is the composer + renderer chain.
6. **Gallery.** Update `package/projectured/example/Gallery.jl:253,255` — the two
   `text_highlighting=true` / `text_filtering=true` branches — to also swap
   `document` (currently the plain `TextBlock`) with the wrapper doc.
7. **Rewrite `ProjectionConfiguringTest.jl`.** The 5 testsets test pcp
   semantics; they get rewritten around the composer + wrapper-doc model.
   The `@test_broken` typing subtest becomes a normal `@test` and passes.
8. **Retire `ProjectionConfiguringProjection`.** Delete the module + include
   line + re-exports. Update the two doc-comment mentions in `ObjectToWidget.jl`
   / `Widget.jl`. Move the plan to `plan/done/`.

## Success criteria

- `test_projection_configuring()` — the same 5 testsets, rewritten around
  the wrapper doc — passes with all `@test`s green. No `@test_broken`.
- `test_substrate()` full (the successor of `test_visual()` after the package
  split): no new failures relative to `f16ce8b`.
- Each domain's own `test_<domain>()` (the successor of `test_domain()`): no
  new failures (the two gallery branches now build different documents;
  regressions here would surface as broken example goldens, worth eyeballing).
- Interactive: `run_example(...; text_highlighting=true)` — typing into the
  pattern textbox re-highlights live; Tab / Escape behave sensibly;
  focus survives across prints.

## Out of scope

- Migrating any other pcp-style patterns to the doc-config model — no
  others exist today (grep confirms).
- Any `WordWrapping` / `TextFirstLine` treatment — no user-editable state.
- Path 2 (retiring `TextHighlighting`/`TextFiltering`).
- Autofocus semantics in the widget layer (the alternative Option A from
  the design discussion); the whole point of this plan is that we don't
  need it.
- Cross-editor / shared config (theme, font-size, per-user preferences) —
  those are legitimately editor-owned, not document-owned, and would need
  a different plan if we ever want them interactive.

## References

- Failing subtest currently `@test_broken`: `package/substrate/test/projection/ProjectionConfiguringTest.jl:135` (was `:106` before the package split; commit `f16ce8b`).
- Widget layer selection-authoritative routing: `package/widget/main/WidgetToGraphics.jl:2634` (`WidgetSplitPane`, `_selected_split_slot`) and `:1868` (`WidgetComposite`, `_selected_composite_slot`) — plus `package/widget/doc/widget.md`.
- pcp's control-slot consumption: `package/widget/main/ProjectionConfiguring.jl:117-121`.
