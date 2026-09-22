# The evaluator draws in a tab

> **Status (2026-09-22): DONE.** The evaluator draws in a pane tab, and
> `test_evaluator_toplevel()` passes 27 of 27.

A tab that holds an `EvaluatorToplevel` stops the editor. The fault comes when a
person types `evaluator` (or `repl`) into the `DocumentInsertion` of a new tab
and presses Enter.

## The fault

    MethodError: no method matching get_graphics_size(::VerticalLayout{…})
      WidgetTabbedPaneToGraphicsCanvas: the page of the active tab

The tabbed pane measures the output of its active tab, and it expects graphics.
The evaluator rows that `EvaluatorToWidget.jl` registers with
`register_natural_graphics!` end in a layout:

    EvaluatorToplevel => EvaluatorToplevelToWidgetComposite()   # a VerticalLayout
    EvaluatorForm     => EvaluatorFormToWidgetCard()            # a VerticalLayout of cards

At the top level the natural renderer prints such an output again until it is
graphics, so the existing test passed. A tab reads its content through
`print_child`, which does not do that; `PaneToWidget` documents the limit. The
registry's own contract is that a row makes its domain "become graphics
directly", and the Markdown row keeps it by chaining
`VerticalLayoutToGraphicsCanvas` after its layout.

A sweep of every type that `get_insertion_candidates(Document)` answers, each in
a pane tab of the application, fails for `EvaluatorToplevel` alone with this
error.

## Design

Each evaluator row ends in graphics, the same way as the Markdown row:

    EvaluatorToplevel => ChainingProjection(EvaluatorToplevelToWidgetComposite(),
                                            VerticalLayoutToGraphicsCanvas())
    EvaluatorForm     => ChainingProjection(EvaluatorFormToWidgetCard(),
                                            VerticalLayoutToGraphicsCanvas())

Both stages of a chain get the renderer's recursion, so the cards and the
documents inside them re-enter the renderer, which is what the top-level print
does now. The form row is chained too: a form that a layout reaches through the
recursion is otherwise dropped, because a layout draws only the children whose
output is graphics.

The alternative is to make the tabbed pane reduce a tab's output to graphics.
That changes the rule that `PaneToWidget` documents, for every host, so it is not
part of this fix.

## Steps

- [x] 1. A test draws the evaluator in a pane tab, and it fails before the fix.
  Before the fix it raised the same `MethodError` as the application.
- [x] 2. The two rows end in graphics; the evaluator test passes, 27 of 27
  (25 before, and the 2 new assertions).
- [x] 3. The insertion sweep passes for `EvaluatorToplevel` in the application.

## Facts found during the work

- **The evaluator takes no typed key**, alone and in a tab, before and after
  this fix. A `KeyPress` read through `NaturalToGraphics` with the caret at
  `elements[1].form.value{0}` answers no operation; the same read on a bare
  `PrimitiveString` answers `ReplaceStringRangeOperation`. The evaluator test
  sets `form.value` directly, so it does not see this. It is a separate fault
  and not part of this plan.
- Six other insertable types fail when a pane tab holds one alone, with other
  errors: `SqlDistinct`, `SqlJoinUsingCondition` and `YamlMappingEntry` have no
  projection registered; `SqlInsertStatement` and `SqlUpdateStatement` reach a
  `Nothing` with no projection; `TextInsertion` reaches `WordWrapping`, which has
  no printer for it. None of them is part of this plan.
