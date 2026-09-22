# The public functions name their arguments

**Status (2026-09-22): PENDING.** The rules landed in
[code-quality-rules.md](../../documentation/rule/code-quality-rules.md) §4, and
`tool/survey-arguments.jl` measures them. No signature changed yet.

**Goal:** every public function of `source/` and `example/` takes at most three
positional arguments, or carries a `# @positional:` marker that says why it does
not. A private helper is deferred.

## 1. Decisions

The owner decided on 2026-09-22:

- **The public functions come first.** A private helper costs one reader one
  file; a public function costs every call site and every later caller.
- **An exception is allowed, and it is written down** at the definition, as
  `# @positional: <reason>`. A signature over the line with no marker and no
  protocol is a defect.

## 2. What the survey found

`julia tool/survey-arguments.jl` over `source/` and `example/`, 508 files and
7158 definitions:

| Positional arguments | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | ≥8 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Definitions | 824 | 2526 | 1681 | 1292 | 603 | 107 | 59 | 31 | 35 |

835 definitions are over the line. 341 of them are methods of a protocol, which
the tool knows by name. **137 public functions and 357 private helpers answer for
the rest.** 665 definitions already take a keyword argument, so the style exists
in the code; it is not applied everywhere.

Where the 137 sit: kernel 30, graph 27, sequencechart 16, pdf 12, graphics 10,
plot 10, layout 7, syntax 6, pane 5, and five more slices with one or two each.

## 3. The waves

### Wave 1: the signatures a caller can get wrong

A `Bool` in the call, or two arguments of one type that a caller can swap. These
are the ones where an order is a defect waiting, and each has few call sites.

| Function | Positional | Calls | File |
| --- | --- | --- | --- |
| `clip_child_to_slot` | 10 | 5 | source/layout/LayoutToGraphics.jl:108 |
| `find_nearest_sample` | 8 | 3 | source/plot/PlotGeometry.jl:351 |
| `allocate_axis` | 7 | 16 | source/layout/LayoutDocument.jl:561 |
| `get_extent_transform` | 7 | 4 | source/graph/GraphLayoutEngine.jl:257 |
| `fit_into_extent!` | 7 | 3 | source/graph/GraphLayoutEngine.jl:291 |
| `fold_scatter` | 7 | 4 | source/plot/PlotGeometry.jl:396 |
| `get_band_intervals` | 7 | 8 | source/sequencechart/SequenceChartGeometry.jl:625 |
| `record_fault!` | 6 | 31 | source/kernel/fault/FaultStore.jl:115 |
| `GestureBinding` | 6 | 49 | source/kernel/binding/GestureBinding.jl:18 |
| `make_pane_drop_split_operation` | 6 | 4 | source/pane/PaneSurgery.jl:684 |
| `decimate_minmax` | 6 | 6 | source/plot/PlotGeometry.jl:252 |
| `make_pane_split_operation` | 5 | 18 | source/pane/PaneSurgery.jl:530 |
| `make_pane_move_tab_operation` | 5 | 8 | source/pane/PaneSurgery.jl:587 |
| `fire_gesture_bindings` | 5 | 8 | source/kernel/binding/GestureBinding.jl:82 |
| `make_fault_record` | 5 | 7 | source/kernel/fault/FaultRecord.jl:104 |
| `run_fault_barrier` | 5 | 4 | source/kernel/fault/FaultBarrier.jl:4 |
| `print_template_rule` | 5 | 2 | source/kernel/projection/ProjectionTemplate.jl:217 |
| `compute_anchored_positions` | 5 | 9 | source/layout/LayoutDocument.jl:734 |
| `compute_histogram_values` | 5 | 7 | source/plot/PlotGeometry.jl:690 |
| `decimate_events` | 5 | 8 | source/sequencechart/SequenceChartGeometry.jl:509 |
| `get_visible_arrows` | 5 | 6 | source/sequencechart/SequenceChartGeometry.jl:233 |
| `sync_element_limit` | 4 | 10 | source/reflection/BoundedSync.jl:96 |
| `compute_legend_layout` | 4 | 3 | source/plot/PlotGeometry.jl:598 |
| `report_fault!` | 4 | 9 | source/kernel/fault/FaultCascade.jl:17 |
| `fire_named_gesture_binding` | 4 | 10 | source/kernel/binding/GestureBinding.jl:121 |
| `read_template_intent` | 4 | 2 | source/kernel/projection/ProjectionTemplate.jl:1307 |

