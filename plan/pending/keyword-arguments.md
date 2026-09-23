# The public functions name their arguments

**Status (2026-09-22): WAVE 1 DONE.** The rules landed in
[code-quality-rules.md](../../documentation/rule/code-quality-rules.md) §4,
`tool/survey-arguments.jl` measures them, and `test/suite/arguments.jl` guards
them. Wave 1 changed 26 public functions in a worktree and landed on `main`.
Waves 2 to 4 are open.

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

### Wave 1: the signatures a caller can get wrong — DONE

**Done, 2026-09-22.** All 26 changed, in four commits: the fault family, the
gesture bindings, the pane makers with the layout and the reflection, and the
geometry of the plot, the sequence chart and the graph. `print_template_rule`
and `read_template_intent` took a `# @positional:` marker instead of a change:
they are the printer and the reader of the projection protocol, which the
template macro emits with that shape.

What the measure says, before and after: definitions over the line 835 → 811,
of them public 137 → 107; definitions that take a keyword argument 665 → 736.

The suites that cover the changed slices keep their known results:
`test_fault()` 73 of 73, `test_kernel()` 3 failures and 3 errors of Rule C and
the reference schema, `test_substrate()` 3 failures and 2 errors of the
split-pane drag, `test_conversation()` its one import check, and
`test_shell()`, `test_application()`, `test_plot_geometry()`,
`test_sequencechart()`, `test_graph()`, `test_chart()`, `test_naming()`,
`test_documentation()` and `test_tree()` all pass.


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

### Wave 2: the four-argument public functions that are not a tuple — DONE

**Done, 2026-09-23.**

These took the keyword form:

| Function | Was | Is | File |
| --- | --- | --- | --- |
| `layout_min` / `layout_max` / `layout_preferred` | `(doc, axis, intrinsic, default)` | `(doc, axis, intrinsic; default)` | source/layout/LayoutDocument.jl |
| `layout_weight` | `(doc, axis, default)` | `(doc, axis; default)` | source/layout/LayoutDocument.jl |
| `call_tool` | `(set, name, args, target)` | `(set, name; args, target)` | source/kernel/tool/ToolSet.jl |
| `Resource` | `(uri, name, description, provider)` | `(uri, name; description, provider)` | source/kernel/tool/Tool.jl |
| `make_hinted_text` | `(content, empty, placeholder, style)` | `(content; empty_thunk, placeholder, style)` | source/text/TextDocument.jl |
| `insert_elements` | `(path, index, items, selection)` | `(path, index, items; selection)` | source/kernel/operation/Operations.jl |
| `insert_events` | `(chart, at, times, axes; …)` | `(chart, at; times, axes, …)` | source/sequencechart/SequenceChartDocument.jl |
| `set_process_position!` | `(session, model, node, previous)` | `(session, model; node, previous)` | source/process/ProcessDebugSession.jl |
| `add_cell_struct_field!` | `(plan, name, type, default)` | `(plan, name; type, default)` | source/kernel/struct/CellStructPlan.jl |
| `write_stream!` | `(w, num, dict, data)` | `(w, num; dict, data)` | source/pdf/Pdf.jl |
| `flow_ticks` | `(times, coordinates, scale, mode; …)` | `(times, coordinates; scale, mode, …)` | source/sequencechart/SequenceChartGeometry.jl |
| `fold_bins` / `fold_strips` | `(lefts, rights, values, min_px)` | `(lefts, rights, values; min_px)` | source/plot/PlotGeometry.jl |
| `move_to_field` | `(document, selection, from, to)` | `(document, selection; from, to)` | source/domain/Domain.jl |
| `make_pane_title_caret_operation` | `(tree, group, index, position)` | `(tree, group, index; position)` | source/pane/PaneSurgery.jl |
| `make_pane_retarget_title_operation` | `(tree, group, index, operation)` | `(tree, group, index; operation)` | source/pane/PaneSurgery.jl |
| `play_live!` | `(backend, projection, document, timeline; …)` | `(backend, timeline; projection, document, …)` | source/kernel/playback/Playback.jl |
| `shift_child_image` | `(child, off_x, off_y, cim)` | `(child, cim; off_x, off_y)` | source/layout/LayoutToGraphics.jl |
| `get_band_reference` | `(chart, axis, band, row)` | `(chart; axis, band, row)` | source/sequencechart/SequenceChartDocument.jl |
| `compute_window_place` | `(x, y, w, h, area_w, area_h, pointer)` | `(x, y, w, h; area_width, area_height, pointer)` | source/sdl/Sdl.jl |
| `SpliceBuffer`, `soft_equal!`, `record_video` | four positional | the tail is named | their files |
| `WidgetTable` (document cells) | `(position, column_headers, row_headers, rows, column_count)` | `(position; column_headers, row_headers, rows, column_count)` | source/widget/WidgetDocument.jl |

