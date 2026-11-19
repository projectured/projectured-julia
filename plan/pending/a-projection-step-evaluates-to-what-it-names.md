# A projection step evaluates to what it names

**Status:** written on 2026-11-19 at the request of the owner: "let's write up
this whole issue of evaluation of projection induced steps in a future plan.
This needs to fixed eventually but not now." Not approved, and not started.

The issue came up in step 5.4 of `plan/pending/a-click-reaches-the-innermost-part-in-every-view.md`.
That plan does not do this work. The plan lands nothing and pushes nothing: it
ends with a request to land.

**If a step needs a mechanism that this plan does not name, the work stops and
the session asks.**

## The problem

A view can draw a part that no field of its document holds: a button, the
label of a tick of a chart, a bracket, the glyph of a math operator. A path
names such a part by the step `ProjectionReferenceStep(projection,
output_path)`, the projection step. The step stands on the node that the
projection printed, and `output_path` is the place of the part in the drawing of
that node.

The step holds the projection and the place, but not the drawing. So no code
reaches the part:

```julia
# example appearance/appearance/natural: an Alt+double click on the button "Save"
path = …PaneTab.content::Appearance‹.content.children[1].children[1].action.label›::ConcreteReference

try_evaluate_reference(root, path)
# now: ::WidgetScrollPane.content::VerticalLayout.children::CellVector[1]
#        ::HorizontalLayout.children::CellVector[1]::WidgetButton.action::Action.label::String
#      (the place in the drawing, not the part)
# a path from make_introduced_reference, which is not stored: nothing

# Ctrl+C
# now: nothing is copied
```

The value of today comes from one line (`ProjectionReferenceStep.jl:139`):

```julia
evaluate_reference_step(step::ProjectionReferenceStep, document) = step.output_path
```

A new path ends in a node that records `Position`, so its check fails and
`try_evaluate_reference` gives `nothing`. A stored selection is typed again
when the editor writes it, its end records `ConcreteReference`, and the
evaluation gives the output path. The owner, on 2026-11-19: "that sounds a bad
design, a quite random return value. We should clean this up."

## What is known

- **The check of a selection write depends on the value of today.**
  `_matched_selection` (`SelectionDefaults.jl:155`) types the path
  (`annotate_reference_types`) and checks it (`is_valid_reference`). Both
  evaluate the step: its value is the output path, so the end records
  `ConcreteReference` and the check passes. With no value, the check cuts the
  path at the step, and each selection in a drawn part throws
  `SelectionMismatchException`. The same check clears the selection after a
  failed operation (`FaultBarriers.jl:230`) and cuts it after a file is read
  again (`DocumentFile.jl:674`).
- **About 30 places in the editor evaluate the selection** and read the result
  as a document. Each stops at the step now, because the value is no document:
  the owner of a selection (`Operations.jl:756`), the edits
  (`DocumentEdits.jl:27`, `Inversion.jl:101`), the targets of a paste and a cut
  (`Clipboard.jl`, `ClipboardSliceToAny.jl`), the named document
  (`Domain.jl:644`), the innermost document of a tab (`PaneToWidget.jl:652`),
  the selected part (`SelectedPart.jl:12`), the walk of Alt and an arrow
  (`SelectionWalking.jl`) and the route of a gesture (`Chaining.jl:191`). This
  is what keeps the basic work of the editor cheap, and it must stay so.
- **The makers of the step.** 111 calls of `make_introduced_reference` in the
  sources; 99 pass the IO map of the view, 12 do not. Three places build the
  step directly (`WholeSelection.jl:151`, `RosterToGraphics.jl:611`,
  `PivotZoneEdit.jl:191`).
