# A view names the domain part under a point

> **Status (2026-09-27): pending. Nothing of it is started.** The owner chose on
> 2026-09-27 to do the introduced reference now (option 1 of Q17 in
> [events-gestures-and-the-pointer.md](../done/events-gestures-and-the-pointer.md)) and
> to plan this, option 2, as its own work. Every decision below waits for the
> owner.
>
> The owner kept it separate when the pointer work finished (2026-10-02, "keep it
> separate").

## 1. The purpose

A view prints a domain document as widgets: a log as a list of lines, a module
tree as a tree, a result as a table. A point on the view must name the part of
the domain document that the view shows there, for example the log line, the
module or the result row, and not only the widget that draws it.

The mouse target tracker of the events plan keeps "the most specific document
part pointed at by the mouse" (the owner's words), and sends an enter and a
leave by the difference of two paths. An agent names a part in the vocabulary
of the domain too. So the most useful answer to "what is under the point" is a
domain part. In the owner's words about D11: "In domain projections that is
usually trivial".

## 2. The state after option 1

- A view that maps no part of its input maps a widget part back by an introduced
  reference: `proj(view, ^(widget path))`, the default of
  `map_reference_backward`.
- Forward, it maps only such a reference, with `find_introduced_path`, so no
  caret goes into the view.
- 41 views in omnet-julia and 5 in projectured-julia work so: the file chooser,
  the cell table, the object form, the query result, and the control of a
  configuring projection.
- 4 views in omnet-julia still map nothing:
  - `HanoiToGraphics`, `ModuleAppearanceToGraphicsCanvas` and
    `TimelineStripToGraphics` print graphics directly, so a point in them has no
    widget part to name. Today the whole view is the part.
  - `SimulationResultFrameToWidgetTable` sends a selection that is not a row
    pick to the kernel default reader. With an introduced reference, that
    selection would put a caret into the view.

## 3. The model

These are proposals. The owner decides them in §5.

- **Backward.** A widget part that shows a domain part maps to the reference of
  that domain part, in the input of the view. A widget part that shows no
  domain part maps to the introduced reference, as now. Examples of the second
  kind: a title, a button, a divider, a readout of a computed value.
- **Forward.** A domain reference maps to the path of the widget that shows it,
  and an introduced reference maps to its path, as now. A route to a domain
  part needs the forward mapping, because the chain carries a route forward
  stage by stage.
- **How a view knows the pairs.** The printer builds each widget from a domain
  part, so the printer knows the pair when it makes it. The preferred way is a
  child IO map for each part that the view prints (the view delegates to it).
  The other way is a search by identity, from a widget to the domain object
  that its content holds, as `_find_child_steps` finds a child widget.
- **The reader.** A view whose reader sends an operation back unchanged does not
  use the backward mapping, so a domain mapping changes nothing in its clicks.
  A view whose reader falls back to the kernel default reader carries a
  selection back through the mapping, so for it a domain mapping puts a
  selection on the domain part. Each such view needs a decision.
- **A view that prints graphics directly.** It maps a point with the hit test of
  its reader of a click, as the charts do (step 4d of the events plan): the
  module picture to the submodule under the point, the Hanoi board to a disk or
  a peg, the timeline strip to an event.

## 4. The inventory

The domain part of each widget is not known yet: step 1 finds it. "Reader"
says what the reader of the view does with an operation that comes back from
the widgets: "unchanged" sends it back as it is, "own" is a reader of its own
that does not use the mapping, and "default" falls back to the kernel default
reader, which uses the mapping.

### projectured-julia

| View | Input → output | Reader | Domain part |
| --- | --- | --- | --- |
| `CellTableToWidgetTable` | `CellTable` → `WidgetTable` | none | a cell: header `j` is `rows[1][j]`, body `rows[i][j]` is `rows[i + 1][j]` |
| `ObjectToWidget` | any object → controls | own | the field of the object that a control edits |
| `FileSystemChooserToWidget` | `FileSystemChooser` → composite | none | the entry of a row |
| `SqlToCellTable` | `SqlSelectStatement` → `CellTable` | none | none: a result cell is no part of the statement |
| `ProjectionConfiguringProjection`, the control | the inner projection → controls | own | none: the control shows the projection, not the input |

### omnet-julia

| View | Input → output | Reader |
| --- | --- | --- |
| `StudyQuestionToWidget`, `StudyExpectationToWidget`, `StudyFindingToWidget`, `StudyStudyToWidget` | study parts → cards | unchanged |
| `SimulationTaskDocumentToWidgetCard`, `SimulationTaskDocumentToWidgetPage`, `SimulationTaskListToWidget`, `LegacyRunToWidget` | legacy simulation tasks → cards | unchanged |
| `SimulationResultModuleToWidgetCard`, `SimulationResultDocumentToWidgetCard` | legacy results → cards | unchanged, and own for a collapse |
| `SimulationResultFrameToWidgetTable` | a result frame → a table | own for a row pick, default for any other selection |
| `OmnetWorkbenchToWidget` | the workbench → a shell | unchanged |
| `SessionViewToWidget` | a session → a card | unchanged |
| `LogViewToWidget` | a log → a card | unchanged |
| `ModuleTreeViewToWidget`, `ModuleGraphViewToWidget`, `SimulationTopologyToWidget` | modules → a tree, a graph | unchanged, and own for going into a module |
| `FindViewToWidget` | the result of a pattern → a list | unchanged |
| `ResultViewToWidget`, `ResultStoreViewToWidget`, `ResultComparisonViewToWidget` | results → cards, tables | unchanged |
| `CaptureTableToWidget`, `CaptureViewToSequenceChart`, `MessageAnimationViewToWidget` | a capture → a table, a sequence chart, an animation | unchanged |
| `ExecutionViewToWidget`, `ExecutionStatusViewToWidget`, `SimulationExecutionToWidget`, `TimelineViewToWidget` | an execution → cards, a control bar | unchanged |
| `SequentialEngineToWidget`, `SequentialEngineDashboard`, `ParallelEngineDashboard`, `TelemetryViewToWidget` | engines, telemetry → panels | unchanged |
| `AccumulatorViewToWidget`, `ObservationViewToWidget`, `ResolvedParametersViewToWidget`, `CheckpointViewToWidget`, `SimulationInspectorToWidget` | one view kind each → a card | unchanged |
| `StrategyViewToWidget`, `SimulationOptimizationToWidget` | a strategy, an optimization → a panel | unchanged |
| `FederationViewToWidget`, `FederationEmbedToWidget` | a federation → a panel | unchanged |
| `ConfigFormOnly` (demo) | a workbench → a form | unchanged |
| `HanoiToGraphics`, `ModuleAppearanceToGraphicsCanvas`, `TimelineStripToGraphics` | a model → graphics | none, own for a click, none |

## 5. Questions for the owner

- **Q1. A part that the view computes.** A readout shows a value that the view
  computes, such as a rate or a count. Claude's recommendation: it is no domain
  part, so it keeps its introduced reference. Only a widget that shows a part
  of the input maps to a domain part.
- **Q2. The forward mapping and the caret.** A view that takes no caret must
  still map a domain reference forward, because a route needs it. Does a
  forward mapping of the domain selection then show a caret in the view? This
  depends on how each printer sets the selection of its output, and step 1
  must find it. Claude's recommendation: no caret; the forward mapping serves
  routes, and the printer does not take the selection from it.
- **Q3. The reader that falls back to the default.** For
  `SimulationResultFrameToWidgetTable`, a click on a header then selects the
  column in the domain. Claude's recommendation: the reader declines a
  selection that is not a row pick, as the other views decline one.
- **Q4. A trailing point.** A chart maps a point on its plot area to the plot
  at that point, a reference that ends in a point step. Inside a view, every
  move of the pointer then gives a new path, and the target tracker sends a
  leave and an enter at each move. Claude's recommendation: the tracker
  compares targets without a trailing point step. This belongs to step 8 of
  the events plan, and it is recorded here because a view with a chart shows
  it first.
- **Q5. The order of work.** Claude's recommendation: first the views that a
  user points at most in the IDE: the log, the module tree, the results, the
  session; then the rest.
- **Q6. The place of the plan.** Most of the work is in omnet-julia. This plan
  is in projectured-julia beside the events plan, because the model and its
  first user are there. It can move to omnet-julia.

## 6. Steps

Each step waits for the owner's "continue".

- [ ] 1. **Study.** For each view, name the domain part of each widget, or
  "none". Find how the printer makes the widget of each part: through a child
  IO map, or directly. Find how the printer sets the selection of its output
  (Q2). Output: the table of §4, filled.
- [ ] 2. **A shared function, only if the study shows one pattern.** For
  example, a list of widgets made from a list of domain parts. Ask the owner
  before it is added, because it is a new mechanism.
- [ ] 3. **projectured-julia.** The cell table, the object form and the file
  chooser. Tests: a point maps to the domain part; the forward mapping of the
  domain part gives the widget path; the click tests still pass.
- [ ] 4. **omnet-julia, the views that print widgets**, in the order of Q5, one
  commit for each view or for each file. Tests for each view: a point maps to
  the domain part, and the suites of omnet-julia give the same results as
  before.
- [ ] 5. **omnet-julia, the views that print graphics directly** and the result
  frame (Q3). The point map uses the hit test of the reader of a click.
- [ ] 6. **Check.** The suites of both repositories against a baseline on
  `main`, and a walk of the IDE window: a point on a log line, a module, a
  result row and a session button names the expected part.