Two took a `# @positional:` marker instead of a change:

- `Editor(backend, document, projection, devices; …)` — the four are what an
  editor is made of, in the order of the layers.
- `make_style_color(red, green, blue, alpha)` — the four components of a colour,
  in the order every one writes them.

`get_band_reference` was called as `get_band_reference(chart, band...)` with the
tuple that `find_band_hit` answers. A splat can not name a keyword, so
`find_band_hit` now answers a `NamedTuple`, and the call is
`get_band_reference(chart; band...)`.

`layout_weight` was not on the list: it takes three positional arguments, which
the rule allows. It changed with its three siblings, because the four make one
family and a family that reads two ways costs the reader more than the rule
saves.

`layout_graph` and `sync_document!` stay on the ledger for wave 3: both are
wide constructors of a tuple, not a list of options.

### Wave 3: the constructors and the wide tuples — IN PROGRESS

**Measured 2026-09-23, after wave 2.** Seven names were left on the ledger,
thirteen definitions. The first estimate of this section counted every call of
each name; the work is only the calls that are still positional, and that is 25
call sites, not hundreds. Eight of the names this section first listed
(`GraphicsRect`, `GraphicsText`, `GraphicsLine`, `GraphicsCircle`,
`GraphicsViewport`, `MousePress`, `Inset`, `PrinterContext`) left the wave on the
day the guard landed: they are conventional tuples and carry a marker.

| Name | Definitions over the line | Calls to move | What the wave does |
| --- | --- | --- | --- |
| `layout_graph` | 3 | 0 | protocol list |
| `sync_document!` | 1 | 0 | protocol list |
| `compute_window_place` | 1 | 0 | marker |
| `SyntaxLeaf` | 4 legacy forms | 0 | delete |
| `SyntaxNode` | 6 legacy forms | 9, and 1 in omnet-julia | keyword form |
| `GraphicsCanvas` | 2, and a third with a positional `Bool` | 17 | keyword form |
| `WidgetTable`, list form | 1 | 3 tests, and 1 in omnet-julia | one constructor |

Decisions:

- **`layout_graph` and `sync_document!` are protocols.** Each is a bare
  declaration (`function layout_graph end`, `function sync_document! end`) that
  other code implements; omnet-julia adds a fourth `layout_graph` method. They
  join `ARGUMENT_PROTOCOL` beside `copy_document`.
- **`compute_window_place(x, y, width, height; …)` is a conventional tuple**: the
  box, in the order every one writes it.
- **The three-argument `GraphicsCanvas(elements, layout, overlapping)` goes too.**
  The guard does not count it, but the rule says a `Bool` is never positional.
  Six callers. The two-argument `GraphicsCanvas(elements, layout)` keeps the rule
  and stays.
- **A `SyntaxNode` inside `@projection_template` with a raw vector of children
  stays as it is.** The template engine finds those children by looking for a raw
  `Vector`, and the keyword path would turn it into a `CellVector`. Those calls
  go to the generated field constructor, not to the legacy forms.
