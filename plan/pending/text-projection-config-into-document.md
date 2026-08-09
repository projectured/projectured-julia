# Hoist editable text-projection config into documents

> **Layout note.** This plan was written when every domain lived in one
> `ProjecturedDomain` package. Each domain is its own package now — see
> [documentation/domains.md](../../documentation/domains.md). A path or a
> module name below that still says `package/domain/` or `ProjecturedDomain`
> needs translating when the plan is picked up.

Retire `ProjectionConfiguringProjection` (pcp). Its editable parameters
(`TextHighlighting.pattern`, `TextFiltering.pattern` / `invert` etc.) live on
projection structs, which are not `@document`s and therefore have no
`selection::Reference` — so the control widgets rendered from them have no
durable focus/caret, which is exactly why `pcp` swallows control-slot
`ReplaceSelectionOp`s (`ProjectionConfiguring.jl:117-121`, "the control caret
is derived"). That in turn is why the widget layer's selection-authoritative
KeyPress routing can never reach the control bar (`WidgetToGraphics.jl:
2353-2363`, `_selected_split_slot` returns 0 when no selection is set).

The failing subtest currently `@test_broken`ed at
`ProjectionConfiguringTest.jl:106` (see commit `f16ce8b`) is the visible
symptom.

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

**Only 2 real callers of `pcp`** (both in domain examples):

- `domain/example/src/projection/Wrapper.jl:83-98` — `make_text_configuring_projection` factory.
- `domain/example/src/Gallery.jl:149,151` — `text_highlighting=true` and `text_filtering=true` flags on the gallery, using `TextHighlighting("dolor")` and `TextFiltering("dolor")`.

Definitions / re-exports (mechanical to update):

- `visual/src/widget/ProjectionConfiguring.jl` — the module.
- `visual/src/ProjecturedVisual.jl:190` — include line.
- `domain/src/ProjecturedDomain.jl:125` — module re-export.
- Doc-comment mentions in `visual/src/widget/{ObjectToWidget,Widget}.jl`.

Tests:

- `visual/test/src/projection/ProjectionConfiguringTest.jl` — 5 testsets,
  ~130 lines, one currently `@test_broken` at line 106.
- `visual/test/src/ProjecturedVisualTest.jl` — export list.

Configurable text projections (in scope):

| projection | fields |
|---|---|
| `TextHighlighting` | `pattern::Cell`, `case_insensitive::Cell`, `color::StyleColor` |
| `TextFiltering`   | `pattern::Cell`, `case_insensitive::Cell`, `invert::Cell` |

`WordWrapping` (`max_width`, `measure`) and `TextFirstLine` (empty) have no
user-editable state; out of scope.

Direct `TextHighlighting(...)` / `TextFiltering(...)` call-sites (all
untouched under Path 1):

- `visual/example/src/projection/{TextHighlighting,TextFiltering}.jl` — the
  gallery entries for the projections themselves (fixed pattern, no control).
- `visual/test/src/projection/TextHighlightingTest.jl` — 7 `print_document(TextHighlighting(...), ...)` cases.
- `visual/test/src/projection/TextFilteringTest.jl` — 8 similar cases.
- `visual/test/src/projection/ObjectToWidgetTest.jl:4` — `TextHighlighting` used as a fixture for `ObjectToWidget`.

## Steps

1. **Extract shared primitives.** Refactor the pattern-scanning core out of
   `TextHighlighting` / `TextFiltering` into pure functions in
   `visual/src/text/` (e.g. `_scan_highlights(text, pattern, case_insensitive)`,
   `_filter_lines(text, pattern, case_insensitive, invert)`). Both the
   existing projection and the new doc-driven projection call these.
2. **Introduce `HighlightedContent`.** New `@document` at
   `visual/src/text/HighlightedContent.jl`, alongside a
   `HighlightedContentToText` projection that reads its config from
   `iomap.input.{pattern,case_insensitive,color}` and produces the same
   highlighted `TextBlock` output the existing `TextHighlighting` projection
   produces.
3. **Introduce `FilteredContent`.** Symmetric: `visual/src/text/
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
6. **Gallery.** Update `Gallery.jl:149,151` — the two `text_highlighting=true` /
   `text_filtering=true` branches — to also swap `document` (currently the
   plain `TextBlock`) with the wrapper doc.
7. **Rewrite `ProjectionConfiguringTest.jl`.** The 5 testsets test pcp
   semantics; they get rewritten around the composer + wrapper-doc model.
   The `@test_broken` typing subtest becomes a normal `@test` and passes.
8. **Retire `ProjectionConfiguringProjection`.** Delete the module + include
   line + re-exports. Update the two doc-comment mentions in `ObjectToWidget.jl`
   / `Widget.jl`. Move the plan to `plan/done/`.

## Success criteria

- `test_projection_configuring()` — the same 5 testsets, rewritten around
  the wrapper doc — passes with all `@test`s green. No `@test_broken`.
- `test_visual()` full: no new failures relative to `f16ce8b`.
- `test_domain()`: no new failures (the two gallery branches now build
  different documents; regressions here would surface as broken example
  goldens, worth eyeballing).
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

- Failing subtest currently `@test_broken`: `package/visual/test/src/projection/ProjectionConfiguringTest.jl:106` (commit `f16ce8b`).
- Widget layer selection-authoritative routing: `package/visual/src/widget/WidgetToGraphics.jl:2353-2363` (`WidgetSplitPane`) and `:1648-1652` (`WidgetComposite`) — plus `documentation/document/widget.md`.
- pcp's control-slot consumption: `package/visual/src/widget/ProjectionConfiguring.jl:117-121`.
