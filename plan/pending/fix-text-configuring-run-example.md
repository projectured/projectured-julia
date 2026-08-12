# Fix `text_filtering` / `text_highlighting` in `run_example`

> **Status (2026-08-12): NOT STARTED.** The code is still in the exact "before"
> state this plan describes; no step below is implemented. Two things moved
> since the plan was written: `make_text_configuring_projection` now lives at
> `package/workbench/example/projection/Wrapper.jl:117`, and the `run_example`
> branches that replace the projection now live at
> `package/projectured/example/Gallery.jl:248,254`. `SequentialProjection` no
> longer exists under that name — it was renamed to `ChainingProjection`
> (`package/projection/main/higherorder/Chaining.jl`), same shape and
> semantics. `ProjectionConfiguringProjection`, `TextHighlighting`, and
> `TextFiltering` still exist (now at `package/widget/main/ProjectionConfiguring.jl`,
> `package/text/main/TextHighlighting.jl`, `package/text/main/TextFiltering.jl`),
> so the plan is NOT obsolete — just unimplemented, with paths to update as it
> is picked up.

## Problem

When `run_example` is called with `text_filtering=true` or `text_highlighting=true`,
the example's **entire projection** is replaced by the output of
`make_text_configuring_projection(...)`:

```julia
elseif text_highlighting
    projection = make_text_configuring_projection(TextHighlighting("dolor"))
elseif text_filtering
    projection = make_text_configuring_projection(TextFiltering("dolor"))
end
```

This discards every step in the example's own `SequentialProjection`.  For
instance, `text_example` normally runs `WordWrapping → TextToGraphics`; with
`text_highlighting=true` the `WordWrapping` step is lost and replaced by a
hard-coded `TextToGraphics` inside `make_text_configuring_projection`.

The flags should work with **any** example, not just text examples, and they
should **augment** the existing pipeline rather than replace it.

## Goal

Find the correct insertion point inside the example's `SequentialProjection`
and splice a `TextHighlighting` (resp. `TextFiltering`) step — wrapped in
`ProjectionConfiguringProjection` for the control-bar UI — **into** the
existing pipeline, preserving all other steps.

## Analysis: Where to Insert

`TextHighlighting` and `TextFiltering` are **Text → Text** projections.  They
must sit inside the pipeline at a point where the data is a `TextBlock` — i.e.
**after** any domain-to-text conversion (e.g. `SyntaxToText`) and **before**
the final rendering to graphics (e.g. `TextToGraphics`).

Typical example pipelines and the insertion point (marked `▸`):

| Example | Pipeline | Insert before |
|---------|----------|---------------|
| `text_example` | `WordWrapping → TextToGraphics` | `TextToGraphics` |
| `json_example` | `JsonToSyntax → SyntaxToText → TextToGraphics` | `TextToGraphics` |
| `json_sorted_example` | `Sorting → JsonToSyntax → SyntaxToText → TextToGraphics` | `TextToGraphics` |
| `julia_example` | `JuliaToSyntax → SyntaxToText → LineNumbering → TextToGraphics` | `TextToGraphics` |
| `text_filtering_example` | `TextFiltering → TextToGraphics` | `TextToGraphics` |

The common pattern: **insert immediately before the first `TextToGraphics`
step** (or more generally, the first step that leaves the `TextBlock` domain).

## Design

### Step 1 — Detect insertion point in a `SequentialProjection`

**⏳ OPEN (verified):** No `_find_text_insertion_index` (or any equivalent helper) exists in source — only referenced in this plan file.

Write a helper that inspects a `SequentialProjection`'s `.projections` vector
and returns the **index** of the step where a Text→Text projection should be
spliced in.  The heuristic:

```julia
function _find_text_insertion_index(seq::SequentialProjection)
```

Walk `seq.projections` from left to right.  Return the index of the **first**
step that is a `TextToGraphics` (or is a `RecursiveProjection` wrapping a
`TypeDispatchingProjection` whose entries include `TextToGraphics`).  This is
the boundary where the pipeline leaves the text domain.

If no such step is found, fall back to `length(seq.projections) + 1` (append
at the end — degenerate case, the projection is not a standard pipeline).

If the projection is **not** a `SequentialProjection` at all (e.g. a bare
`TextToGraphics`), wrap it in one first: `SequentialProjection(projection)`.

### Step 2 — Splice the configuring projection

**⏳ OPEN (verified 2026-08-12):** `make_text_configuring_projection` (`package/workbench/example/projection/Wrapper.jl:117-132`) builds a fixed two-step `ChainingProjection(ProjectionConfiguringProjection, renderer)`; no splice into an existing pipeline.

Build the augmented pipeline by inserting a
`ProjectionConfiguringProjection(inner=TextHighlighting(...))` (or
`TextFiltering(...)`) at the detected index.  The result is a new
`SequentialProjection` with all original steps preserved and the text-config
step added at the right position.