- **`WidgetTable` gets one keyword constructor for both kinds of rows.** A keyword
  argument takes no part in dispatch, so a second `WidgetTable(position; …)`
  would replace the first. The one constructor branches on the type of `rows`,
  and `row_headers` defaults to none.
- **Not in the wave: 54 calls of the generated `GraphicsCanvas` constructor** that
  pass all eight fields, most of them cells. The rule counts definitions, and the
  macro writes that one. Moving them to the generated keyword constructor needs a
  test first, that it keeps a cell it is given as a live cell.
- **omnet-julia moves with the wave.** Wave 2 broke three of its calls (two
  `WidgetTable`, one `record_video`), and this wave changes two more
  (`NedToSyntax.jl`, `SimulationFilterToWidget.jl`). A branch there carries all
  five.

Steps:

- [x] 1. The protocol list and the marker: `layout_graph`, `sync_document!`,
  `compute_window_place` leave the ledger.
- [x] 2. `SyntaxLeaf`: delete the four legacy forms.
- [x] 3. `SyntaxNode`: move the nine calls, delete the six legacy forms, and
  update the comment diagrams that draw the legacy form.
- [ ] 4. `GraphicsCanvas`: the keyword form takes a `CollectionDocument`; move the
  seventeen calls; delete the three forms.
- [ ] 5. `WidgetTable`: one keyword constructor; move the three tests.
- [ ] 6. The ledger is empty: the guard and §4 of the rule say so.
- [ ] 7. omnet-julia: the five calls, on a branch.

### Wave 4: the private helpers, deferred

357 of them. Two groups stand out, and neither wants keyword arguments:

- **The painters of the backends** (`source/sdl/`, `source/pdf/`): one family of
  one shape, called from one dispatch table. They take the marker as a family.
- **The widest helpers**: `_stroke_rrect!` 14, `_fill_rrect!` 13, `_wt_geometry`
  12, `_place_legend` 11, `_walk_document!` 11, `_paint_polyline_points!` 11.
  Each holds a type that is missing — a geometry, a style, a pass. They are a
  refactor of their own, and a later plan.

## 4. The guard

**Done, 2026-09-22.** The owner chose the ledger, so the guard landed before the
waves rather than after them: the count can not grow while the work runs.

`test/suite/arguments.jl` holds the parser, the protocol list and the ledger of
the 119 public names that were over the line on the day the rule landed.
`test_arguments()` in `ProjecturedSuite.jl` runs it, and `test_all()` runs that.
It fails on two things: a public definition over the line that neither the
ledger nor a `# @positional:` marker excuses, and a ledger name that no
definition needs any more. So the ledger only shrinks.

The guard reads 508 files and loads nothing, so it runs in about a second, and
it runs on its own as well:

    julia test/suite/arguments.jl
    julia tool/survey-arguments.jl          # the whole picture, private helpers included

The ledger holds 119 names and the survey counts 137 public definitions: a name
with two methods over the line, such as `record_fault!`, stands once.

## 5. How one change is made

1. Change the signature. The name does not change, so `workspace/bin/julia-rename.jl` has no part in this.
2. Update every call site: `grep -rn "<name>(" source example test`.
3. Run the narrowest test of the slice, then the suite of its package. See [testing-guide.md](../../documentation/guide/testing-guide.md).
4. One commit for one function, or for one family that changes together.
5. Take the name out of the ledger of `test/suite/arguments.jl`. The guard
   fails while a name stands there that no definition needs.
6. Re-run `julia tool/survey-arguments.jl` and watch the public count fall.

**A script that rewrites call sites pays for itself**, and wave 1 used one that
reads balanced parentheses and splits at top-level commas. Two traps: it rewrites
a signature line inside a docstring as if it were a call, and it swallows a
comment that stands inside an argument list. Read the diff for `= #` and for a
`->` in a docstring after each run.

## 6. What is not in this plan

- The test files. They hold their own helpers, and a test reads its own call
  sites.
- The generated code: `@document`, `@cell_struct` and the other macros write the
  positional constructor of every document. That is machine-written, and no rule
  of style applies to it.
