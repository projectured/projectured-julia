# A click reaches the innermost part in every view

> **Status (2026-11-10): in progress, step 5; steps 1 to 4 are done.** The owner asked for the study
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
- **D5 (owner, 2026-11-10). A widget records the part of each drawn line.**
  The owner chose A of Q2 ("Option A"), after the question "Which widget and
  what line?" was answered with the card title: `WidgetCardToGraphicsCanvas`
  draws `w.title` by `_push_text_block!` (`WidgetToGraphics.jl:8716`), which
  pushes one `GraphicsText` for each line and keeps no record of the part.
- **D6 (owner, 2026-11-10). Each view writes the selection of its output.**
  The owner chose A of Q3 ("Yes"), after the question was answered with the
  reflected object: its forward map gives `.value` of the type-name leaf, but
  its printer writes nothing into the `selection` field of the leaf, so
  `SyntaxLeafToText` reads `nothing` and draws no band. Each stage reads only
  the `selection` field of its input, and the chain does not write it
  (`Chaining.jl`, the forward map of the chain). So each view writes the forward
  image of the selection into the documents of the output that it prints, one
  call in its printer, as `InsertionNothingToSyntaxLeaf` does.
- **D7 (owner, 2026-11-11). A header controls its line.** The owner chose A of
  Q4 ("Agreed"): a plain click on the text of a header selects its column or its
  row, and a click on the corner selects the table, as a click on a tab switches
  its page. The caret goes only into the text of a cell (D4). Q4 came from the
  label caret of 5.3: a header gives a click to the label that it holds, and the
  label now takes it, so a click on the number of a row of a data frame view put
  a caret there, and Ctrl+Return opened no row. Rejected (B of Q4): the caret goes
  into the text of a header too, and a click on its padding selects the line;
  then the selection of a row or a column needs a click on a small place.
- **D8 (owner, 2026-11-11). The Alt+click on the half of a quote waits.** The
  owner answered the question of the quote cause of step 6: "Not important for
  now, should be done eventually, but defer this". The change that names the
  character under the pointer goes to §7.
- **D9 (owner, 2026-11-13). The most useful click stays, and a fallback gives
  the caret.** The owner answered the question of a text that a view computes
  to label a part, such as the tick of an axis: "if there's already some
  behavior assigned to a click which does something useful, we should not
  replace that with putting the caret", and then: "if some other behavior is
  more useful for that part, we should use that and we can still have a
  fallback operation which always puts a caret there. The selecting the whole
  part is the same". So:
  - a part keeps the plain click that is most useful for it: an action, a link,
    the choice of the part, such as an axis or a field of a pivot; the caret on
    its text is the plain click only where nothing more useful exists;
  - a fallback gesture always puts the caret at the character under the
    pointer, on any text, so that the text can be copied;
  - the Alt+click selects the part as a whole only where it has no more
    important use there, and another gesture selects the part where it has;
  - a container gets no rule before its parts: "the user can always click at a
    place which talks to the container because usually not everything is
    covered by parts". The rule that the assistant proposed, the action of a
    container before a caret inside it, is rejected.
  The gestures of the two fallbacks are open (Q6).
- **Q6. The gestures of the fallbacks of D9** (asked 2026-11-13). The clicks in
  use: a plain click, Shift+click (extends a range of text, adds a column to the
  sort of a table), Ctrl+click (opens a link or a row in a new tab), Alt+click
  (the part as a whole), a double and a triple click (a word and a line of
  text), a right click (the menu). Free: Ctrl+Alt+click, Alt+Shift+click,
  Ctrl+Shift+click. The first question is the caret; the whole part follows.