However, `ProjectionConfiguringProjection` converts its output to a
`WidgetSplitPane` (control bar + document).  The steps **after** the
insertion point (starting with `TextToGraphics`) now receive a widget tree,
not a `TextBlock`.  This is exactly the situation `make_text_configuring_projection`
already solves — it wraps the tail in a `RecursiveProjection(TypeDispatchingProjection(...))`
that dispatches widgets to `WidgetToGraphics` and `TextBlock` to the remaining
text steps.

So the splice is:

```
original[1..i-1]                         # steps before the text→graphics boundary
ProjectionConfiguringProjection(inner=…) # the control-bar wrapper
renderer                                 # dispatches widget + TextBlock to the tail steps
```

where `renderer` is built from the original steps `original[i..end]` plus the
`WidgetToGraphics` dispatch, exactly as `make_text_configuring_projection`
already does for the hard-coded case.

### Step 3 — Update `make_text_configuring_projection`

**⏳ OPEN (verified 2026-08-12):** Still the single-arg signature `make_text_configuring_projection(inner_text_projection; measure=truetype_measure_text, font=font_ubuntu_monospace_regular_20)` at `package/workbench/example/projection/Wrapper.jl:117`; no `base_projection` parameter.

Refactor `make_text_configuring_projection` (in `example/src/projection/Wrapper.jl`)
to accept an **existing projection** to augment:

```julia
function make_text_configuring_projection(inner_text_projection, base_projection;
                                          measure=..., font=...)
```

When `base_projection` is supplied:
1. Call `_find_text_insertion_index` on `base_projection`.
2. Split the projection vector at that index.
3. Build the renderer `TypeDispatchingProjection` from the tail steps + `WidgetToGraphics`.
4. Return the spliced `SequentialProjection`.

When `base_projection` is omitted (the 1-arg form), keep the current
behaviour as a convenience fallback (backward-compatible).

### Step 4 — Update `run_example`

**⏳ OPEN (verified 2026-08-12):** `package/projectured/example/Gallery.jl:248,254` still call the 1-arg form (`make_text_configuring_projection(TextHighlighting("dolor"))`), replacing the projection.

In `Examples.jl`, change the `text_highlighting` / `text_filtering` branches
from replacing the projection to augmenting it:

```julia
elseif text_highlighting
    projection = make_text_configuring_projection(TextHighlighting("dolor"), projection)
elseif text_filtering
    projection = make_text_configuring_projection(TextFiltering("dolor"), projection)
end
```

This preserves the example's full pipeline and inserts the text-config step at
the correct position.

### Step 5 — Handle non-`SequentialProjection` cases

**⏳ OPEN (verified):** Depends on Steps 1-3; no fallback wrapping logic exists since the splice mechanism is unimplemented.

Some examples may have non-sequential projections (e.g. a bare
`RecursiveProjection`, a `NestingProjection`, or a `TypeDispatchingProjection`
used at the top level).  For these, the insertion heuristic won't find a step;
the fallback is to wrap the entire projection: `SequentialProjection(projection)`
and treat `TextToGraphics` as absent, appending at the end.  This reproduces
the current (replacement) behaviour, so it is no worse.

## Edge Cases

- **Already has `TextHighlighting`/`TextFiltering`**: `text_highlighting_example`
  already has a `TextHighlighting` step.  Inserting another is harmless (two
  highlights stack) but could be confusing.  Consider detecting and skipping
  if the same projection type is already in the pipeline, or accept the
  duplication as intentional (the flag injects a *configurable* version).
- **`caching=true` interaction**: caching wraps the **outermost** projection in
  `GraphicsCaching` after the text-config splice.  This is correct — caching
  is always the outermost wrapper.
- **`scrolling=true` / `workbench=true` / `introspection=true`**: These are in
  `elseif` branches and are mutually exclusive with `text_highlighting` /
  `text_filtering` today.  Consider relaxing this — the splice approach makes
  composition possible — but that is a separate concern.

## Files to Change

- `package/workbench/example/projection/Wrapper.jl` — refactor
  `make_text_configuring_projection`, add `_find_text_insertion_index`
- `package/projectured/example/Gallery.jl` — update the `text_highlighting` /
  `text_filtering` branches in `run_example`

## Testing

- `run_example(text_example; text_highlighting=true)` — should show
  `WordWrapping → TextHighlighting → TextToGraphics` with the control bar
- `run_example(json_example; text_filtering=true)` — should show
  `JsonToSyntax → SyntaxToText → TextFiltering → TextToGraphics` with the
  control bar
- `run_example(text_highlighting_example; text_highlighting=true)` — confirm
  it degrades gracefully (double highlight or detected/skipped)
- `run_example(julia_example; text_highlighting=true)` — should show
  `JuliaToSyntax → SyntaxToText → LineNumbering → TextHighlighting → TextToGraphics`