The call counts are the matches of `<name>(` in `source/`, `example/` and
`test/`, so each one counts the definition and the docstring too. About 240
call sites in all. The fault family (`record_fault!`,
`make_fault_record`, `run_fault_barrier`, `report_fault!`) changes together, and
so does the gesture-binding family.

### Wave 2: the four-argument public functions that are not a tuple

`layout_min`, `layout_max`, `layout_preferred`, `call_tool`, `make_hinted_text`,
`insert_elements`, `insert_events`, `set_process_position!`, `Resource`,
`add_cell_struct_field!`, `SpliceBuffer`, `write_stream!`, `flow_ticks`,
`record_video`, `sync_document!`, `move_to_field`,
`make_pane_title_caret_operation`, `make_pane_retarget_title_operation`,
`layout_graph`, `play_live!`, `soft_equal!`, `shift_child_image`,
`make_style_color`, `Editor`. About 25 functions, most with under 20 call sites.

`Editor(backend, document, projection, devices; …)` may stay as it is with a
marker: the four are what an editor is made of, and the keyword arguments are
already there for the rest. The wave decides each one.

### Wave 3: the constructors and the wide tuples

`GraphicsCanvas` (191 calls), `GraphicsRect` (116), `GraphicsText` (64),
`GraphicsLine` (37), `GraphicsViewport` (18), `GraphicsCircle` (25),
`SyntaxLeaf` (566), `SyntaxNode` (415), `MousePress` (216), `Inset` (75),
`PrinterContext` (263), `make_child_context` (145), `WidgetTable` (35).

Most of these are conventional tuples, so the work is to **write the marker**,
not to change the signature. Two are not: `GraphicsCanvas` ends in a `Bool`
(`overlapping`), and `WidgetTable` takes three `Vector`s in a row.

**A constructor with hundreds of call sites gets the keyword form beside the
positional one first.** The call sites move slice by slice, and the positional
form goes when the last one is gone. Nothing else keeps the tree green while the
work runs.

### Wave 4: the private helpers, deferred

357 of them. Two groups stand out, and neither wants keyword arguments:

- **The painters of the backends** (`source/sdl/`, `source/pdf/`): one family of
  one shape, called from one dispatch table. They take the marker as a family.
- **The widest helpers**: `_stroke_rrect!` 14, `_fill_rrect!` 13, `_wt_geometry`
  12, `_place_legend` 11, `_walk_document!` 11, `_paint_polyline_points!` 11.
  Each holds a type that is missing — a geometry, a style, a pass. They are a
  refactor of their own, and a later plan.

## 4. The guard

`tool/survey-arguments.jl` reports today; a guard must fail a build. The guard
lands at the end of wave 3, when the public list is empty, and it fails on a
public definition over the line with no marker. Before that it would fail on
every one of the 137.

**A ledger is the alternative**, and it is what lets the guard land now: a file
of the names that are allowed for today, and the guard fails on any name that is
not in it. The list only shrinks. The owner decides which of the two.

## 5. How one change is made

1. Change the signature. The name does not change, so `workspace/bin/julia-rename.jl` has no part in this.
2. Update every call site: `grep -rn "<name>(" source example test`.
3. Run the narrowest test of the slice, then the suite of its package. See [testing-guide.md](../../documentation/guide/testing-guide.md).
4. One commit for one function, or for one family that changes together.
5. Re-run `julia tool/survey-arguments.jl` and watch the public count fall.

## 6. What is not in this plan

- The test files. They hold their own helpers, and a test reads its own call
  sites.
- The generated code: `@document`, `@cell_struct` and the other macros write the
  positional constructor of every document. That is machine-written, and no rule
  of style applies to it.