- **D10 (owner, 2026-11-13). Alt means "select, do not act".** The owner answered
  Q6 with a question of its own (a logical set of gestures that is easy to
  remember) and chose the scheme that the assistant proposed ("I like this
  scheme"), with Alt+Left and Alt+Right on the siblings, as today:
  - a click does what the part does; where the part does nothing, it puts the
    caret on a text, and selects the part as a whole where there is no text (P4);
  - Alt+click always puts the caret at the character under the pointer,
    whatever the part does;
  - Alt+double click always selects the innermost part as a whole, the part
    that holds the caret of the first click;
  - Alt+Up and Alt+Down widen the selection to the part around it and narrow it
    back, and Alt+Left and Alt+Right move it to a sibling.
  The guides follow ("we also need to document this in the guides"). A plain
  Left or Right on a part selected as a whole puts the caret at the start or the
  end of the part, as a text editor does with a range, "but if there's no
  meaningful caret selection on that part, then I would move to siblings, like a
  selected column in a table, or a selected image in a list".
- **Q2. How a widget knows which part a drawn text shows** (answered by D5,
  asked 2026-11-10). A plain click on the title of a card
  must give `.title{k}`, and a move and the caret must agree with it. Three
  ways, recommended first by the assistant:
  - A. The printer records a line of text with the part it shows: for each
    drawn line, the index of its element, the path of the part, such as
    `.title` or an introduced path of a computed value, and the character where
    the line starts. The record is in the IO map of the widget, as
    `char_to_coord` is in the IO map of `TextToGraphics`, and one helper of the
    widget slice maps a point to the caret, the caret to its box and the box
    back. Each of the 41 calls that draw text passes the part.
  - B. A widget draws each text through a text leaf, a `TextBlock` with
    `TextToGraphics`, as `WidgetText` does, so the carets of the text domain
    work with no new code. Each label then is a projection chain, which costs
    time and memory in a page of many labels.
  - C. Each view writes its own maps, as the card does for its title on an
    Alt+click. Each new view then has dead clicks until it does.
- **Q3. How the output of a view follows the selection** (answered by D6,
  asked 2026-11-10). A probe of 2026-11-10 showed that the
  appearance view, the first example of this question, already wires its
  output (`_follow_tab_paths!` and `set_output_tree_path_computations!`): an
  Alt+click on "Save" selects the button, and the button draws its focus ring,
  in the colour of the focus ring, which the click test did not count as a mark.
  The click test counts it now. A view that wires nothing is the reflected
  object (`ObjectNodeToSyntaxNode`, `_type_leaf`), beside the placeholder leaf
  (`InsertionNothingToSyntaxLeaf`), which wires its leaf. A part that a view
  drew is selected by P3, but it is marked only where the documents of the
  output of the view hold their part of the selection. A printer of the
  template gives each output node its selection; a view that builds its output
  inline, such as `AppearanceToWidget` or `ObjectNodeToSyntaxNode`, gives it to
  the root at most (`make_output_path_cells`), and 5 views call
  `follow_output_selection!`. Two ways, recommended first by the assistant:
  - A. Each view whose output is a tree of documents wires the tree with
    `follow_output_selection!` and the mouse target with it, one call in each
    printer, about 20 printers in projectured-julia and the views of
    omnet-julia; the click test finds the views that do not.
  - B. The printer of a chain wires the output of each stage whose output
    documents hold no computed selection, with no call in the view. A view
    that wires its own keeps its own. A walk of each output tree at each print
    costs time in a large page.
- **Q4. What a plain click on the text of a header selects** (answered by D7,
  2026-11-11). A header gives a click to the label that it holds, and the label
  of 5.3 takes a click on its text.
  - A. The header selects its column or its row, as a tab switches its page;
    the caret goes only into the text of a cell.
  - B. The caret goes into the text of the header, as in a cell; a click on the
    padding of the header, or an Alt+click, selects the line.
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
- [x] 4. **The first run.** (Done 2026-11-10.) Run the click test on the catalog of both
  repositories, on `examples` and on the omnet pages: the page of each kind of
  run task, the result table, the result file page and the runner form. Record
  the counts by cause in this plan. No fix in this step.

  Found in the work (2026-11-09 and 2026-11-10, two runs in the environment of
  the scratchpad, at projectured-julia `f8aa1ff98` with the test changes below
  and omnet-julia `f488ce735`):
  - **What ran.** 661 examples, each in the variant `natural`: 404 atoms of
    projectured-julia, 104 atoms of omnet-julia, the 142 `examples` of
    ProjecturedExample and the 11 `examples` of `OmnetLegacyExample`. The omnet
    pages that this step names are atoms of the legacy list. The second run
    pressed 14 227 points in 46 minutes. 38 examples have points and no
    failure; 18 do not build; 6 draw nothing to press;
    `legacy/simulation_task_list/natural` is not run, because its print does
    not end (step 3).
  - **Three changes of the test.** The first run pressed the whole window when
    the document had no forward image, also the close button of a tab. That
    press closed the tab, and each later point then threw
    `SelectionMismatchException` (2059 lines in 64 examples). So now a document
    with no forward image gets one line and no press, and a press that removes
    the document stops the walk with one line. A line of a throw names the
    first three frames in the source.
  - **The meaning of `@∅` after a plain click.** The test selects the document
    before each press. "A plain click gives no caret: @∅" thus means that the
    press did nothing. For the card title the reader of the card answers
    `DoNothingOperation` (`WidgetToGraphics.jl:9008`): the card draws its title
    as a block of text that no text leaf reads (`_push_text_block!`), so no
    caret can exist there.
  - **The causes**, from the second run. An example counts once for each cause
    that it has.

    | Examples | Lines | Cause | Step |
    | --- | --- | --- | --- |
    | 205 | 4046 | The Alt+click cuts a drawn part of a view, such as a widget of `AppearanceToWidget`, to its document | 5 (P3) |
    | 203 | 2697 | A plain click on a drawn text does nothing: the text is a block that no text leaf reads | 5 (P2, D1) |
    | 134 | 2326 | The Alt+click cuts a glyph, such as a quote or a bracket, to its node | 5 (P3) |
    | 125 | 1472 | The Alt+click selects the leaf, such as `.title`, and not the value in its field, `.title.value` | 5 (P8) |
    | 115 | 807 | The text of a Julia or SQL syntax leaf maps to a step of the view, `‹JuliaIdentifierToSyntaxLeaf .value{1}›`, not to the field that holds the name | 6 (P8) |
    | 81 | 81 | The forward map of the whole document answers `nothing`, so a selection of the document draws no ring | 6 |
    | 74 | 7659 | The view of a reflected object, `ObjectNodeToSyntaxNode`, maps no point to a field: the Alt+click gives the document | 6 |
    | 68 | 391 | The Alt+click stops above the part that the move names, such as `.menu_bar` for `.menu_bar.elements[2]` | 5 (P3) |
    | 60 | 359 | A plain click on a text gives a part, not a caret | 5 (D1) |
    | 57 | 535 | The Alt+click selects a part outside the deepest part under the point | 6 |
    | 55 | 367 | The caret of a plain click is not drawn, such as `.title.value{3}` in a research item and a workflow step | 6 |
    | 43 | 430 | A rest of the pointer on a fact or an icon throws `FieldError` of `tooltip` (`TooltipOperation.jl` to `WidgetDocument.jl`) | 6 |
    | 18 | 18 | The example does not build with `build_editor` (list below) | 6, 7 |
    | 14 | 1074 | The press falls out of the document, and the Alt+click selects the root of the pane | 6 |
    | 14 | 73 | A legacy page of the IDE gives no caret (`LegacyPartPageToWidget`) | 7 |
    | 13, 12, 6 | 206, 236, 100 | A table, a tree, a list or a roster chooses the row, or the move and the Alt+click name different parts | 6 (D4) |
    | 9 | 42 | The caret is not at the character, or not inside the part | 6 |
    | 4 | 101 | A press in a shell writes a path that does not match the document: `SelectionMismatchException` at `Operations.jl` | 6 |
    | 4 | 57 | Other throws: `under-typed @reference` in `GraphToGraphLayout.jl`, `annotate_reference_types(::GraphicsCanvas)`, `keep_held_arrangement(nothing, …)` | 6 |
    | 3 | 162 | An Alt+click on the label of a vertex or an edge of a graph gives the document | 6 |
    | 1 | 1 | A press in `arrangement/document` removes the document from the editor | 6 |

  - **The examples that do not build.** `text/bare_*` (5) and
    `conversation/part`, `conversation/turn`: no `print_document` for
    `WordWrapping` or `VerticalLayoutToGraphicsCanvas` under a
    `RecursiveProjection`. `widget/screen_document`: a `GraphicsCanvas` has no
    field `windows`. `appearance/document`, `omnet/timeline_strip`,
    `omnet/simulation_workbench`, `omnet/simulation_execution`,
    `ide/test_case`: `UndefRefError`. `legacy/run_entry`: no method of
    `_get_configuration`. Both cosim atoms: `NestingIoMap` has no
    `content_iomap`. `examples/chart` ("a Cell read itself while it computed")
    and `examples/json_sorted` (`DeclaredTypeMismatchException`) built at the
    first build in the probe and threw at the second build in the same
    process, so their cause is not the click.
  - **The omnet pages.** `run_task`: the facts throw on a rest, and a plain
    click does nothing. `result_table_view` and `simulation_project_page`: the
    Alt+click cuts each drawn part to the document. `result_file_view`: a
    plain click does nothing, and the Alt+click selects the document outside
    its `.entry`. `result_file`: rows (D4), the facts, and carets that are not
    drawn. `simulation_runner`, `simulation_result_frame` and the results and
    monitor widgets of `examples`: the document has no forward image.
  - **The 81 documents with no forward image.** In each of them, the path of
    the document in the editor has 13 steps and ends at `.content` of the
    `PaneTab`: `windows[1].content.root.tabs[1].content`. Each prefix of it maps
    forward, except the empty path of the pane tree and the whole path. The
    forward map answers `nothing` and does not throw. `json/string/natural` has
    the same path, and it maps. The pane tree and the tab group never answer
    `nothing` for this path (`_child_forward`, `PaneToWidget.jl:110`), so the
    view of the content of the tab, or a layer above the pane, drops it. Step 6
    finds which one.
  - **Slow.** `task/stream_lines/natural` takes 496 s and 9 GiB for 200 points.
- [ ] 5. **A drawn part is a part.** P2, P3 and P4 in the kernel and the
  platform; the pane, the syntax tree, the card title and the shell band follow
  the one rule of `convert_to_whole_selection`. P5 in the clipboard.

  Found before the work (2026-11-10, a read of the code):
  - **Two rules cut a part today.** `convert_to_whole_selection`
    (`WholeSelection.jl:73`) cuts a path at its first introduced step
    (`_cut_introduced_place`), and it turns a caret inside a value, such as
    `.title.value{3}`, into the child whole, `.title`. The pane
    (`_select_page_content`, `PaneToWidget.jl:551`) has its own copy: "a caret,
    or a place the content's projection introduced, names the innermost document
    on its path". These two give the causes `widget`, `glyph`, `value` and
    `stop` of step 4.
  - **More copies cut before the container.** The syntax tree answers an
    Alt+click on a leaf and on its own delimiters with the node
    (`SyntaxToText.jl:183`, `_resolve_click` at `:1230` and `:1268`). The card
    title (`WidgetToGraphics.jl:9026`), the shell band (`:4279`), the table
    headers and cells (`WidgetToGraphics.jl:12744`, `WidgetTableParts.jl:1607`),
    the conversation (`ConversationToWidget.jl:964`), the workspace
    (`WorkspaceToFileSystem.jl:122`), the toolbar (`WidgetToGraphics.jl:3525`)
    and the mark of a fault (`FaultCatching.jl:388`) have a rule of their own;
    omnet-julia has one in the runner form
    (`LegacySimulationRunnerToWidget.jl:780`).
  - **The step of a drawn part.** `ProjectionReferenceStep` evaluates to its
    output path, a `Reference`. A path with it and a typed terminal does not
    evaluate in the input, so the whole-selection test, the clipboard
    (`_selected`, `Clipboard.jl:211`) and a route (`Chaining.jl:191`) treat it
    as a path that does not resolve. `OutputReferenceStep`
    (`OutputSelection.jl:19`) holds the drawn node and evaluates to it; the mark
    of a fault and the runner form of omnet-julia use it. About 30 places
    evaluate a path that can hold an introduced step and read the result by its
    type: the owner of a selection (`Operations.jl:745`), the edits
    (`DocumentEdits.jl:27`, `Inversion.jl:101`), the walks of the focus and the
    pane, and others. A paste or a cut whose target is a drawn part would write
    into the output of a view.
  - **The plain click.** The card draws its title by `_push_text_block!`, which
    no text leaf reads, and its reader answers a plain click with
    `DoNothingOperation`. Only a text leaf maps a point to a caret
    (`TextToGraphics.jl:313`).

  The sub-steps, in this order. The rules of P3 and P8 read the path alone and
  do not need P2, and they fix the largest causes, so they come first. One
  commit for each.
  - [x] 5.1 **One rule for the whole part.** (Done 2026-11-10, with 5.2 in one commit, because both change `SyntaxToText.jl`.) `find_whole_part(document, path)`
    in `WholeSelection.jl` answers the innermost whole part that `path`
    reaches: the path when it names a part as a whole; else the path without
    the place at its end, a caret or a range of text, until a whole part is
    left, so `.title.value{3}` gives `.title.value` (P8). Inside the output path
    of an introduced step, the cut reads the steps: a field and one element
    reach a drawn part, and any other last step is a place in it, so
    `‹.open{0}›` gives `‹.open›` (P3). An output path that becomes empty gives
    the node that printed it. `convert_to_whole_selection` and the pane use it;
    `_cut_introduced_place` and the introduced cut of
    `_find_innermost_document_path` go.

    Found in the work (2026-11-10):
    - **A selection must be drawn.** The click test checks now that a ring or a
      band of the selection holds the point after an Alt+click (`_pc_is_selection_drawn`;
      the colours `selection_ring` and `selection_band` of `GraphicsTheme`). On
      15 examples, the rule alone left a glyph and a value with no mark, for
      example 169 points of 200 in `examples/fsm`, where the old rule drew a mark
      at each point. So the marks are part of this sub-step:
      - The syntax tree maps a whole field of a leaf (`.open`, `.value`,
        `.close`) and a whole delimiter of a node to a band over its characters,
        a `TextSpanReferenceStep`, and moves the band of a child into the frame
        of the parent (`SyntaxToText.jl`, `_leaf_field_span`,
        `_make_entries_span`, `_shift_child_span`).
      - A widget marks a value in one of its own fields:
        `is_whole_selected_field(selection, field; document)` counts
        `.title.value` of a `PrimitiveString` title as the title. A container
        does not do so for its elements, because an element such as a card
        draws its own mark on its title, and the two marks were one too many.
    - **The value of a leaf maps to the field of the domain.** The leaf wiring
      of the template (`AtomicWiring`, `ProjectionTemplate.jl`) mapped a caret
      in the value of a leaf to the bound field, and the whole value to
      `nothing`. It maps the whole value both ways now, so an Alt+click on
      `Alice` gives `.entries[1].value.value` (P8).
    - **A reflected object draws no mark.** The page of the pane test draws
      `DocumentNothing` as a reflected object (`ObjectNodeToSyntaxNode`), whose
      type name is a text that the view computes, so an Alt+click on it selects
      that text, by D1. The view builds its output leaves inline and gives them
      no selection, so no mark is drawn; the old rule selected the content of the
      tab, with the ring of the page. The two assertions are `@test_broken` in
      `PaneReaderTest`; 5.4 and the cause `object` of step 6 fix them.
    - **The tests that change.** `WidgetSelectionTest` (a caret and a letter of
      a card title give `.title`; a text box gives its `String`; new cases for a
      glyph and a caret in a drawn text), `WidgetCardFoldTest` (a
      `PrimitiveString` title gives its `String`), `PaneReaderTest` (a caret in
      a `PrimitiveString` gives its `String`). The click test compares two
      paths without their node types (`_pc_is_same_part`), also inside an
      introduced step, and its cut drops an introduced step whose output path
      becomes empty, as the rule does.
    - **A drawn widget part has no mark yet.** An Alt+click on the button
      "Save" of the appearance view selects
      `‹AppearanceToWidget .content.children[1].children[1]›`, and no ring is
      drawn: the view gives the root of its output the forward image of the
      selection (`make_output_path_cells`, `OutputPaths.jl`), but the widgets
      below the root get no part of it, so no container rings the button. Only
      5 views call `follow_output_selection!`. This is the work of 5.4 (Q3).
    - **The omnet test of select and paste** (`test_select_and_paste`,
      omnet-julia `test/ide/IdeSelectAndPasteTest.jl`). Against the projectured
      code before 5.1, in the same environment, the only new failures are at
      the text box "release" of the runner: an Alt+click gives its text, by P8,
      and its ring had the colour of the focus. The ring of a widget takes the
      colour of the selection also for one of its own fields as a whole
      (`_is_whole_widget_selection`, `WidgetToGraphics.jl`), and the test
      expects the text and its copy as a `PrimitiveString`. The check of the
      bracket of a call expects the step of the view at the call (P3). The test
      set stops before it, also on the old code: `_select_clipboard` reads
      `.slice` of the content of the window, which the settings wrapper makes a
      `SettingsDocument`. That fault is on main (the settings wrapper is on by
      default, and a test passes `settings = false`), and so are the other 9
      failures of this test.
    - **The result on 15 examples of the large causes**, against the second
      run of step 4. `alt:not-caret-part` is the Alt+click that is not the part
      of the caret, `alt:not-drawn` the Alt+click that draws no mark:

      | Example | `alt:not-caret-part` before → after | `alt:not-drawn` after |
      | --- | --- | --- |
      | `examples/fsm` | 185 → 0 | 2 |
      | `examples/formula` | 155 → 2 | 61 |
      | `examples/json` | 85 → 1 | 12 |
      | `sql/and/natural` | 15 → 0 | 0 |
      | `collection/vector/natural` | 5 → 0 | 5 |
      | `appearance/appearance/natural` | 0 → 0 | 105 |

      The marks that are left: a value that a widget draws, such as an element
      of a vector or the title of a workflow step (Q2); a part that a widget
      view drew, such as the buttons of the appearance view (5.4, Q3); a
      delimiter of zero width at the start of a leaf in a formula, and the left
      half of a closing quote, which the caret gives to the value (step 6).
  - [x] 5.2 **The copies follow the rule.** (Done 2026-11-10.) Each reader of
    the list above answers what its child answered, and the container decides
    by `find_whole_part`, or the reader calls it. A control still acts on a
    plain click.

    Found in the work: the syntax tree (`SyntaxLeafToText`, and
    `SyntaxCompoundToText` through `_resolve_click`), the conversation and the
    workspace answer an Alt+click by `convert_to_whole_selection`. The table
    and the accordion stay for step 6, because a plain click and an Alt+click
    go into a cell there (D4). The card title already selects its field; the
    toolbar item declines an Alt+click and the level above selects the item; the
    shell band calls `read_child_event`; the mark of a fault and the runner form
    of omnet-julia make an `OutputReferenceStep` and wait for 5.4.
  - [ ] 5.3 **A plain click on a drawn text (D1, P4).** A plain click on a text
    that no text leaf reads puts the caret at the character: the view that drew
    the text names it by its output path and the index of the character, and
    its backward map names the field that it shows, or an introduced caret. A
    plain click on a part with no text selects it whole; a control acts.
    Found before the work: a widget draws its text as `GraphicsText` lines
    (`_push_text_block!`, `_push_text!`, 41 calls in `WidgetToGraphics.jl`),
    and no map knows which part a line shows. The label answers a point with
    `nothing` (`map_reference_backward`, `WidgetToGraphics.jl:1914`) and reads
    only its bound gestures; the card maps each path of its output into its
    content (`:9088`). So a view needs three maps for a caret in its text: a
    point to the caret, the caret to the drawn place, and the place back. This
    needs new data in the IO map of a widget, so it waited for the owner (Q2,
    answered by D5).

    The design by D5:
    - `DrawnTextLine(text, part, start)`: one drawn line, the `GraphicsText`
      object, the path of the part that it shows from the widget (`.title`, or
      an introduced path of a computed value), and the character of the part
      where the line starts. The record holds the object, not its index, because
      a printer inserts elements before the title after it drew it (the band of
      a selected title).
    - `_push_text_block!` and `_push_text!` take `part` and `drawn`, and push a
      record for each line that they draw.
    - One helper for each map, in the widget slice: a point to the caret
      (`part{start + c}`, by the caret offsets of the font), a caret to its
      place `.elements[i].text{c:c}`, whose box `find_reference_box` already
      gives, and that place back to the caret.
    - The widget draws a caret mark, a thin rectangle at the box of the caret,
      while its selection is a caret in a part that it recorded.
    - The card title is the first model, then the fact and the label; the other
      calls follow in step 6, one cause at a time.

    Done so far (2026-11-11):
    - ~~The card title~~ (7ab296844, on main). The record of a line is
      `DrawnTextLine` (first named `DrawnText`, which `ApplicationModule`
      already exports for the target of a workload click; the rename removes
      the clash).
    - ~~The label.~~ `WidgetLabelToGraphicsCanvas` records each line of a
      `String` content with the part `.content`; its IO map keeps the records
      (`WidgetBoxIoMap.drawn`). A plain single click on the text answers
      `ReplaceSelectionOperation(.content{c})`, a move names that caret, and
      the forward and backward maps use the helpers. A label of a value that is
      not a `String` records no line and answers nothing.
    - **The caret is an element of the canvas of the lines.**
      `make_drawn_caret_elements(drawn, selection, measure)` gives one thin
      rectangle while the selection is a caret on a recorded line, and no
      element else; the card and the label append it to their elements. It
      takes the place of the separate caret mark of the card.
    - **A label leaves a double click to the widget around it** (my decision).
      The help navigator opens the page of a row on a double click; when the
      label answered the double click with a caret, no row opened
      (`test_help_pages` 30/10). A label reads a single click only, so the row
      gets the double click as before. A word selection on a double click is
      not part of this plan.
    - **A header and the corner keep every answer but a caret in a label**
      (D7). The table gives a plain click on a header or on the corner to what
      it holds, and keeps the answer unless it is a selection in a text that
      takes no key (`_find_control_answer`, `_is_read_only_text`, true for a
      label). So a click on the label of a header selects the line, or the
      table for the corner, and an action, such as the toggle of a checkbox, and
      a caret in a text that takes keys stay: a text field, and the text of the
      header of a markdown table, which is the text of the document (my reading
      of D7, which the owner gave for a header that shows a label). Two first
      versions failed: the caret in the header text as in a cell (my reading of
      step 6; the data frame suite showed 5 failures and 9 errors), and a rule
      that kept only a selection in a document that takes the focus
      (`is_focusable_document`), which dropped the caret in a markdown header
      (`MarkdownTableTest.jl:150`).
    - **A cell follows D4.** A click on the text of a label cell puts the caret
      there, and a click on its padding selects the row: `WidgetTableTest`,
      `WidgetTablePartsTest`, `WidgetTablePartSelectionTest`. The point tests
      expect the caret in the text of the label under the point:
      `LayoutPointTest`, `WidgetPointTest`, `AnchoredLayoutTest`. The search of
      the settings test starts right of the text of the label. The pivot keeps
      the labels of its cells as its own documents, so the caret in a cell of a
      pivot is a place of the pivot (`PivotTableToWidgetTest`).
    - **A label cell of a data frame view is selected whole.** The view shows a
      value that no primitive document holds, such as a `Symbol`, as a label
      that it makes (`make_data_frame_cell`), so the text of the label has no
      place in the frame, and the caret there threw a
      `SelectionMismatchException`. The view already selects a cell of a column
      that takes no write whole (`_find_whole_read_only_cell`); a label cell
      takes no key either, so it follows the same rule, in the selection and in
      the backward map (`_is_shown_as_label`). A caret in the text of such a cell
      waits for the step for a drawn part (5.4).
    - **Found:** the note of a tooltip threw a `FieldError` (`second`) on a
      fact that is a condition of a decoration, since the D6 wiring of
      212901ac9 (efda41c32).
    - ~~The fact.~~ `WidgetFactGroupToGraphicsCanvas` records the line of a
      title that is a `String` (`.title`), the line of each label that is a
      `String` (`facts[i].label`), and each line of a value that is a `String`
      (`facts[i].value`), in its IO map (`drawn`). A plain single click on such
      a text puts the caret there, and a move names that caret. A value that is
      no `String`, such as a number, records no line, as for the label. A
      double click, and a plain click on the rest of a row, go on to the widget
      around the group, as before: the rest of a row chooses the row as today
      (D4). The label of a fact takes the caret as any text: a fact is a row of
      data, and its label is a field of the fact, so D7, which is for the
      header of a table, does not apply (my reading).
    - **An Alt+click on a drawn text selects its field** (P8: the value in the
      leaf is the innermost part). The label and the fact group answer the
      caret on an Alt+click too, as the card does, and the container makes the
      field as a whole (`convert_to_whole_selection`). Before, the label
      answered nothing, and the click walk showed that an Alt+click on the text
      of a label selected nothing. An Alt+click on the rest of a row of facts
      selects the fact. `WidgetSelectionTest` now expects the text of a label
      for an Alt+click on it, as it already expected the text of a text box;
      the label as a whole, which a path names, keeps the ring of its
      container.
    - Click walk on the app variant: `widget/fact_group` 20 failures before,
      0 after; `widget/label` 2 before, 0 after; `widget/card` 3 before, 2
      after (the two texts in the content of the card, which another widget
      draws, wait for step 6).
    - **A band marks a drawn text selected as a whole.**
      `make_drawn_selection_elements(elements, drawn, selection, measure,
      band_color)` takes the place of `make_drawn_caret_elements`: it puts a
      band in the colour of a selected part behind each line of the part that
      the selection names as a whole, before the first element that holds a
      line, and the caret on top. The label, the card and the fact group use
      it, so the separate band of the card title (`_make_title_band`) goes, and
      the description of a card has its band too. The node of a row of facts
      draws the same band while its fact is selected as a whole.
  - [ ] 5.4 **One step for a drawn part (P2).** The introduced step holds the
    output that its projection drew, and evaluates to the drawn part. The owner
    chose it as the next work on 2026-11-11 ("Ok"), before the widgets that record
    no line, because most of the plain clicks that do nothing in step 6 are on a
    label that a view computes.

    Found before the work (2026-11-11, two probes), against the reason of that
    choice:
    - **A step of a view validates today.** It evaluates to its output path, and
      the selection records the type of that path at its end
      (`annotate_reference_types`, `get_valid_reference_prefix`), so a caret in a
      label that a view made is a valid selection as soon as the view names it
      by an introduced reference. The kernel change of 5.4 gives the copy, the
      note and the whole rule a drawn part (P2); it does not give a caret.
    - **The dead plain clicks have other causes.** In `task/group`, "T2" and "not
      started" are badges in the title of a card: the badge records no line, so
      the card answers `DoNothingOperation`; the Alt+click and the move already
      name the badge. In `examples/research_contested`, a click on "Q1" or
      "answered by" selects the question, `.questions[1]`: the research view
      chooses its row by a rule of its own (D4 for a row), and the statement of a
      question already takes the caret since 2bebb39d7.
    - So the order waits for the owner again: the widgets that record no line
      and the rows of the views first, or 5.4 first. The owner chose the widgets
      and the rows first (2026-11-12, "yes"), and asked whether a widget whose
      click is its operation keeps it. It does, by P4: a button, a link, a menu
      item, a toolbar item, a checkbox, a toggle, a radio option, a select, a tab
      and a header (D7) act on a plain click and take no caret. Only a text that
      a widget shows takes the caret: a label, a badge, an avatar, an alert, a
      status text. A gesture bound to the widget comes first, as for a label.
      The rows of a table, a list and a tree follow D4.
    `OutputReferenceStep` goes, and its users make the introduced step. Each
    place of the list above is checked; a paste and a cut refuse a target in a
    drawn part.

    By D6, 5.4 also makes each view write the selection of its output. Found in
    the work:
    - **The reflected object** (`ObjectNodeToSyntaxNode`, `ObjectToSyntax.jl`)
      gives the root of its output, the type-name leaf or the node of the
      object, the forward image of the selection and of the part under the
      pointer (`make_output_path_cells`). The syntax node maps a path into its
      children by its own forward map, so the root alone is enough here.
    - **A whole field of a root leaf drew nothing.** The forward map of
      `SyntaxLeafToText` gives the band of a whole `.open`, `.value` or
      `.close`, but the selection cell of its output used only the caret map
      (`_leaf_cursor`). Inside a node, the parent drew the band, so the runs of
      step 4 did not show it. The printer now also maps a whole field to its
      band (`_find_whole_leaf_field`).
    - **Run 3 of the click test** (2026-11-10, after b5bf7b9c0, 661 examples,
      1 h 22 min). `alt:not-drawn` is the Alt+click that draws no mark, which
      run 2 did not count apart:

      | Kind | Run 2 points | Run 3 points | Run 2 examples | Run 3 examples |
      | --- | --- | --- | --- | --- |
      | `plain:no-caret` | 3365 | 3361 | 217 | 223 |
      | `alt:not-drawn` | – | 2388 | – | 224 |
      | `alt:outside` | 1709 | 1628 | 73 | 74 |
      | `move:differs` | 9580 | 938 | 441 | 144 |
      | `plain:caret-not-drawn` | 367 | 367 | 55 | 55 |
      | `throws` | 606 | 204 | 69 | 44 |
      | `alt:not-caret-part` | 7489 | 147 | 335 | 22 |
      | `no-image` | 81 | 59 | 81 | 59 |
      | all | 23240 | 9136 | | |

      The 443 points of `alt:not-drawn` in the reflected object are all on a
      delimiter: a space (234), a quote (161), `]` (45) and `}` (3). The caret
      there goes to the part beside the delimiter, which does not hold the
      point; this is the delimiter cause of step 6, not the wiring of D6.
    - **A probe of the chain** (`probe-chain.jl`, one unmarked Alt+click of each
      view) put each view into one of four classes: the root of the output holds
      no selection (D6, 20 views of projectured and 5 of omnet-julia); the root
      holds it, but a container below holds nothing (D6, the explorer section,
      the explorer search, the help entry); each document holds its part, but
      the widget draws no mark for it (the models of 5.3 and step 6: the content
      of a scroll pane, a layout constraint, the header of a table, the
      description of a card); a delimiter (step 6).
    - **The functions of D6 are in the widget slice.**
      `follow_widget_output!(root, input, map_forward; is_followed)` gives each
      widget and layout of the output of a view its part of the selection and of
      the part under the pointer. `follow_built_children!(holder)` does it for
      each child that a computation of a layout builds after the print, because
      the walk of the print reaches only the children that are there.
      `is_widget_or_layout` is the default rule: a widget, a layout, a layout
      constraint, or a `CellVector`, which is the row of a table. They are not in
      the focus slice, because a view slice such as statistics has no edge to
      focus in `PLATFORM_SLICE_EDGES`, and every view that draws widgets uses the
      widget slice. A syntax view writes the paths of its root with
      `make_output_path_cells`, because a syntax node maps a path into its
      children itself.
    - **A view leaves out a part that holds its own selection**: a document of
      its input that it puts into its output whole, also when that document is a
      widget, such as the kind document of a task (`WidgetFactGroup`) and the
      documents of a tooltip; and a field with its own map, such as the title of
      an explorer section and the field of the place of a folder.
    - **The views of projectured** (8066eeae3, 8c8949b40, b4bbac502, 0755cd4a9,
      8f3c4f516), the Alt+clicks that draw no mark in run 3 and after:
      system process 14 → 0, task 16 → 1, task execution 9 → 1, task stream
      15 → 0, task group list 3 → 1, closed task group 6 → 0, tooltip note 7 → 0,
      tooltip content 3 → 3, MCP log 27 → 10, workflow journal 8 → 0, folder
      9 → 1, pivot part table 11 → 2, formula 1 → 0, formula environment 1 → 1,
      explorer section 19 → 18, explorer search 19 → 1, help entry 6 → 1,
      message log 4 → 0, gesture log 6 → 0, about page 5 → 0, reversing 17 → 5,
      frame statistics (all failures) 119 → 41, fault log (all failures) 8 → 0.
      No count of all failures grew, and no example throws.
    - **`PivotTableToWidget` stays as it is.** It computes the selection of its
      grid, its bar and its table with its own maps, and the walk would replace
      them. Its 10 points are the labels of its zones and the cells of a header:
      the model class.
    - **A fault found by the work**: the computation of the row count of
      `GridLayoutToGraphicsCanvas` assigned `p` in its closure, so the printer
      read a vector as its projection once the count computed early (8c8949b40).
    - **The views of omnet-julia.** The part page (`_finish_page`,
      `LegacyIniFileEntryToWidget.jl`) gives its widgets the selection too: on
      five part page examples, 200 → 7 Alt+clicks that draw no mark. 20 more
      views that gave their widgets only the part under the pointer call
      `follow_widget_output!`, and keep the parts that they leave out. Four views
      set some selection cells by hand: `CatalogShellToWidget`,
      `SimulationWorkflowToWidget`, `SimulationEmbedToWidget` and
      `SimulationOptimizationToWidget` (the best row of its table). A walk would
      overwrite those cells, and the click test shows no failure from them: their
      catalog examples show the reflected object. They stay as they are. The
      click walk after b72a25adb, run 3 → after: the project page 74 → 2, the
      run entry 18 → 0, the part pages of a test kind, an INI file, a
      configuration, the INI files of a project, an INI folder, the NED files of
      a project, a NED package, a test folder, a statistical baseline and a chart
      baseline each from 23–41 to at most 3; no count grows and no example
      throws. The view tests fail only as on the base of the branch:
      `test_topology_card` 14/2, `test_sim_control_panel` and
      `test_sim_dashboard_panel` 1 error each (`get_future_event_set` has no
      method for `ACSequentialEngine`), `test_batch_widget_layout` 4/2/1, and
      `test_parallel_sim_dashboard_panel` hangs.
    - **The last two omnet views of the probe** (181066b6e): the list of
      simulation tasks writes the paths of its layout, and the plot view of a
      result gives its widgets their part. The combined simulation widget
      107 → 99, the result plot view 29 → 22. The rest have other causes:
      - The tabs of the selector of the combined widget
        (`.selector_element_pairs[k]`) draw no ring.
      - A part inside a run card: the backward map of the task list answers its
        own introduced path (`‹SimulationTaskListToWidget .children[1].title…›`)
        and not the path of the task through the card, so the card, which
        follows the selection of its task, never gets the part. The backward map
        must delegate to the IO map of the child.
      - The axes of a chart (`‹LegacySimulationPlotToChart .y_axis›`): the model
        class.
    - **A native document keeps its selection as a plain value** (9ff929585).
      The topology card of omnet-julia takes a native `MSimulationInstance`, and
      `get_stored_selection` and `is_live_selection` read the `selection` field
      as a cell, so the walk of the card threw. They read it with `unwrap_cell`
      now; for a document of the cell layout nothing changes.
    - **Points that stay unmarked**, for 5.3 and step 6: the content of a scroll
      pane (MCP log, help, task, explorer search, task list), the background of a
      header cell of a table (folder, pivot part table), the navigator of the
      explorer, which is another view, a text inside a layer document of a
      tooltip, the label of an embedded formula, and the quote leaf of a string
      in the reversing view.
  - [ ] 5.5 **Ctrl+C copies a selected value (P5).** The copy of a value is
    done (2026-11-10); the copy of a part that a view drew waits for 5.4.

    Found in the work: the copy (`_clipboard_copy`, `ClipboardSliceToAny.jl`)
    takes a selected value that is not a document as the primitive document of
    its kind (`_make_value_document`: `PrimitiveString`, `PrimitiveNumber`,
    `PrimitiveBool`), and the mirror into the clipboard of the system takes
    its text as for any document. `find_clipboard_document` does not change,
    because a note names the original: a note of a value takes nothing. The
    test is in `ClipboardTest.jl`.
  - [ ] 5.6 **The check.** The click test on the catalogs, against the counts
    of step 4, and the suites that the change touches, against main.
- [ ] 6. **The causes in projectured-julia.** Fix each cause that step 4
  found in its general rule, one commit for each cause: the views and layouts
  of §4, and the table and the accordion, which go on into a cell and a header.
  The table, the list and the tree follow D4: a plain click on the text of a
  cell puts the caret there, and a plain click on the padding chooses the row.

  Done so far (2026-11-10):
  - **A fact and an icon throw on a rest of the pointer** (43 examples). Every
    drawn widget type carries the field `tooltip`, as `test_widget_tooltip`
    states ("the sweep is the claim"); `WidgetFact`, `WidgetIcon` and
    `WidgetIconMark` had none, so the tooltip binding of `WidgetDocument` threw
    `FieldError`. They have the field now, with the default `nothing`, so each
    caller with fewer arguments stays as it is; about 36 lines of the recorded
    precompile lists name the old types, far below the limit of 10 %. The
    sweep test names the three types. The click test finds no throw on
    `widget/fact_group`, `widget/icon`, `legacy/run_task` and
    `legacy/configuration_view` any more (9, 0, 13 and 20 before).
  - **A primitive has no forward image** (part of the 81 examples). The
    forward map of the primitives as text (`_forward_value`,
    `PrimitiveToText.jl`) took only a place `.value{s:e}`: the whole primitive
    and its whole value mapped to `nothing`, so a selection of either drew no
    mark. It maps the whole primitive to the whole block and the whole value to
    the range of all its characters now, also for the selection of the block.
    The click test passes on `primitive/string`, `primitive/number`,
    `primitive/bool` and `collection/vector`, with no failure. The 81 examples
    are drawn by many views, and a type dispatch hands back the IO map of the
    row, so no one place can map the whole input of every view.
  - **A view that maps only introduced references forward.** About 40 views
    have the one-line forward map `find_introduced_path(p, reference)` (3 in
    the platform and the domains, `SqlToCellTable` in the `odbc` adapter, and 35
    files of omnet-julia), and the docstring of `find_introduced_path` says
    that such a view maps those references "and only these" forward. So the
    whole document of such a view maps to `nothing`, and a selection of it draws
    no mark. The default forward map does the same and maps the whole input to
    the whole output, so the one-liners go: the three of the platform and the
    domains are gone, and the docstring of `find_introduced_path` says the new
    rule. `statistics/frame_statistics` (79 points) and `workflow/journal` (23
    points) have a forward image now; `CellTableToWidgetTableTest` expects the
    whole table to map to the whole widget table. `SqlToCellTable` and the 35
    files of omnet-julia follow in step 7. `statistics/frame_time_series` and
    the other views of the list lose the whole document in maps of their own.

  **The baseline of step 6** (2026-11-11, run 1 of step 6, branch at
  e7ff5e058 on main 165fabe77). The click test on the catalog of
  projectured-julia (404 atoms, variant `natural`) and its 142 `examples`, in
  `environment/all` of the worktree, with a cap of 8 GiB: 546 examples in 29
  min, 6164 lines. `task/stream_lines` does not run, because it needs 9 GiB.
  The omnet atoms are not in this run; step 7 runs them.

  | Examples | Lines | Cause |
  | --- | --- | --- |
  | 115 | 1594 | A plain click on a text does nothing: icons, badges, chips, buttons with no action and other texts that a widget draws with no record of its part (most in the research views, the task group and the workflow) |
  | 65 | 394 | A plain click on a text gives a part, not a caret |
  | 62 | 303 | The text of a syntax leaf maps to a step of the view, not to the field (P8) |
  | 51 | 401 | The reflected object: an Alt+click on a delimiter (a space 201, a quote 152, `]` 45, `}` 3) selects a part that does not hold the point, or one that draws no mark |
  | 48 | 342 | The caret of a plain click is not drawn |
  | 45 | 354 | The Alt+click selects a part outside the deepest part under the point |
  | 38 | 162 | The move and the Alt+click name different parts |
  | 37 | 37 | The document has no forward image |
  | 15 | 1110 | The press falls out of the document to the pane |
  | 14 | 188 | The Alt+click selects the leaf, not the value in its field (P8) |
  | 10 | 75 | `SelectionMismatchException` |
  | 9 | 9 | The example does not build |
  | 6, 2 | 91, 38 | A table, a tree or a roster chooses the row (D4) |

  The Alt+clicks that draw no mark (1274 lines) are in the rows above by their
  view: the reflected object 401, the formula 184 and the Julia operations 112,
  the work plan 36, XML 32, the primitive string 32, and widget parts such as
  `.menu_bar`, `.elements[i]` of a split pane and the tabs of a tabbed pane.

  The causes of the reflected object, from a probe of `primitive/object_field`:
  - ~~**A delimiter of a child on a line of its own draws no band**~~ (the `]`
    and the `}`). The Alt+click selects `.close` of the inner node, and the
    syntax text holds a band for it, but the band covered the break and the
    indentation, not the `]`: `_shift_child_span` moved the start of the band of
    a child into the parent and kept its length, and the parent indents the lines
    of the child further. It moves the first and the last character now, each to
    its entry (`_shift_child_flat`).
  - ~~**A space at the end of a line lies beside the band**~~ (most of the 201
    spaces). The space is the separator of a node, and the Alt+click selects
    that node, which is right. The band of a node hugs the characters that
    draw: a piece of only whitespace sets no edge of a row (`_hl_piece_blank`,
    `TextToGraphics.jl`), so the band ends before the space. A text of only
    whitespace draws nothing, so the click test takes it as an empty area (P4,
    my reading): after an Alt+click there, it checks that the output draws a
    mark of the selection, not that the mark holds the point
    (`_pc_is_blank_text`).
  - **The inner half of a quote gives the value** (152 points, and the quotes of
    JSON and of the other syntax views). Deferred by the owner (D8), in §7: it
    needs a change in four slices. A plain click puts the caret at the edge
    nearest the point, which is right. The Alt+click and the move take their
    part from that caret, and a caret on the edge of two parts belongs to one
    of them by the backward map of the syntax text, which takes the left part
    at one edge and the right part at another. So they must name the character
    under the point, as a range of one character. A try (not committed) showed
    what that needs:
    - the text view answers the range of the character under the point to an
      Alt+click and a move (`TextToGraphics`);
    - the node and the leaf of the syntax text map a range in a delimiter of
      their own back to that field; today `_map_compound_range_backward` looks
      only into the children and answers `nothing`, and the editor selected the
      whole document;
    - `find_whole_part` takes a range of one step in the output path of a view
      as one drawn element, so it must read a range of one character of a text
      as a place;
    - the click test reads such a range as a place, and accepts a caret at an
      edge of the mark of the part that the Alt+click selects.
  - ~~**A delimiter of only whitespace has no band**~~ (288 of the 312 points of
    the formula and the Julia operations). The Alt+click on the space before an
    operator selected the delimiter `.open` of the leaf of the operator, which
    is a space, and a band of only whitespace draws nothing. Such a delimiter
    draws nothing, so the Alt+click selects the leaf or the node that holds it
    (`_lift_blank_delimiter` in the two Alt+click readers of `SyntaxToText`); a
    value of only whitespace is data, and it stays. The click test lets the
    part of an Alt+click on a blank text hold the part of the caret and of the
    move (`_pc_is_part_within`). `examples/formula` 67 lines before, 9 after;
    `examples/fsm` 2 → 0; `julia/assignment` and `julia/toplevel` 2 → 0. The 9
    that are left: a caret on `42` that goes to the empty delimiter at the
    start of the number (5 lines, 3 before), and the math leaves that map their
    value to a step of the view (P8, 4 lines).
  - ~~**The value of a primitive leaf is a step of the view**~~ (P8; 124 of the
    303 lines of the leaf cause: `PrimitiveStringToSyntaxLeaf` 80,
    `PrimitiveNumberToSyntaxLeaf` 36, `MathVariableToSyntaxLeaf` 8). These leaves
    mapped a caret in the text of the leaf to the field of the primitive, but
    not the text as a whole, so an Alt+click selected
    `‹PrimitiveStringToSyntaxLeaf .value›`, which no mark draws. The text as a
    whole maps to the field as a whole now, both ways, for the bool, the number
    and the string, and for the name of a math variable. The walk:
    `examples/collection` 25 → 5, `examples/filtering` 16 → 8,
    `examples/reversing` 25 → 5, `examples/formula` 9 → 5. The other views of
    the leaf cause are widget parts of a view, the model class.
  - **A plain click on a text that a widget draws with no record of its part**
    (1594 lines in 115 examples). Two groups:
    - ~~The glyph of an icon~~ (581 lines in 52 examples). An icon is a picture
      that an icon font draws (`make_glyph_icon`), and a picture takes no caret
      (P4). The click test takes a text of only characters of the private use
      area of Unicode, where Lucide keeps its glyphs, as a picture
      (`_pc_is_icon_glyph`). The walk: `examples/research_contested` 360 → 303,
      `task/group` 115 → 95, `examples/workflow_recorded` 255 → 193,
      `widget/icon` 4 → 3.
    - The texts (1013 lines in 101 examples). Most are in the views of research,
      the task group and the workflow, which make a label of a `String` that
      they compute from the document, in their own output: a caret there is a
      place in the output of the view, the caret in a computed label of 5.4
      (P2). The rest are the texts of about 25 widgets that record no line: the
      badge, the avatar, the alert, the status bar, the tree, the list, the
      tooltip, the dialog, the accordion, and the controls (a button, a link, a
      menu item), whose plain click acts. They follow one widget at a time.
    - ~~The badge~~ (2026-11-12). The badge records the line of a content that
      is a `String`, as the part `.content` (`_build_badge_elements` takes
      `drawn`; a tab strip that draws badges passes none), and it maps and reads
      a click on its text by the functions of the label
      (`_map_content_text_forward`, `_map_content_text_backward`,
      `_read_content_text`): a plain single click puts the caret, an Alt+click
      selects the text, a move names the caret, a double click goes on. Both use
      one canvas with the marks of the selection (`_make_drawn_text_canvas`). A
      badge in a header takes no caret (`_is_read_only_text`, D7). The walk:
      `examples/widget_badge` 16 → 0, `widget/badge` 3 → 0, `task/group` 95 →
      83, `task/group_list` 39 → 26. What is left in the task group is the
      rows of its roster (D4) and the buttons that the example disables: a
      disabled button is a control too, and the click test can tell it only when
      a path reaches a drawn part (5.4).
    - ~~The avatar and the alert~~ (2026-11-12). The avatar records its initials
      as the part `.initials` when they are a `String` (an icon records nothing),
      and the alert records its title and each line of its description, as
      `.title` and `.description` (the description is drawn by
      `_push_text_block!`, which breaks it as before). The shared functions are
      named by what they read: `_map_drawn_text_forward`,
      `_map_drawn_text_backward`, `_read_drawn_text`. The walk: `widget/avatar`
      2 → 0, `widget/alert` 5 → 0, `workflow/workflow` 37 → 30. In the research
      views an Alt+click on the id of an item, such as "Q1", selects the root of
      the pane: that is the cause of the press that falls out to the pane, and
      it comes next.
  - ~~**The press that falls out to the pane is a fault of the test**~~ (most of
    the 1110 lines in 15 examples). The walk collected the drawn elements once.
    A plain click on a control that changes what is drawn, such as the option
    "By kind" of the toggle group that orders a research view, moved the
    layout, and each later point pressed a place that had moved; most of them
    hit the pane around the view. The test did not see the action, because each
    press writes the state of the gesture tracker, so a write of view state
    tells nothing. Now:
    - a plain click that moves a drawn text acted, so the test expects no
      caret there (`_pc_get_text_layout` before and after the press);
    - when a point moves a drawn text, with the pointer off the window so that
      a light shows nothing, the walk builds the editor again from `remake()`
      and goes on with the next point (`_pc_open_session`); with no `remake`
      it stops with one line. `test_part_click` passes `remake`.
    The walk: `examples/research_contested` 303 → 114, `examples/research`
    295 → 103, `task/group` 83 → 53, `examples/filesystem` 42 → 15;
    `examples/json` stays at 12. What is left in the research views: a plain
    click on the id of an item selects the item (the row rule of the view), and
    the caret in a statement is set but not drawn.

  **Run 2 of step 6** (2026-11-12, at 9147be27a, the same 546 examples as run
  1): 3209 lines in 300 examples, against 6164 lines in 343. By kind:
  `plain:no-caret` 1182, `alt:not-drawn` 598, `plain:caret-not-drawn` 427,
  `move:differs` 391, `alt:outside` 283, `alt:not-caret-part` 236, `throws` 43,
  `no-image` 37. The largest causes left: a plain click on a text gives a part,
  not a caret (65 examples, 820 lines); a plain click does nothing (82, 277);
  the caret is set but not drawn (48, 427); the reflected object (49, 152);
  the Alt+click outside the deepest part (44, 248). Three examples threw out of
  the walk in run 2 (`assistant/work`, `examples/assistant_work`,
  `explorer/explorer`): a read of the layout or the second build threw, outside
  the check of a point. The walk now records such a throw as one line and stops.

  - ~~**A text in the row of a record in an outline gives the record**~~ (the
    research and workflow views). The outline kit maps a place inside a whole
    row that no slot holds to the record, so a press on a mark or a gap names
    the record, as the kit says. A plain click on a text that the view drew in
    the row, such as the time of an item, then named the record, not a caret.
    `map_outline_backward(slots, reference; introduce)` now asks `introduce`
    first: `make_outline_row_text_reference` answers the step of the view at
    the record for a caret in a text that the view drew, or for that text as a
    whole, a `String` of the output, which an Alt+click gives after the
    container made the caret whole; for any other place it answers `nothing`,
    and the place maps to the record as before. The view maps such a step
    forward to its place in the output (`find_outline_introduced_path`,
    `map_outline_view_forward`), also for the routing of the selection, so the
    caret is drawn. The research view and the workflow view use them.
  - ~~**A chip is a control**~~. A label with bindings of its own, such as the
    chip of a link that selects the item it names, acts on a plain click, and
    its text takes no caret from a move, an Alt+click or a point
    (`_is_bound_control`), so the move and the Alt+click name the chip as a
    whole, which the outline maps to the record. The click test takes a press
    that selects a document and shows it (`ShowSelectionOperation`) as an
    action.
    The walk: `examples/research_contested` 114 → 19, `examples/research`
    103 → 12, `workflow/workflow` 24 → 19, `examples/workflow_recorded` 53 →
    47; `test_research` 386, `test_workflow` 314, `test_outline` 34 pass.
  - ~~**The caret in a text field of a plain value maps forward to nothing**~~
    (most of the 427 lines of `plain:caret-not-drawn` in run 2: the titles and
    the fields of the workflow and research items). The caret was drawn, by the
    routing of the selection into the text view of the field, but the forward
    map of a `WidgetText` that shows a `String` went only into a document of
    `content`, so the forward map of the editor answered `nothing` for the
    caret, and a scroll to the selection or the click test could not find it.
    The field maps `.content{s:e}` to the flat range of the text of its view,
    and `.content` to that text as a whole, through the IO map of the view
    (`_map_plain_text_forward`), the inverse of `_map_plain_text_reference`.
    The walk: `workflow/workflow` 24 → 0, `examples/workflow_recorded` 53 → 4,
    `examples/research_planned` 104 → 5, `mcplog/log` 10 → 5. Left: the names
    of `examples/formula_report` (20) and the object view of
    `examples/nested_object_to_widget` (8).
  - ~~**The forward map of a text of Markdown and RST throws**~~. The leaf of a
    text spliced the rest of the input path into a typed literal
    (`@reference ::SyntaxLeaf.value::TextString.^(rest)`), and a caller can give
    the path with no types, so the map threw "under-typed @reference": the walk
    of `assistant/work` and `examples/assistant_work` stopped in run 2, and the
    caret in a heading of `examples/formula_report` had no image. The two leaves
    build the range again in the types of the output, as the primitive leaves
    do. The leaves of an image and of a book read their own stored selection,
    which is typed, and stay. The walk: `examples/formula_report` 20 → 8,
    `assistant/work` and `examples/assistant_work` walk again (29 and 30 lines,
    47 and 57 in run 1); `test_markdown` 289 and `test_rst` 130 pass.
  - ~~**The reflected object of a `Dict` throws**~~ (`explorer/explorer`). The
    view left out a slot that holds nothing yet only in an `Array`, and a
    `Memory`, such as the keys of a `Dict`, is an array that is no `Array`, so
    the view read an unfilled slot and threw `UndefRefError` after a press in
    the explorer. It asks `isassigned` of every `AbstractArray` now. The walk
    of `explorer/explorer` presses all its 43 points with no throw.
  - ~~**The caret in a field of a form maps forward to nothing**~~
    (`examples/nested_object_to_widget`, the object view). A field of the form
    holds an `ObjectField`, whose child gives the value that the text field
    shows, and the forward map of the field went into the child, which gives a
    value and no graphics. The forward map of a text field asks that child for
    the flat range of the value now, as the backward map does
    (`_map_shown_text_forward`, which the plain value uses too). The walk:
    `examples/nested_object_to_widget` 21 → 13, `examples/object_to_widget`
    3 → 2, `examples/chart_inspector` 42 → 39, and no caret that is not drawn
    is left in them.

  **Run 3 of step 6** (2026-11-13, at 34ce4b933, the same 546 examples): 2396
  lines in 281 examples (run 2: 3209 in 300; run 1: 6164 in 343). By kind:
  `plain:no-caret` 723 (1182 in run 2), `alt:not-drawn` 619, `move:differs`
  406, `alt:outside` 295, `alt:not-caret-part` 236, `throws` 39, `no-image` 37,
  `plain:caret-not-drawn` 29 (427). The largest causes left: a plain click on
  a text gives a part (62 examples, 404 lines: chart axes, the cells of the
  frame statistics, the columns of a table, the dimensions of a pivot); a plain
  click does nothing (67, 232); the Alt+click outside the deepest part (45,
  260); the reflected object (50, 153: the half of a quote, D8); the leaf of a
  view (37, 152); the value in a leaf (14, 188).
  - **A value that a widget draws as a text takes the caret** (my reading of
    D1). The label, the badge, the avatar, the alert, the fact group and the
    card recorded the line of a text only when the value was a `String`; a
    label of a number gave no caret. They record the line of every value that
    they draw as a text, which is no document and no picture
    (`_is_drawn_value`); an image and the icon of an avatar record none. The
    walk does not change on the examples with numbers that fail: there the
    numbers are the tick labels of the axis of a sequence chart, which the
    chart draws itself, and the field chips of a pivot, which choose their
    field as the row of a list does; those are causes of the chart and the
    pivot. `test_dataframes` 616 and 13 widget, table and task sets pass;
    `test_pivot` fails at `PivotModuleTest.jl:21`, `:23` and
    `PivotZoneEditTest.jl:84`, as main 31f04235c does.
  - **Found:** `test_pane_reader` expected the label for an Alt+click on the text
    of a label, which e7ff5e058 changed (P8); its two test sets now expect the
    text of the label and its band, and the ring for the label as a whole.
- [x] 6a. **The gestures of D10.** One commit for each part, in this order:
  1. The gesture rules in the focus slice: an Alt+click is a caret press, an
     Alt+double click a whole selection press (`is_whole_selection_press`), and
     each reader that makes an Alt+click whole today makes an Alt+double click
     whole; an Alt+click answers the caret at the character, also on a control.

     Done in the work (2026-11-13): `is_caret_press` (an Alt+click, count 1),
     `is_whole_selection_press` (an Alt+click of count 2 or more),
     `is_selection_press`, and `convert_to_caret_selection`, which keeps the
     selection that a child answered and drops an action, so a caret press
     never acts. `read_child_event`, which every container passes a press
     through, answers a caret press by it. The label, the badge, the avatar and
     the alert read no binding on a selection press, so a chip takes the caret
     on an Alt+click; the card and the fact group answer the caret to both
     presses; the toolbar item declines both. The tables: an Alt+double click
     selects a cell, a header or the corner whole, and an Alt+click gives the
     caret in the text of the part, also in the label of a header
     (`_find_control_answer` keeps the caret on a caret press) and drops an
     action. The comments, the welcome text of the application and the texts
     of the picture of the assistant name the new gestures. A plain arrow on a
     part selected as a whole navigates the tree of a code view today, as an
     Alt+arrow does; part 3 changes it.

     A tree reads no binding on a press that selects, and the chevron of its row
     opens or closes nothing then: a binding pattern with no modifiers matches
     every modifier, so the double click that opens the file of a row of the
     Files pane answered the Alt+double click, and the container made the whole
     explorer of the answer. The controls (checkbox, button, link, menu item,
     switch) still answer their action, which the container drops.

     The tests follow: 25 files press an Alt+double click where they selected a
     part whole. Where a test selected a JSON string or a code name whole, it
     now presses Alt+Up after the Alt+double click, because the double click
     selects the value in the leaf (P8), as the Alt+click did before. The
     transcript test accepts the turn for a plain click in the padding of the
     card of a turn (D4); it failed so before this part too.

     Results: 16 platform sets pass (`test_widget_tree` 103, `test_document_tree`
     135, `test_pane_reader` 155, `test_syntax_to_text` 346,
     `test_widget_table_list` 258 and 11 more); `test_clipboard_edits` 34,
     `test_table_navigation` 67, `test_text_range_selection` 41,
     `test_data_frame_paths` 19, `test_data_frame_cells` 176,
     `test_pivot_table_projection` 43 and `test_part_picture` 13 pass;
     `test_application` fails only at `ApplicationTest.jl:1013` (the usage text
     of the agent bar) and `test_history_sweep` only at `HistorySweepTest.jl:111`
     (the palette step), both known failures.
  2. The click test of step 1: a plain click acts or puts the caret; an
     Alt+click puts the caret on every text; an Alt+double click selects the
     innermost part; a move names the part of the Alt+double click.

     Done in the work (2026-11-13): `_pc_check_point!` presses a plain click, an
     Alt+click and an Alt+double click (`_pc_double_press!`, two presses 0.05 s
     apart) at each point. A plain click on a text fails when it does nothing,
     selects outside the document or puts the caret outside the text; an
     Alt+click fails when it acts or gives no caret; the Alt+double click keeps
     the checks of the innermost part, and the move is compared with it. The
     run over the catalog follows part 3.
  3. A plain Left or Right on a part selected as a whole: the caret at its start
     or its end, or, on a part with no meaningful caret, the sibling.

     Done in the work (2026-11-13): the rule is in the text, not in each
     domain. A whole part in a text block is `∅` on the block or a
     `TextSpanReferenceStep(a, b)`, a flat range of characters, so the motion
     of the caret (`_text_char_motion`) collapses it to its start or its end as
     it collapses a range (`_find_whole_flat_range`); a whole part with no
     character declines. In the graphics pipeline the text reads the key first.
     In the console pipeline the syntax table reads it first and the text is
     its fallback, so the plain arrow rule of `SyntaxCompound` declines a Left
     or a Right on an element that renders a character (`_find_selected_node`,
     `_has_rendered_text`), and both pipelines follow one rule. Plain Up and
     Down on a whole element still move in the tree. The tables keep their
     grid keys (D9). Rejected: the caret at the first leaf of the element
     (`_descend_to_text_cursor`), which puts it after the opening quote and
     not at the start of the part. The probe on `json/object/natural`: a
     whole quote, key, entry and root give `.open{0}` on Left and the end of
     their text on Right, where the sibling and nothing were before. The
     tests follow: `SyntaxToTextTest` expects the caret, an element with no
     character moves to its sibling, and the tree walks press Alt+Left and
     Alt+Right; `ConsoleBackendTest` presses Alt+Right (`ESC [ 1 ; 3 C`) to
     step to the sibling.

     **Found (D9):** a plain click on a line that the program of a terminal
     wrote gave the caret in the label of the line since 8f7439489, which is on
     main, so the keys went nowhere and `test_assistant_composer_panel` failed
     at `ConversationPanelTest.jl:220`. The terminal has a more useful plain
     click: the keys go to its input line. Its 4-arg reader keeps it: a plain
     click that a text outside the input line answers with a selection gives
     the caret at the end of the input line, and an Alt+click keeps the caret
     in the line, so a person can copy it.

     Results: `test_syntax_to_text` 346, `test_text` 170, `test_console_backend`
     143, `test_terminal` 53, `test_json` 251, `test_sql` 671,
     `test_assistant_composer_panel` 99, `test_text_range_selection` 41,
     `test_table_navigation` 67, `test_xml_construct` 10, and the JSON and YAML
     construct sets with their 2 known broken each pass; `test_julia` fails
     only at `TooltipWindowTest.jl:179` and `test_platform_layering` only at the
     10 entries that main has.
  4. The guides: `keyboard-and-mouse-guide.md` (the lines of Alt and the
     arrows, Alt+click), `gestures-guide.md`, and the package guides of the
     widget, the text, the selection and the focus.

     Done in the work (2026-11-13): the user guides list the click, the
     Alt+click, the Alt+double click, Alt+Up and Alt+Down, Alt+Left and
     Alt+Right and the plain arrow on a whole part, with one paragraph of the
     idea; `gestures-guide.md` has the section "Three clicks"; the guides of
     the focus, the layout, the widget, the text and the syntax describe the
     predicates, `read_child_event` and the key rules; 14 more package guides
     name the Alt+double click where they mean a whole selection.
     `selection.md` describes no click, so it stays.

  Run 4 of the click test of D10 over the catalog (2026-11-13, scratchpad
  `step6/run4`): 3194 lines in 301 of 546 examples. The kinds changed with
  the test, so they compare with run 3 only in part:

  | Kind | Lines | Where most |
  | --- | --- | --- |
  | An Alt+click gives no caret | 968 | the text of a control: a button, a menu name, a toolbar item, a segment, the + and − of a stepper, a tab title; and the math views |
  | An Alt+double click selects a part that no ring or band draws | 612 | widgets, panes, the explorer, versions, state machines |
  | The move names another part than the Alt+double click | 611 | |
  | The Alt+click caret is not in the part of the point | 351 | |
  | The Alt+double click selects outside the innermost part | 295 | |
  | A plain click on a text does nothing | 232 | tasks, math, widgets, research |
  | A throw, no image, a caret not drawn or off | 119 | |

  The next cause is the first row: each control records the line of its
  text, as a label does, so an Alt+click finds the character (D10).

  **Paused (owner, 2026-11-13):** "just having the caret is not very good,
  can't navigate with cursor, cannot select a range, cannot copy-paste. We
  should reconsider the plans. This would be desirable to have but we should
  not reinvent the text domain everywhere." The caret in a widget text takes
  no key of the text domain. The work on the controls stops; stash
  `3f8923c5d` holds the caret in the label of a button (`_build_button`,
  `_read_control_caret`, its test). The assistant recommends (asked, not yet
  answered): one plan in which a widget text that holds the selection draws
  through a text view, as the name of a tab does while it is renamed
  (`_print_tab_name_view`), so the keys, a range and a copy come from the one
  text domain; the records of the drawn lines only find the character under
  a press. The other way: no caret in a widget text, and an Alt+double click
  selects the text as a whole.

  The landing of 2026-11-13 (main 55e3de361, not pushed) holds steps 6a and
  the causes before it. The omnet follow-up of the Alt+double click is on the
  omnet branch `innermost-click` (b8a8d2c21), not landed.
- [ ] 7. **The omnet views.** Remove the maps that answer the whole page or
  `nothing`; a value that a field holds maps to its field; the result table
  picks a row on a plain click only. One commit for each group of views.

  Done so far (2026-11-10, omnet-julia `98367a408` and the cleanup after it):
  15 views of the presentation (in 14 files) had the one-line forward map by
  `find_introduced_path`, and they use the default forward map now, which maps
  the whole document of the view to its whole output; a view that extends the
  forward map no more does not import it. The atom tests, against step 3: IDE
  197999 pass and 14 broken, cosim 32189 and 422, presentation 1416927 and
  1174, legacy 768123 and 516; no Fail and no Error. The other omnet views of
  the list of step 4 lose the whole document in maps of their own.
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

- An Alt+double click on a tab title of a group without the focus brings back an old
  selection; the fix needs a sealed kernel file (`pane.md:290`).
- An edge of a graph is a decoration by design (`graph.md:88`); the test
  reports it, and the owner decides.
- The Alt+click and the move on the half of a character beside the edge of a
  part, such as the inner half of a quote, name the part of the caret and not
  the character under the pointer (D8: deferred, to be done eventually). The
  work, which step 6 found: the text view answers the range of the character
  under the point; the syntax text maps a range in a delimiter of a leaf or a
  node of its own back to that field; `find_whole_part` reads a range of one
  character of a text in the output path of a view as a place; the click test
  reads such a range as a place.