- **`OutputReferenceStep`** (`OutputSelection.jl:19`) holds the drawn node and
  evaluates to it, from its owner only. Two places make it: the mark of a fault
  (`FaultCatching.jl:389`) and the runner form of omnet-julia
  (`LegacySimulationRunnerToWidget.jl:786`). A copy and a note of a fault
  report work through it (`ClipboardTest.jl`, "a copy and a note reach a
  widget a projection drew").
- **An IO map keeps its identity while its output computes again** (`@iomap`),
  so the IO map of a view holds the drawing as it is now.
- **The IO maps that hold children.** 30 IO map types give their children by
  `get_child_iomaps`. In 16 of them the child of one step is a field or an
  index. In 9 it is not clear: the container keeps only the children that are
  documents, so the index of a child is not its index in the input, or the child
  is two to four steps below (`.tabs[i].content`,
  `.vertex_layouts[i].vertex.content`). In 5 the container builds the child
  itself, and no step of the input reaches it: `AppearanceToWidget` prints a
  `WidgetScrollPane` that it makes. 57 more IO map types hold children and give
  none; 11 of them are on the way from the root of the editor to "Save".
- **A view of the content of a tab is in the second stage of the chain.** The
  pane stage passes the content of a tab through as it is
  (`Application.jl:360`), and the renderer prints it. The input of the second
  stage is the output of the first, so no step of the document path reaches the
  IO map of the view. The route of a gesture crosses the stages by
  `map_reference_forward` (`_read_routed_chain`).
- **Probes** (`/var/tmp/ic-scratch/step11/`, `probe-save.jl` and
  `probe-eval.jl`; the folder goes at the end of the plan of the innermost
  click, so the probes are written down here): a walk by `get_child_iomaps` and
  `get_content_iomap` from the root of the editor passes eight layers and stops
  at `WindowManagingIoMap`, which gives no children; its forward map answers
  `nothing` for the path of "Save".

## The decisions of the owner

- **A path holds only steps.** "An iomap is not a step in the path, use the
  projection induced step if that fits." No IO map, output or drawn node goes
  into a step. No new kind of step: "we should not introduce a new reference
  step, there is already a projection introduced step".
- **Two forms of the evaluation.** "When you only have the document and the
  path then it's ok to return a new one but when you have the IoMap then it
  should be the one that's there."
- **The evaluation of the step is an option.** "I'm not sure allowing the
  projection step to be evaluated is always a good idea, maybe it should be an
  option." The name of the option must not sound like graphics: "the drawn
  argument name is weird, looks like it's about graphics."
- **The IO map form is no search.** "it would be a search and not just going
  down the fields and indices, right? Not sure that's a good idea either." And
  on a function that gives the child IO map of one step: "if it's not a search
  then it's good."
- **The editor stays fast.** "We should be careful here to not make the editor
  slow for some basic behaviour."
- **The output path is no value** ("it's just plain wrong"), and **the check of
  a path stops at a projection step and accepts the rest as it is**, in its
  place ("Yes, it's fine").

## The proposals

Proposed by the assistant; each waits for the owner.

1. **The step gives no value, and the check stops at it.**
   `evaluate_reference_step` of a projection step throws an exception that
   says that a document has no drawing, so `try_evaluate_reference` gives
   `nothing` for each such path. `get_valid_reference_prefix` and
   `is_valid_reference` accept the step and the rest of the path as they are,
   and `annotate_reference_types` keeps the rest as its maker typed it. A new
   path and a stored selection then give the same answer.
2. **The document form makes the part again, as an option.**
   `evaluate_reference(document, path; evaluate_projection_steps = true)`
   prints the node with the projection of the step and evaluates `output_path`
   in that output. It gives a new object. Only a caller that asks pays for the
   print.
3. **The IO map form goes down by the steps of the path.** A new function
   `get_child_iomap(iomap, step)` gives the IO map of the child at one step, by
   a field or an index. A wrapper gives the IO map that it shows through
   (`get_content_iomap`). A chain maps the rest of the path forward through a
   stage (`map_reference_forward`) and goes on in the next stage. At the IO map
   of the projection of the step, the walk evaluates `output_path` in the output
   of that IO map, and gives the part that is there.
4. **A write stops before the step.** A paste, a cut, an edit, its inverse and
   the owner of a selection take the document that the view drew, so a drawing
   takes no write.
5. **`OutputReferenceStep` goes.** The mark of a fault and the runner form of
   omnet-julia name their part by the projection step, and use the IO map form.
6. **The copy and the note of a drawn part.** Ctrl+C copies the part that the
   IO map form gives. A note names that part.

## The questions to ask first

Ask them one at a time, before the work starts.

1. How does a container give the child of a step when it keeps only some of
   its children, when the child is several steps below it, or when it builds the
   child itself? The options: each container stores its children by the steps
   that reach them; or the function takes the rest of the path and answers the
   child and the steps that it took.
2. Which features need the part as it is on the screen, and which need only a
   new one? The copy, the note, the assistant, a test.
3. Does the copy of a fault report go with `OutputReferenceStep`, or does the
   mark of a fault wait for the IO map form?
4. Is `evaluate_projection_steps` the name of the option?

## The steps

One commit for each step.

- [ ] 1. **The value and the check** (proposal 1). Tests: a projection step
  gives `nothing` by `try_evaluate_reference`, for a new path and for a stored
  selection; an Alt+click on "Save" and on a JSON bracket writes the selection;
  the repairs after a fault and after a read of a file keep it.
- [ ] 2. **The document form** (proposal 2). Test: the option gives `"Save"` as
  a new object; with no option, the path gives `nothing`.
- [ ] 3. **The child IO map of a step** (proposal 3, first half), for each IO
  map on the way from the root of the editor to a tab and into the second stage.
  Test: the walk from the root of the editor reaches the IO map of
  `AppearanceToWidget` by the steps of the path of "Save", with no comparison of
  inputs.
- [ ] 4. **The IO map form** (proposal 3, second half; proposal 4). Test: the
  form gives the `String` of the label "Save" that the drawing holds, the same
  object; a paste on it writes nothing.
- [ ] 5. **One step for a drawn object** (proposal 5), in projectured-julia and
  in omnet-julia. Test: the tests of the mark of a fault and
  `WidgetSelectionTest`.
- [ ] 6. **The copy and the note** (proposal 6). Test: Ctrl+C on "Save" puts
  `"Save"` into the clipboard and into the clipboard of the system.
- [ ] 7. **The check.** The suites that the steps touch, against main; the
  click test on the catalogs; omnet-julia precompiles with no warning.
