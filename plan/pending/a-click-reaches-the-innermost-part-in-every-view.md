# A click reaches the innermost part in every view

> **Status (2026-11-09): in progress, step 4; steps 1 to 3 are done.** The owner asked for the study
> and this plan on 2026-11-09, decided D1, D2 and D3 the same day, agreed with
> P1 to P6, and approved the plan for implementation ("yes"), with P7. The work
> is on the branch `innermost-click` in the worktree
> `projectured-julia-innermost-click`, and in omnet-julia on the branch
> `innermost-click` in the worktree `omnet-julia-innermost-click`.

## 1. The purpose

The owner, 2026-11-09: "in several cases, for example in the omnet legacy
simulation running and results, the structural selection doesn't work. When I
Alt+click with the mouse often nothing is selected. … My goal is to make the
mouse clicks work generally and position the cursor with simple click and also
structurally select the innermost part with alt+click. Many-many parts already
work as expected but not all. We should make this much more reliable."

And: "We need a generic test which runs on atomic documents. It could test
graphics, layouts, widgets for positional mouse click routing and/or other
documents and projections for structural reference mapping."

And: "The test should cover the atomic examples of omnet-julia as well, the
omnet-julia repo should contain atomic examples just like projectured-julia
which take part of the tests as usual".

## 2. The rule

These rules of the owner hold together:

- **D1 (owner, 2026-11-09).** A part that a view draws and that no part of the
  document holds, such as a value that the view computes, is a part of its own.
  A plain click puts the caret in its drawn text, at the character under the
  pointer ("for a click A is better because it puts the cursor where the mouse
  is"). An Alt+click selects it ("let's do A for both click and alt+click").
- **D2 (owner, 2026-11-09).** "both should go to the innermost part and prefer
  going innermost first and not jumping to projection induced parts first. We
  already do this". And, to correct the first reading of the assistant: "it
  means the path towards the selected part should prefer going deeper compared
  to going to introduced parts but it should still be the innermost part". So
  the selection is always the innermost part under the pointer, also when that
  part is an introduced part, such as a bracket. Its path goes through the
  parts of the document as deep as they go, and the introduced step stands at
  the innermost document that printed the part, never higher.
- **Any part can be selected (owner, 2026-11-06).** An Alt+click can select any
  part of the document of the editor, also a plain value that a field or one
  element of a collection holds, such as the `String` title of a card.
- **The mouse target names the innermost part (owner, 2026-10-22).** No
  container keeps the part under the pointer for itself.
- **A point maps back to the most specific part drawn there (owner,
  2026-09-29).** A part that holds it is reached by navigation.
- **A plain click controls, an Alt+click selects (owner, 2026-09-17).** A button
  still acts on a plain click, and no widget declares that it can be selected.

An example: the card "Run" on the page of a run in the omnet IDE.
`format_run_facts` (omnet-julia `source/legacy/simulator/presentation/SimulationDocument.jl:189`)
gives its rows: `"configuration" => t.config.config` is a field, and `"INI
file" => normpath(joinpath(...))` is a value that the view computes. Each row is
a `WidgetFact` with the fields `label` and `value`.

| The pointer is on | A plain click | An Alt+click |
| --- | --- | --- |
| `General`, the value of "configuration" | the caret in `t.config.config`, at the character | the field `t.config.config` |
| `/…/omnetpp.ini`, the value of "INI file" | the caret in the drawn value, at the character | the `value` of the drawn row |
| `INI file`, the label of the row | the caret in the drawn label | the `label` of the drawn row |
| the title "Run" of the card | the caret in the drawn title | the `title` of the drawn card |
| the `(` of a call in Julia code | the caret beside the bracket | the bracket `(`, named at the call (P3) |

Today, from the code, an Alt+click on each of the first four selects the whole
page of the run (§4), and an Alt+click on the `(` selects the whole call.

The path of each answer, as D2 says:

```
Alt+click on /…/omnetpp.ini:  <the run task document> ‹drawn row 2›.value
                              not: <the pane> ‹the page, the card "Run", row 2›.value
Alt+click on (:               <the document> … <the call> ‹.open›
                              not: <the document> ‹… .open›      (the step stands too high)
                              not: <the document> … <the call>   (the call, not the innermost part)
```

## 3. What exists

### Tests

- **The catalog of atomic examples** (`ProjecturedExample.catalog()`,
  `example/projectured/Catalog.jl`): about 315 small documents, one for each
  document type, also graphics, layouts and widgets. `test_catalog()`
  (`test/projectured/projection/CatalogTest.jl:144`) runs `test_printer`,
  `test_reader`, `test_repl` and `test_position_navigation` on them. None clicks.
  `catalog()` reads only the atoms of projectured-julia
  (`atomic_documents()`, `example/projectured/Catalog.jl:20`), and
  `test_catalog_coverage` (`test/projectured/projection/CatalogCoverageTest.jl:218`)
  fails for a printer that has no atom.
- **The atoms of omnet-julia.** `omnet_atomic_documents`
  (omnet-julia `package/OmnetPresentationExample/src/OmnetPresentationExample.jl:166`)
  holds 7 atoms: the catalog shell, the workbench, the two monitors, the two
  results and the embedded simulation. Only the precompile workload uses them
  (omnet-julia `demo/Precompile.jl:58`); no test runs them. omnet-julia has
  about 99 printers for about 90 document types, 39 of them in the legacy
  views, and no guard that finds a printer with no atom.
- **`examples`** (`example/projectured/ProjecturedExamples.jl:1`): about 144
  examples, with about 45 widget, 8 layout and 3 graphics examples.
- **`test_reader`, `test_repl`** (`test/kernel/editor/ReaderTest.jl:54`,
  `ReplTest.jl:86`): clicks and moves at 5 fixed points, no Alt. They check
  only that nothing throws.
- **`test_click_roundtrips`** (`test/projectured/editor/ExampleSweeps.jl:457`,
  `test/platform/editor/ClickRoundtripTest.jl:113`): a plain click on each
  character of a `TextToGraphics` output; the caret must be drawn on that row.
  It skips every widget, layout, table, graphics and chart example, and only
  `test_all` runs it. `test_mouse_clicks` (`test/projectured/editor/MouseClickTest.jl:331`)
  is a weaker form of it.
- **`test_widget_round_trip`** (`test/platform/projection/WidgetRoundTripTest.jl:171`):
  the 45 widget examples; each widget or layout part maps forward to a drawn
  box, and a point in the box maps backward to the part or to a part inside it.
  It checks the maps, not the readers that a click goes through, it sends no
  Alt+click, and it does not check that the answer is the innermost part.
- **`test_mouse_target_move`** and **`test_json_mouse_target`**: hand-built
  fixtures. The driver `MttDriver` (`test/platform/projection/MouseTargetDriver.jl:8`)
  is reusable.
- **Alt+click:** only hand-written tests, in about 10 files, and one private
  grid scan, `_scan_whole_selections`
  (`test/projectured/projection/ConversationTranscriptTest.jl:91`). In omnet,
  only `test_select_and_paste()` (omnet-julia `test/ide/IdeSelectAndPasteTest.jl`):
  the runner form, the run card and the title of a set of runs.

### The path of a click

1. The backend gives `MouseDown` and `MouseUp`; `ClickRecognition`
   (`source/kernel/gesture/ClickRecognition.jl:76`) makes a `MouseClick`.
2. The window moves the point into its content (`ScreenToScreen`).
3. Each container hit-tests (`hit_element_at`,
   `source/platform/graphics/GraphicsDocument.jl:953`) and calls
   `read_child_event` (`source/platform/layout/LayoutToGraphics.jl:206`).
4. A text leaf maps the point to a caret (`TextToGraphics.jl:313`).
5. Up the chain, the default `read_intent` maps the path with
   `map_reference_backward`, and an answer `nothing` drops the click
   (`source/kernel/projection/ProjectionDefaults.jl:176`).
6. On an Alt+click, `read_child_event` calls `convert_to_whole_selection`
   (`source/platform/focus/WholeSelection.jl:73`). It keeps a whole part,
   selects the child for a caret or an action, and cuts an introduced place to
   the node that printed it. The pane (`_select_page_content`,
   `PaneToWidget.jl:545`), the syntax tree (`_resolve_click`,
   `SyntaxToText.jl:1230`), the card title, the shell band and a few others
   have their own copies of this rule.
7. Ctrl+C copies the selected object only when it is a document
   (`find_clipboard_document`, `source/platform/clipboard/Clipboard.jl:224`).

## 4. Where a click is lost

- **omnet views that answer the whole page.** The pages of 10 kinds of run
  task map every path back to `EmptyReference()`: Run
  (omnet-julia `source/legacy/result/presentation/LegacyRunTaskDocumentToWidget.jl:49`),
  Make, Build step, Coverage report, Feature test, Fingerprint, OppTest,
  ProgramTest, Speed and Validation. Chart, Comparison and Statistical map one
  field only.
- **omnet views that drop the click.** The result table
  (`LegacySimulationResultFrameToWidget.jl:251`, and its reader turns every row
  selection into a row pick, `:230`), the run results
  (`LegacyResultFileToWidget.jl:331`, "a part of it holds no selection"), the
  result file page (`:509`), the header of a file view (`:663`), the plot
  (`:548`), the store (`LegacyStoreToWidget.jl:110`), the test runner
  (`LegacyTestRunnerToWidget.jl:170`) and the event log
  (`LegacyEventLogFileToSequenceChart.jl:47`). The result table view, the plot
  view and `LegacySimulationPlotToChart` map nothing.
- **omnet views that work.** The runner form
  (`LegacySimulationRunnerToWidget.jl:778`) names the drawn widget with an
  `OutputReferenceStep`; the run card and the set of runs map by default.
- **projectured views and layouts that drop the click.**
  `CellTableToWidgetTable` (`read_intent(...) = nothing`,
  `source/platform/widget/CellTableToWidgetTable.jl:73`), `ReflectionToWidget`
  (every path, `source/platform/reflection/ReflectionToWidget.jl:175`),
  `SqlToCellTable.jl:47`, `DataFrameViewToWidget.jl:830`, the layout of a list
  (`LayoutList.jl:323`) and the anchored layout (`LayoutToGraphics.jl:2603`).
- **Containers that stop at a cell.** A table and an accordion map a point to
  a cell or a header, and not on into what it holds
  ([the-work-that-the-forward-image-found.md](the-work-that-the-forward-image-found.md) §1).
- **A drawn part has no object.** The default backward map names a drawn part
  with a `ProjectionReferenceStep`, which evaluates to its output path, a
  reference (`source/kernel/projection/ProjectionReferenceStep.jl:137`). So
  Ctrl+C on it copies nothing. Only `OutputReferenceStep` (focus slice) leads to
  the drawn object, and only the runner form makes one.
- **A value can not be copied.** Ctrl+C on a selected `String`, such as the
  title of a card, copies nothing, because the value is not a document.

A leaf control that answers `nothing` from its maps, such as a switch or a
slider, is correct: the container then selects the control as a whole.

## 5. Decisions

D1 and D2 of §2 and D3 and D4 below are the owner's. P1 to P6 were proposed by the
assistant, and the owner agreed with them on 2026-11-09 ("yes, I agree with the
propsals"). P7 was proposed by the assistant and approved with the plan on
2026-11-09.

- **D3 (owner, 2026-11-09).** omnet-julia holds atomic examples as
  projectured-julia does, and they take part in the tests as usual: the
  printer, the reader, the REPL loop, the navigation and the click test of
  this plan.

- **P1. The test finds the expected part from the forward map** (proposed by
  the assistant). The parts are every document of the input, every value that a
  field or one element of a collection holds, and, below the image of the
  deepest of them, every widget and every field value of the output that no
  part of the input holds (D1). `map_reference_forward` and
  `find_reference_box` give each part the nodes that draw it. The expected part
  at a point is the deepest part whose image draws the element under the point.
  At each point the test sends a plain click, an Alt+click and a move, as a
  person does, through a built editor (`build_editor`, `MouseDown` and
  `MouseUp` through the window). It then checks what is drawn: the caret lies
  on the character under the point, the ring holds the point, and the mouse
  target names the same part as the Alt+click. Rejected: an expected path
  written by hand for each example, because it tests the assumption of its
  author; and `read_intent` alone, because it misses the window and the pane,
  where the omnet pages lose clicks.
- **P2. One kind of path for a drawn part** (proposed by the assistant). The
  default backward map names a drawn part by a path that leads to the drawn
  object, so a copy, a note and the whole-selection rule reach it with no code
  in the view. `ProjectionReferenceStep` and `OutputReferenceStep` become one
  model. Rejected: each view writes the code of the runner form; about 20 views
  need it today, and each new view has dead clicks until it does.
- **P3. The whole-selection rule keeps an introduced part** (follows from D2).
  `convert_to_whole_selection` and its copies keep a path that names an
  introduced part as a whole: a drawn widget, a value of it, and a bracket. A
  caret inside an introduced text becomes that introduced part as a whole, as
  a caret inside a field becomes the field. `_cut_introduced_place`, which now
  cuts the path to the node that printed the place, goes. Each backward map
  puts the introduced step at the innermost document that printed the part, as
  `ProjectionTemplate.jl` already does for a caret (commit 3a3588098, "an
  introduced position stands at the innermost node that printed it"). The
  omnet test `test_select_and_paste()` expects the call for the `(`
  (omnet-julia `test/ide/IdeSelectAndPasteTest.jl:395`); it then expects the
  bracket, named at the call.
- **P4. A plain click on a part that draws no text** (proposed by the
  assistant). It selects the part as a whole, as a chart does now for a data
  point, and as a word processor does for a picture. A control still acts. An
  empty area, such as the padding of a card, keeps its rule of today. Rejected:
  a plain click selects nothing there; then a click on a picture or a vertex
  shows nothing.
- **P5. Ctrl+C copies a selected value** (proposed by the assistant). It puts
  the value into the clipboard as a document (`PrimitiveString` for a text),
  and its text into the clipboard of the system, as the copy of a range of text
  does now. Rejected: a value is copied only through its document; then the
  Alt+click of 2026-11-06 on a `String` title has no use for a copy.
- **P6. Where the test runs** (proposed by the assistant). It is a fifth tester
  of `test_catalog`, a sweep over `examples` in the suite of the package that
  owns each example, and a sweep over the omnet pages in `OmnetIdeTest`. A
  known failure is `@test_broken`, keyed on its signature, as the catalog does.
  Rejected: only in `test_all`; the two click sweeps that are only there failed
  without notice.
- **P8. The value in a leaf is the innermost part** (proposed by the
  assistant; it follows from D2). An Alt+click on the text `Alice` of a JSON
  string selects the `String` in its field, `entries[1].value.value`, not the
  JSON string `entries[1].value`; an Alt+click on a quote selects the quote,
  and Alt+Up reaches the JSON string. The same holds for each leaf that keeps
  its value in a field, and for a text field, whose text is `.content`.
  Rejected: the leaf document is the innermost part; then a value in a field
  is a part only where no document holds it, which D2 and the rule of
  2026-11-06 do not say.
- **D4 (owner, 2026-11-09). A plain click on a row, a node or a cell.** The
  owner chose A of Q1: "It's A, a single click on the padding could go to the
  row though". A plain click on the text of a cell of a table, a row of a list
  or a node of a tree puts the caret at the character, and the row or the node
  that holds the caret lights. A plain click on the padding of a cell or a row,
  where no text is under the point, chooses the row or the node, as a plain
  click on any part of it does today. The click test checks the caret where
  the element under the point is a text, and so it checks the first rule.
  Rejected (B of Q1): a plain click chooses the row, and a double click puts
  the caret in the cell; then a click does not put the caret where the mouse
  is, which D1 says.
- **P7. The catalog takes the atoms of a package** (proposed by the
  assistant). `catalog`, `test_catalog` and the coverage guard take a list of
  atoms and the modules whose printers they cover, with the atoms of
  projectured-julia as the default. Each omnet package that has printers keeps
  its atoms in its example package, as a domain of projectured-julia keeps them
  in `example/document/*.jl`, and its test package runs `test_catalog` and the
  coverage guard on them. An atom of a task comes from a step that has not
  run, and an atom of a result reads a sample file, so a test starts no
  process. Rejected: a second catalog in omnet-julia; then the two search the
  projections in two ways, and a fix in one does not reach the other.

## 6. Steps

- [x] 1. **The test.** (Done 2026-11-09.) Build `test_part_click(example)`: the points (the centre
  of each drawn element, and each character of a text up to a limit), the
  expected part (P1), and at each point a plain click, an Alt+click and a move.
  It also checks the form of the path (D2): no introduced step above the
  innermost document that printed the part.
  It answers a list of failures, one line each with the point, the expected
  part and the answer. Check it on one JSON, one widget and one layout example.

  Found in the work (2026-11-09):
  - **How the test presses.** It builds the editor with `build_editor` and
    the default wrappers on a `HeadlessBackend`, as the app does, so the
    window, the gesture tracker and the pane are on the way. It sends
    `WindowInput(id, MouseDown)` and `WindowInput(id, MouseUp)`, one event in
    each frame, and reads the answer of the frame in `editor.operation`. The
    gesture tracker answers the release with a timer, and gives the click only
    when the timer is due by the wall clock, because a second press could still
    make a double click. So the events have times in the past, 10 seconds
    apart: each timer is due at once, and no two presses make a double click.
  - **What an answer is.** A click answers a `CompoundOperation` of the
    selection and of writes of view state (`ReplaceViewStateOperation`). The
    test counts an answer as the action of a control only when a member of it
    is neither a path, nor view state, nor nothing.
  - **What draws.** A `GraphicsPointerShape` sets the shape of the pointer over
    its box and draws nothing, so the test skips it when it finds the element
    on top at a point.
  - **The oracle, refined.** The parts that the forward map draws give the
    depth that the answer must reach. The caret of the plain click gives the
    rest: it must be drawn at the character under the point, and the Alt+click
    must select the part that holds it. So the test needs no walk of the IO maps
    of the stages, which is ad hoc today (`step_iomaps`, `child_iomaps`,
    `inner_iomap`, `child_iomap`). A forward image that ends in a
    `RegionReferenceStep`, the box around a range over several segments, takes
    no part in the depth check, because its box holds points that the range
    does not hold.
  - **The catalog threw on main.** `catalog()` threw `UndefVarError:
    NavigatorChoiceList` since 2026-10-23 (commit `2ec5c26f9`, which replaced
    the type with `WidgetChoiceList`), so `test_catalog()` could not run. The
    atom `navigator/choice_list` goes, and `widget/choice_list` makes a
    `WidgetChoiceList` with the same two choices.
  - **A first probe over 30 examples** (2026-11-09, about 75 s; step 4 makes
    the full run):
    - In the text domains (JSON, XML, YAML, Julia, SQL, Markdown, the
      formula), each of about 400 plain clicks put the caret on the character
      under the point. The Alt+click fails in two ways: it cuts a glyph, such
      as a quote or a `{`, to its node (P3 changes this rule), and it selects
      the leaf document, such as the JSON string, where the innermost part is
      the value in its field (P8). The move already names the innermost part,
      also a glyph.
    - In the widgets and the layouts, a plain click on a label, the title of
      a card, a fact or a text of a layout gives no caret. A plain click on a
      cell of a table, a node of a tree or a tab selects the row, the node or
      the page (D4 changes this for a cell, a row and a node).
    - A rest of the pointer on a row of facts throws `FieldError: type
      WidgetFact has no field tooltip`: `_find_widget_tooltip(widget::WidgetDocument)`
      (`source/platform/widget/WidgetDocument.jl:4029`) reads a field that
      not every widget has.
    - `chart_bar` and `fsm_diagram` give their document no forward image, so
      the test presses every element of the window there.
  - **What step 1 gives.** `walk_part_clicks(document, projection)` and
    `test_part_click(example)` in `test/platform/editor/PartClickTest.jl`
    (`ProjecturedPlatformTest`). The test presses the centre of each drawn
    element; a point for each character of a long text is not in it, because
    the centre already checks the caret against the character there. The
    platform suite runs it on the `text` example, which passes (2 of 2); the
    other examples join it in step 8, when their failures are marked.
  - **The coverage guard, which could not run since 2026-10-23,** now names 8
    types with a printer and no atom: `HelpEntry`, `OpenFileList` (known since
    2026-10-22), `TextView`, `Url`, `UrlView`, `WidgetFactGroup`, `WidgetIcon`
    and `WidgetLink`. Step 2 adds their atoms, because the click test of the
    catalog needs them, `WidgetFactGroup` above all: it is the card of facts of
    an omnet run page.
- [x] 2. **The catalog takes the atoms of a package (P7).** (Done 2026-11-09.) `catalog`,
  `test_catalog` and `test_catalog_coverage` in projectured-julia take a list
  of atoms and the modules to cover. The tests of projectured-julia give the
  same counts as before.

  Design, found before the work (2026-11-09):
  - **Where the parts live.** `catalog()` is in `ProjecturedExample`
    (`example/projectured/Catalog.jl`), which `OmnetLegacyTest` already loads.
    The runner `test_catalog` and the coverage guard are in the umbrella
    `ProjecturedTest`, which no omnet test package loads. So the runner and the
    guard move into `ProjecturedPlatformTest`, as functions of a list of
    examples and a list of atoms, and the umbrella keeps its lists of known
    failures and calls them.
  - **A variant of the app.** The search of the catalog reaches the screen
    only through text, or through one projection that draws a document whole.
    A view, such as the page of an omnet run, prints widgets, so its atom gets
    no variant on the screen; and a single projection that the search finds
    has no recursion, which is the cause of many `@catalog-broken` marks.
    `catalog(atoms; natural = true)` adds `domain/name/natural` for each atom:
    the projection that an editor makes for a document when it gets none
    (`make_document_projection`), the one that the app uses. The click test
    runs on it. The default stays `natural = false`, so the counts of
    `test_catalog()` do not change in this step.
  - **The coverage guard** takes the roots of the modules whose printers it
    covers, such as `"Projectured"` or `"Omnet"`, and its list of types that
    no test can make.
  - **8 atoms** for the types that the guard named in step 1.

  Done (2026-11-09):
  - `catalog(atoms = atomic_documents(); natural = false, …)` in
    `example/projectured/Catalog.jl`; `test_catalog_examples(examples;
    testers, marks)`, `CATALOG_TESTERS`, `find_catalog_coverage_gap(atoms;
    roots)` and `test_atom_coverage(atoms; roots, no_atom)` in
    `test/platform/editor/CatalogRunner.jl`. The generic guard is not named
    `test_catalog_coverage`, because the umbrella loads the platform test
    package and keeps its own function of that name, which now calls it.
    `test_part_click` takes `broken`, a predicate of a line of failure, as the
    other testers take theirs.
  - The 8 atoms: `widget/link`, `widget/icon`, `widget/fact_group`,
    `help/entry`, `link/url`, `link/url_view`, `fileformat/open_file_list`,
    `text/view`. `widget/link` finds a real fault: a click opens the target as
    a page, and in the stand-in editor of the REPL walk, which holds no pane
    tree, `open_pane!` throws that no pane tree has the focus. It is marked
    `@catalog-broken` with that cause (`_CATALOG_EDIT_NO_PANE`).
  - Checks: `test_catalog_coverage()` 3 pass, 1 broken (the two types of a
    data frame, as before); `test_catalog(; domain = :widget)` 105672 pass,
    26 broken; the full `test_catalog()` 803739 pass, 2311 broken, no
    failure, no error, in 10 min 39 s. This is the first full count since
    2026-10-23, so it is the baseline. The click test on the variant of the
    app works: `widget/fact_group/natural` 19 failures (9 of them the fault of
    the `tooltip` field of step 1), `widget/card/natural` 7,
    `json/string/natural` 6.
- [x] 3. **The atoms of omnet-julia (D3).** (Done 2026-11-09.) An atom for each document type of
  omnet-julia that has a printer, in the example package of its package, with
  the 7 atoms of today among them. The coverage guard and `test_catalog` run in
  each omnet test package. A failure that is there before the click test is
  `@test_broken` with its cause.

  Found before the work (2026-11-09, a search of omnet-julia):
  - **The atoms of today** are the 7 of `OmnetPresentationExample`; no other
    `AtomicDocument` exists in omnet-julia.
  - **The packages with printers** are `OmnetPresentation` (the views of a
    simulation, the embed, the workbench, the monitors, the results),
    `OmnetCosimPresentation` (the federation), `OmnetLegacyResultPresentation`
    (the result frame, file, folder, plot, the task documents of a run page),
    `OmnetLegacySimulatorPresentation` (the runner, the card of a simulation,
    the test runner, the stores, the project page) and `OmnetIde` (the pages of
    the INI files, the NED files, the tests and the stores).
  - **Small instances** come without a process for most types: a view from
    `make_embed_document` (`source/presentation/page/EmbedDocument.jl`), a
    task document from `make_task_kind_document(task, nothing)` with a task
    that has not run, a result from `results/Fifo1-#0.sca`, a federation from
    `FederationEmbed(; rounds = 6)` before its Run. The test helpers that make
    the stub projects of the task kinds need the test folder, so the atoms make
    their projects themselves. Some IDE pages read the disk in the background,
    so their atom must be read to its end before a test uses it.
  - **The natural rows.** The views, the embed and the results have a row of
    `build_omnet_natural_rows`. The legacy documents, the task documents of a
    run page and the pages of the IDE have a method of
    `make_graphics_projection(::Type{<:T}; measure, appearance)`, which the
    entries that `register_natural_graphics!` adds read
    (`source/legacy/result/presentation/ResultGraphics.jl`,
    `SimulationToWidget.jl`, `SimulationBatchToWidget.jl`,
    `LegacySimulationRunnerToWidget.jl`). So `make_document_projection`, and the
    variant `natural` of the catalog, draws them as the app does. A type with
    neither, such as a monitor or an engine, draws as a reflected object; its
    atom says so.
  - **The dependencies.** No omnet test package depends on
    `ProjecturedPlatformTest`; only `OmnetLegacyTest` depends on
    `ProjecturedExample`. The `[sources]` of omnet-julia reach the main
    checkout of projectured-julia, so until steps 1 and 2 land there, this
    step tests in an environment of the scratchpad whose `[sources]` send
    projectured-julia to its worktree and omnet-julia to its own.

  Found in the work (2026-11-09, omnet-julia branch `innermost-click`, worktree
  `omnet-julia-innermost-click`, one commit for each package group):
  - **The lists of atoms.** `omnet_atomic_documents` has 45 atoms (the 7 of
    before and 38 new), `ide_atomic_documents` 12, `legacy_atomic_documents`
    45 and `cosim_atomic_documents` 2. The INI pages live in
    `OmnetLegacySimulatorPresentation`, so their atoms are in the legacy list;
    the IDE list has the pages of the NED files, the tests and the baselines.
  - **The cosim list is filled by the extension.** `OmnetCosimExample` must
    load without a drawing stack, so the list is empty in the package, and its
    extension on `OmnetCosimPresentation` fills it in `__init__`.
  - **The guard sees only a printer on a concrete type.** The printers of
    `OmnetCosimPresentation` are written on the alias `AFederationView`, so the
    guard finds no type to cover there, and `test_cosim_atoms` runs no guard.
    The other roots pass with an empty `no_atom`.
  - **The tests.** `test_ide_atoms`, `test_presentation_atoms`,
    `test_cosim_atoms` and `test_legacy_atoms` run the guard and
    `test_catalog_examples(catalog(atoms; natural = true); marks)`, and the
    aggregate of each test package calls its function. The test packages depend
    on `ProjecturedPlatformTest` and `ProjecturedExample`.
  - **The known failures** are marked `@catalog-broken` by the message:
    - Ctrl+Home finds no caret in a view that a person reads and does not edit,
      so the navigation walk has no state. This is the most common failure: 22
      presentation examples, 10 IDE examples, 2 cosim examples and almost every
      legacy `natural` example. Step 5 (P4) and steps 6 and 7 are about these.
    - `UndefRefError` in `timeline_strip/natural`,
      `simulation_workbench/natural` and `ide/test_case/natural`.
    - `FieldError(NestingIoMap, :content_iomap)` in both cosim `natural`
      examples.
    - One example each in the legacy list: `scalar_differences` (a grid of a
      list with a weighted column), `result_file` (a table of a list needs an
      offered height), `run_entry` (`FieldError` of `configuration`),
      `result_folder` and `simulation_project_page` (a click opens a pane, and
      the walk has no pane tree).
  - **Two faults that a mark can not cover.** Each example has one
    `@test_broken false` and runs no tester:
    - The walk of the testers throws out of the tester in 4 presentation atoms
      (`parallel_monitor`, `vector_result`, `simulation_execution`,
      `module_appearance`): a field holds `nothing` or an undefined slot.
    - The walk of the printer of `legacy/simulation_task_list/natural` does not
      end. It allocates until the cap stops it, also with a list of one task.
  - **The check.** The four tests in one process, at omnet-julia `f488ce735`:
    no Fail and no Error; broken 14 (IDE), 422 (cosim), 1174 (presentation)
    and 516 (legacy), as in the runs of each package alone. The counts of
    passes are larger in one process (197980 against 183944 for the IDE),
    because each package that loads registers its natural rows, and the walks
    then see more views.
- [ ] 4. **The first run.** Run the click test on the catalog of both
  repositories, on `examples` and on the omnet pages: the page of each kind of
  run task, the result table, the result file page and the runner form. Record
  the counts by cause in this plan. No fix in this step.
- [ ] 5. **A drawn part is a part.** P2, P3 and P4 in the kernel and the
  platform; the pane, the syntax tree, the card title and the shell band follow
  the one rule of `convert_to_whole_selection`. P5 in the clipboard.
- [ ] 6. **The causes in projectured-julia.** Fix each cause that step 4
  found in its general rule, one commit for each cause: the views and layouts
  of §4, and the table and the accordion, which go on into a cell and a header.
  The table, the list and the tree follow D4: a plain click on the text of a
  cell puts the caret there, and a plain click on the padding chooses the row.
- [ ] 7. **The omnet views.** Remove the maps that answer the whole page or
  `nothing`; a value that a field holds maps to its field; the result table
  picks a row on a plain click only. One commit for each group of views.
- [ ] 8. **The test in the suites (P6).** Each failure that is left is
  `@test_broken`, with its cause.
- [ ] 9. **The documents and the live check.** `testing-guide.md` (the new
  tester and the atoms of a package), `test-anatomy.md` of omnet-julia (its
  atoms), `mouse-target.md`, `selection.md`, `focus.md`, `widget.md`,
  `clipboard.md`, and `keyboard-and-mouse-guide.md`. The owner checks the page of
  a run and a result page in the omnet IDE.

When this plan is done, Q1 and the model of
[a-view-names-the-domain-part-under-a-point.md](a-view-names-the-domain-part-under-a-point.md),
and §1 of
[the-work-that-the-forward-image-found.md](the-work-that-the-forward-image-found.md),
are done too.

## 7. Not in this plan

- An Alt+click on a tab title of a group without the focus brings back an old
  selection; the fix needs a sealed kernel file (`pane.md:290`).
- An edge of a graph is a decoration by design (`graph.md:88`); the test
  reports it, and the owner decides.
