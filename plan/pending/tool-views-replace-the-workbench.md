# Tool views replace the workbench

> **Status (2026-09-17): NOT STARTED.** No step is done. Every fact in
> section 2 was checked against the source on this date.

**Goal.** A person opens an empty tab, presses Insert, types a name, and gets a
working tool. Six tools answer to a name: a log, a read-eval-print loop, a
selection display, the gesture log, a file explorer, and an assistant. Each one
can be opened as many times as the person wants. The whole user interface then
saves to a `.pred` file and opens again from it. The workbench domain goes away.

**Repository.** projectured-julia only. The plan changes no sealed file.

**Branch.** `tool-views`, in a worktree beside the checkout.

## 1. The request

> I want the flexibility of the pane based one. […] how can a user select from
> existing views when instantiating a new tab: for example, gesture log view, a
> new assistant (if all is closed), a new file explorer (if all is closed), etc?
>
> A log view which captures log statements. A repl which allows Julia
> expression evaluation. A selection display showing the human readable view of
> the current selection. The gesture log view. A file explorer. An assistant.
>
> These are components which should be instantiatable at least using the
> document insertion method. Then we can drop the workbench.
>
> We also need to be able to save the whole document of the editor into a pred
> file recursing into other files as already implemented for being able to
> restore the UI.

The rulings that follow from it:

| Question | Ruling |
| --- | --- |
| How does a person choose a view? | The document insertion. `Ctrl+T`, Insert, a name, Enter. |
| Is the insertion the only way? | It is the one that must work. Another way can come later. |
| Is a tool a single instance? | No. A person opens as many as they want. |
| What happens to the workbench? | It goes away. |
| What must survive it? | The file explorer, and the file tab that carries a file name. |
| What does a saved user interface hold? | The whole editor document, with a reference to each open file, not a copy of it. |

## 2. What exists

### The insertion already runs, up to one point

| Fact | Where |
| --- | --- |
| `Ctrl+T` opens a tab that holds a `DocumentNothing`, and puts the cursor **on the placeholder**, not on the tab. | [PaneSurgery.jl:385-388](../../source/pane/PaneSurgery.jl#L385-L388) |
| Insert on a selected `DocumentNothing` emits a fresh `DocumentInsertion` with the cursor in its buffer. | [Domain.jl:506](../../source/domain/Domain.jl#L506), [Domain.jl:395-397](../../source/domain/Domain.jl#L395-L397) |
| A leaf projection with no reader of its own hands a raw key to `read_gesture` of its input document. This is how the Insert key reaches the placeholder through any projection. | [ProjectionDefaults.jl:120-133](../../source/kernel/projection/ProjectionDefaults.jl#L120-L133) |
| The candidate list is every insertable concrete document type under `Document`, computed by reflection and memoized on the world counter. Nothing is registered. | [Domain.jl:232-250](../../source/domain/Domain.jl#L232-L250) |
| A candidate is insertable when it takes no argument, or when it has a `make_insertion_document` method. | [Domain.jl:184-192](../../source/domain/Domain.jl#L184-L192) |
| A candidate answers to its type name, to the same name in words, and to any `get_insertion_aliases`. | [Domain.jl:268-278](../../source/domain/Domain.jl#L268-L278) |
| `complete_insertion` classifies the buffer as empty, invalid, ambiguous or unambiguous, and gives the continuation. `resolve_insertion` commits an exact name or a single prefix match. | [Domain.jl:328-340](../../source/domain/Domain.jl#L328-L340), [Domain.jl:374-382](../../source/domain/Domain.jl#L374-L382) |
| `DocumentInsertionToSyntaxLeaf()` draws "Insert a new ⟨name⟩ here", paints the buffer, and commits through `default_factory`. | [InsertionToSyntax.jl:325-331](../../source/syntax/InsertionToSyntax.jl#L325-L331) |
| **`DocumentInsertion` has no row in the to-syntax fabric.** It falls through to `Any` and `ObjectToSyntax` reflects it as a struct with a `value` field. So the buffer draws wrong and Enter commits nothing. | [SyntaxNatural.jl:33-51](../../source/syntax/SyntaxNatural.jl#L33-L51) |
| `DocumentNothing` draws as the static phrase "empty document" in the natural renderer, and never reaches its own placeholder leaf. A phrase maps no reference back, so a click cannot select it. | [NaturalProjection.jl:145-147](../../source/natural/NaturalProjection.jl#L145-L147), [SyntaxNatural.jl:44-47](../../source/syntax/SyntaxNatural.jl#L44-L47) |

### The six tools

| # | Tool | Type | No argument? | Own projection | Registered where | Title |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | log | **none exists** | — | — | — | — |
| 2 | read-eval-print loop | `EvaluatorToplevel` [Evaluator.jl:171](../../source/conversation/Evaluator.jl#L171) | yes | **none exists** | nowhere | no |
| 3 | selection display | `ReferenceInspector` [ReferenceInspector.jl:4](../../source/inspector/ReferenceInspector.jl#L4) | yes | `ReferenceInspectorToText` | `example/projectured/Gallery.jl:575` only | no |
| 4 | gesture log | `GestureLog` [GestureLogDocument.jl:19](../../source/gesturelog/GestureLogDocument.jl#L19) | yes | `GestureLogToSyntax` | nowhere; reachable only inside the overlay decorator | no |
| 5 | file explorer | `Workspace` [Workspace.jl:16](../../source/workbench/Workspace.jl#L16) | yes | `WorkspaceToFileSystem` converts only | `example/projectured/Application.jl:150` only | no |
| 6 | assistant | `Assistant` [AssistantDocument.jl:86](../../source/assistant/AssistantDocument.jl#L86) | yes | `AssistantToWidgetSplitPane` | the `WorkbenchToWidget()` table only | no |

Five of the six already take no argument, so the insertion already offers them.
Typing `assistant` and Enter today makes a real `Assistant()`. The tab then
draws it through the `Any` row as a reflected struct, because no natural row
claims it. **The insertion is not the work. The rows are the work.**

More facts about the six:

| Fact | Where |
| --- | --- |
| No document type in `source/` defines `get_document_title`. Only the default exists, and three methods in omnet-julia. | [PaneProgram.jl:269](../../source/pane/PaneProgram.jl#L269) |
| A tab with an empty name is called after `get_document_title` of its content, and "untitled" when there is none. | [PaneDocument.jl:70-76](../../source/pane/PaneDocument.jl#L70-L76) |
| `WorkbenchConsole` holds a `TextBlock` and **nothing writes to it**. It is an inert panel, not a log. | [WorkbenchDocument.jl:87-89](../../source/workbench/WorkbenchDocument.jl#L87-L89) |
| `WorkbenchEvaluator` holds `content::Any = nothing` and is wired to nothing. | [WorkbenchDocument.jl:158-160](../../source/workbench/WorkbenchDocument.jl#L158-L160) |
| The Julia evaluator is a function, not a document: `execute_julia_code(set, target, code)`. The assistant and the transcript both call it and wrap the answer in an `EvaluatorForm`. | [CodeExecution.jl:157](../../source/kernel/tool/CodeExecution.jl#L157), [AssistantTurn.jl:52-58](../../source/assistant/AssistantTurn.jl#L52-L58), [ConversationEditor.jl:349](../../source/conversation/ConversationEditor.jl#L349) |
| `EvaluatorForm` needs a `form` positionally, so it is not a candidate. `EvaluatorToplevel` is a sequence of them and takes no argument. | [Evaluator.jl:35-59](../../source/conversation/Evaluator.jl#L35-L59), [Evaluator.jl:171-173](../../source/conversation/Evaluator.jl#L171-L173) |
| `ReferenceInspector` is filled by the hover probe, which opens a follower window. It does not read the editor selection. | [HoverProbe.jl:110-117](../../source/inspector/HoverProbe.jl#L110-L117) |
| The gesture log is filled by `GestureLogOverlayProjection`, which also draws it. A tab view needs the record step without the draw step. | [GestureLogOverlay.jl:55-129](../../source/gesturelog/GestureLogOverlay.jl#L55-L129), [GestureLogRecording.jl](../../source/gesturelog/GestureLogRecording.jl) |
| A slice registers its own natural row from its `__init__`. The file system slice already does it. | [FileSystemToSyntax.jl:221-223](../../source/filesystem/FileSystemToSyntax.jl#L221-L223) |
| The two registration seams are `register_natural_syntax!(key, factory)` and `register_natural_graphics!(key, factory)`. | [NaturalRegistry.jl:73](../../source/natural/NaturalRegistry.jl#L73), [NaturalRegistry.jl:87](../../source/natural/NaturalRegistry.jl#L87) |
| The natural table takes the registered rows before its own abstract rows, and `extra` before everything. First match wins. | [NaturalProjection.jl:120-164](../../source/natural/NaturalProjection.jl#L120-L164) |
| The printer context carries a reference, an extent, a property table and a clock. **It does not carry the editor document.** `with_property(ctx, key, value)` and `get_property(ctx, key, default)` write and read the table. | [PrinterContext.jl:26-32](../../source/kernel/projection/PrinterContext.jl#L26-L32), [PrinterContext.jl:156-175](../../source/kernel/projection/PrinterContext.jl#L156-L175) |
| The editor mints the root context with its own clock and nothing else. | [EditorModule.jl:253-258](../../source/kernel/editor/EditorModule.jl#L253-L258) |
| A reactive field of a `@document` struct auto-wraps its argument with `Cell(x)`, and `Cell(f::Function)` makes `f` the cell's **thunk**. The field then re-derives its value from `f` whenever something it reads changes. | [ReactiveCell.jl:85-96](../../source/kernel/cell/ReactiveCell.jl#L85-L96) |
| Neither `EditorModule.jl` nor `PrinterContext.jl` is sealed. | [SEALING.md:150](../../SEALING.md#L150) |

### The workbench

| Fact | Where |
| --- | --- |
| `WorkbenchOperator` and `WorkbenchSearcher` are empty structs. Their printers draw an empty scroll pane. | [WorkbenchToWidget.jl:311-322](../../source/workbench/WorkbenchToWidget.jl#L311-L322) |
| Eight source files outside `source/workbench/` name the workbench. Every one of them names it in a comment, not in code. Several of those comments are history, which the project rule forbids. | `source/assistant/`, `source/mcp/`, `source/component/`, `source/conversation/`, `source/dragging/`, `source/widget/`, `source/natural/`, `source/fileformat/` |
| The pane window still routes three types through `WorkbenchToWidget`: the file tab, the navigator and the assistant. | [Application.jl:186-193](../../example/projectured/Application.jl#L186-L193) |
| `WorkbenchNavigator` only wraps a `Workspace` and gives it the title "Navigator". Its printer puts the raw workspace in a scroll pane. | [WorkbenchToWidget.jl:264-269](../../source/workbench/WorkbenchToWidget.jl#L264-L269) |
| `WorkbenchEditor(title, filename, content)` is the file tab, and it serves the pane tree too. `OpenWorkspaceFileOperation` opens a file into either window. | [WorkbenchFile.jl](../../source/workbench/WorkbenchFile.jl) |
| Three packages and about twenty files carry the workbench: `ProjecturedWorkbench`, `ProjecturedWorkbenchExample`, `ProjecturedWorkbenchTest`. | `package/`, `example/workbench/`, `test/workbench/` |

### The file format

| Fact | Where |
| --- | --- |
| A `.pred` file holds one document written as its own constructor. | [PredFile.jl:1-21](../../source/serialization/PredFile.jl#L1-L21) |
| `register_pred_type!(T)` is the gate. It keys the schema name and `nameof(T)`. An unregistered type is a hard error at save and at load. | [FileProject.jl:259-264](../../source/serialization/FileProject.jl#L259-L264), [PredFile.jl:158-161](../../source/serialization/PredFile.jl#L158-L161), [PredFile.jl:257-259](../../source/serialization/PredFile.jl#L257-L259) |
| Only `FormulaFormula` and `FormulaEnvironment` are registered today. No pane type, no screen type, no tool is. | [FormulaModule.jl:52-53](../../source/formula/FormulaModule.jl#L52-L53) |
| `pred_arguments(document)` writes every field but `selection` as a keyword. `make_pred_document` is its inverse. A type whose file form is reduced overrides both. | [PredFile.jl:96-118](../../source/serialization/PredFile.jl#L96-L118) |
| **The recursion into other files is implemented.** `save_project!` cuts a `FileDocument` child to a `file("a.json")` leaf, a node another file owns to `node(file("a.json"), "path")`, and a repeated node to a self reference. An unowned node aborts the save. | [FileCut.jl:164-184](../../source/serialization/FileCut.jl#L164-L184), [FileCut.jl:261-272](../../source/serialization/FileCut.jl#L261-L272) |
| `load_project(dir, names; follow = true)` opens every file a marker names and splices each leaf back to its target. A marker outside the set stays a plain leaf. | [FileSplice.jl:53-75](../../source/serialization/FileSplice.jl#L53-L75), [FileSplice.jl:152-183](../../source/serialization/FileSplice.jl#L152-L183) |
| Eight `FileDocument` types exist, one per extension, each with a `filename` and a `content`. Every domain registers its own. | [FileProject.jl:52](../../source/serialization/FileProject.jl#L52), `JsonFile`, `XmlFile`, `JuliaFile`, `MarkdownFile`, `RstFile`, `MathFile`, `TextFile`, `PredFile` |
| The editor root chain is `ScreenDocument` → `windows[i]::WindowDocument` → `content::PaneTree` → `root::PaneSplit` or `PaneGroup` → `tabs[i]::PaneTab` → `content`. A clipboard wrapper can sit above the tree. | [ScreenDocument.jl:5-51](../../source/screen/ScreenDocument.jl#L5-L51), [PaneProgram.jl:171-179](../../source/pane/PaneProgram.jl#L171-L179) |

## 3. Decisions

### D1. A tool view is a document that registers its own natural row

A tool draws in a tab because its own slice told the renderer how, from its
`__init__`, the way the file system slice already does. No application wires a
tool, and no table names one. A person who loads the package gets the tool.

**Rejected:** keep the rows in `example/projectured/Application.jl`. An
application is then the only place a tool works, and a second application
repeats the list.

### D2. The insertion is the entry point

`Ctrl+T`, Insert, a name, Enter. Nothing else is needed for this plan. The
command palette can open a tool later; it runs a gesture binding, and a binding
that opens a tool is one line. That is a separate plan.

### D3. A tool is never a single instance

A person opens two file explorers, three gesture logs, and as many assistants
as they want. A copy through the clipboard gives an independent one, and a note
gives the same live one in two tabs. Both already work.

"A new assistant if all is closed" asks a different question: how does a person
**reach** the assistant that is already open. A tab switcher answers that, and
it is a separate plan.

### D4. A file tab holds a `FileDocument`

`WorkbenchEditor` goes away. A tab that shows a file holds the `FileDocument`
of that file — a `JsonFile`, an `XmlFile`, a `JuliaFile`. Three things follow at
once:

1. The file name lives on the document that owns it, not beside it.
2. `Ctrl+S` is `save_file!(file, directory)`, and `Ctrl+O` is `load_file`.
3. **The user-interface save writes `file("a.json")` for that tab**, because the
   cut already turns a `FileDocument` child into a file marker. A saved layout
   therefore holds a reference to each open file, not a copy of it. This is the
   whole reason the last requirement needs no new mechanism.

A `FileDocument` has no projection today. One `@projection_template` that draws
`content` and maps references through it serves all eight.

### D5. Transient state and secrets never reach the file

`pred_arguments` writes every field but `selection`. Three documents must write
less:

| Document | Field | Reason |
| --- | --- | --- |
| `PaneTree` | `drag` | A drag in progress is not layout. |
| `Assistant` | `api_key` | **A key must never be written to a file.** |
| `Assistant` | `llm`, `status` | A live connection is not data. |
| `GestureLog` | `entries`, `count` | A log of the last session is not the next one. |
| `SelectionInspector` | `source`, when it is a computed cell | The notation cannot write a computation. The save writes the reference the cell last produced; see D8. |

Each writes a `pred_arguments` method and a `make_pred_document` method that
rebuilds the dropped field. The assistant reads its key from the environment
again on load, as it does on a fresh start.

### D6. The workbench goes away entirely

`Workspace`, `WorkspaceFolder` and `WorkspaceToFileSystem` move to the file
system slice. `WorkbenchFile.jl` moves to the pane slice, without
`WorkbenchEditor`. Everything else is deleted: the four-page shell, the nine
panel types, `WorkbenchToWidget.jl`, and the three packages.

### D7. The names

A document is a noun. The alias is what a person types.

| Tool | Type | Aliases |
| --- | --- | --- |
| log | `MessageLog` (new) | `log` |
| read-eval-print loop | `EvaluatorToplevel` (exists) | `repl` |
| selection display | `SelectionInspector` (new) | `selection` |
| gesture log | `GestureLog` (exists) | `gestures` |
| file explorer | `Workspace` (exists) | `file explorer`, `explorer` |
| assistant | `Assistant` (exists) | — |

`MessageLog` does not collide with `GestureLog`, and both read as what they
are. `SelectionInspector` follows `ReferenceInspector`, which stays as the
hover probe's own document.

**Settled 2026-09-18.** The user accepted both new names.

### D8. The selection display takes its source as an argument

`SelectionInspector(source)` holds one field, `source`, which says **which**
selection to show. Its purpose is narrow: follow the selection of another
document. It is not a seam for arbitrary computation.

Three forms answer, and the field is an ordinary reactive field:

| Written as | Stored as | Read as |
| --- | --- | --- |
| `SelectionInspector()` | `nothing` | `nothing` — show the selection of the editor |
| `SelectionInspector(reference)` | the reference | a `Reference` |
| `SelectionInspector(() -> get_selection(other))` | **a computed cell**, the function its thunk | a `Reference`, re-derived |
| `SelectionInspector(other)` | the document | a `Document` |

**The computed cell is what makes the follow live.** Reading `inspector.source`
re-runs the function whenever anything it read changed, so the printer needs no
cell of its own for this form.

**Corrected 2026-09-18, measured.** The wrap is **not** automatic. The keyword
constructor stores a function as an ordinary value, and `view.source` then reads
back as the function — the view draws nothing, because a function is not a
reference. The positional constructor for a `Function` must put it in a
`ComputedCell` itself, and that is what makes the field answer a reference.

`find_inspected_selection(source, ctx)` therefore has three methods, one per read
form — `nothing`, `Reference`, `Document`. A function never reaches it. It
answers `nothing` when there is nothing to show, which is what a `find_` verb
promises.

**The document form reads its selection inside a cell.** That form stores a
document, not a computation, so the printer is the one that must re-derive.

**The editor puts its document in the root printer context.** `print!` mints the
root context with `with_property(ctx, :root, editor.document)`, and a `nothing`
source reads it back with `get_property(ctx, :root)`. This is one line in the
kernel, it breaks nothing, and a later tool that needs the root — a tab switcher,
for one — reads the same property.

**Rejected:** let the application set the source of every selection display. An
application is then the only place the tool works, which D1 forbids.

**A computed source does not survive a save.** `pred_arguments` forces the cell
and writes the reference it last produced, so the file holds a fixed reference
where the live document held a follow. A `Reference` source and a `Document`
source write and read unchanged, and the document form keeps following after the
load, because the splice gives the same document back. **Use the document form
for a follow that must survive a save.**

## 4. Steps

Each step is one commit. Run the named test before the commit.

### Step 0. The insertion draws and commits in a tab

**Status: mostly done, 2026-09-18.** `Ctrl+T`, Insert and the prompt work in a
tab. Two assertions are `@test_broken`: a printable key does not reach the name
buffer. The cause is named below.

**The two rows were not the whole of it.** They were necessary and they were
not enough. Three defects in the pane came out behind them, and two are fixed:

1. **A bare page element mapped back to the tab, not to its content.**
   `map_reference_backward` of `PaneGroupToWidgetTabbedPane` answered the
   `PaneTab` for `selector_element_pairs[i].element`, which names the tab's
   CONTENT. The Insert operation then wrote the new document over the `PaneTab`
   itself and took the layout with it. **Fixed.** A bare `[i]` is the tab, and
   `[i].element` is the content, whole.
2. **The `^` splice of `@reference` moves type checkpoints.** It hoists the
   spliced path's leading type onto the node before it and drops the interior
   ones, so `tabs[1]::PaneTab.content::DocumentInsertion.value{0}` came out as
   `tabs[1]::DocumentInsertion.content.value{0}`. A selection whose checkpoints
   moved matches no document. **Fixed** at the three backward maps of the pane,
   by `concat_references`, which carries a terminal type onto the node that
   follows it. The forward maps still splice; leave them until something proves
   they are wrong.

**What is still open, and what it is not.** A printable key does not reach the
name buffer. The cause is not the new rows, not the pane, and not the harness.
The project's own type-in walker says so:

    walk_typein(DocumentInsertion("js"), fabric)
      insert pos=0/2  → insert produced nothing, not ReplaceStringRangeOperation
      insert pos=1/2  → insert produced nothing, not ReplaceStringRangeOperation
      insert pos=2/2  → insert produced nothing, not ReplaceStringRangeOperation

**No insert works at any position of an insertion buffer, and `TextInsertion`
gives exactly the same three lines.** The walker reports no missing cursor, so
the caret is drawn; the text layer simply produces no edit for the value span of
an `InsertionToSyntaxLeaf`. Backspace and Delete behave the same.

`TextInsertion` ships, so either this works through some other chain, or typing
into an insertion buffer has no coverage and has been broken for some time. The
suite walks no example that holds a bare insertion, so nothing would have caught
it.

**This belongs to the insertion machinery, not to this plan.** Settle it before
Step 5, which needs a typed buffer for the read-eval-print loop. Start by asking
whether `InsertionToSyntaxLeaf` maps its document's `value{k}` caret forward
onto the value span it draws; `InsertionNothingToSyntaxLeaf` does that for its
label, and `InsertionToSyntaxLeaf` appears not to.
3. **A group printed with no tab never draws its first tab.** The standing iomap
   keeps the empty pane it printed. Reproduced on clean `main`, so it is older
   than this plan. The test starts from a group with one tab to step around it.
   Worth its own plan.

1. Add `DocumentInsertion => DocumentInsertionToSyntaxLeaf()` to
   `make_natural_to_syntax_dispatch` in
   [SyntaxNatural.jl](../../source/syntax/SyntaxNatural.jl).
2. Add `DocumentInsertion => fabric` and `DocumentNothing => fabric` to
   `_fallback_rows` in the same file. Both are exact rows, so they win over the
   abstract rows of the renderer.
3. Delete the `DocumentNothing => PhraseToGraphics(...)` row from
   [NaturalProjection.jl:147](../../source/natural/NaturalProjection.jl#L147), and
   the sentence in its comment that says the renderer never reaches the syntax
   row.
4. A session without the syntax package then draws no placeholder. Keep the
   phrase as the fallback's own tail row there, not as an abstract row.

**Test.** [test/projectured/editor/InsertionInTabTest.jl](../../test/projectured/editor/InsertionInTabTest.jl),
function `test_insertion_in_tab()`. It opens a tab with `Ctrl+T`, sends Insert,
sends the characters of a name, sends Enter, and asserts what the tab holds and
what it draws. One standing iomap serves the whole sequence, as a live editor
keeps it: a fresh print for each step would hide a reuse bug, which is the class
of bug this test found. 5 pass, 2 broken.

### Step 1. Four tools register their own row

**Status: three done, 2026-09-18.** The assistant, the gesture log and the
reference inspector each register from their own `__init__`. `Workspace` waits
for Step 8, which moves it to the file system slice — that slice already
registers a row and already depends on the natural package, so the file explorer
costs nothing there and a dependency added to the workbench now would be thrown
away.

The duplicate rows in `example/projectured/Gallery.jl` and
`example/projectured/Application.jl` are **not** removed yet. An `extra` row
still wins over a registered one, so both applications draw exactly as before.
They go in Step 8, with the workbench stage they are tangled with.

Two packages gained a dependency on `ProjecturedNatural`, and the inspector also
on `ProjecturedProjection`, because `ChainingProjection` was not reachable from
it. Run `Pkg.resolve()` after adding a dependency; `instantiate` alone does not
re-resolve.

**Test.** [test/projectured/projection/ToolViewTest.jl](../../test/projectured/projection/ToolViewTest.jl),
function `test_tool_views()`. It asserts each tool takes no argument, that the
renderer claims it rather than falling through to "no natural rendering", and
that the insertion resolves it by name. 9 pass.


Each slice registers from its `__init__`, with `register_natural_graphics!` for
a tool that draws widgets and `register_natural_syntax!` for one that draws a
tree.

1. `Assistant => AssistantToWidgetSplitPane()`, from `AssistantModule`.
2. `WorkspaceDocument => ChainingProjection(WorkspaceToFileSystem(), FileSystemToWidget(...), ...)`,
   from the file system slice after Step 8 moves it.
3. `GestureLog => GestureLogToSyntax()`, from `GestureLogModule`.
4. `ReferenceInspector => ReferenceInspectorToText()`, from `InspectorModule`.

Then delete the same rows from `example/projectured/Application.jl` and
`example/projectured/Gallery.jl`. A row in an application is a row that a
second application must repeat.

The file explorer needs a seed: `Workspace()` holds no folder, and an empty
explorer shows nothing. Give it
`make_insertion_document(::Type{Workspace}) = Workspace([WorkspaceFolder(basename(pwd()), pwd())])`.

**Test.** `test_natural_rows()`: build each of the four, print it through
`NaturalToGraphics`, and assert the canvas is not the "no natural rendering"
phrase.

### Step 2. The gesture log records without the overlay

**Status: done, 2026-09-18.** The split the step asked for already existed:
`GestureLogRecordingProjection` is a transparent decorator that records and draws
nothing, and the overlay's reader is a pure pass-through. What was missing was
**which** log fills.

A log a person opens by name is now the session's own log
(`get_session_gesture_log`), because a fresh empty one would never fill — what
records is a decorator at the root of the projection, and it records into the log
it holds. `GestureLog()` still builds an empty one, which a test wants.

The application installs the recorder at the root of its projection, so a tab
that holds a log fills without the window knowing that a tab holds one.

**Settled 2026-09-18.** Every gesture log shows the same gestures, because there
is one editor. Two logs are two views of one history, and they are literally the
same document. A filter that narrows what one view shows comes later, and it is a
filter over this log, not a log of its own.

**Test.** `test_gesture_log_in_tab()` in
[ToolViewTest.jl](../../test/projectured/projection/ToolViewTest.jl): a log
opened by name is the session's own, two opens give the same document, a log
built by hand is still empty, and a gesture the pane claims reaches the log.
5 pass.

### Step 3. The selection display takes its source

**Status: done, 2026-09-18.** All four forms work and the view follows a
selection that moves through a standing render. `SelectionInspector` lives in
the inspector slice beside `ReferenceInspector`, which stays as it is — it is the
hover probe's own document, it holds a reference and its target, and a projection
fills it rather than a source.

Two facts came out of the work:

- **A module takes one `__init__`.** The inspector slice owns two projections
  now, and a second `__init__` in a second file silently overwrote the first
  until precompilation refused it. Both rows are registered in
  `InspectorModule.jl`.
- **A computed source with no root shows `?` for a parent type.** The human
  readable form names each step's parent from the type checkpoints, and those
  come from the document the reference points into. A function does not say what
  document it read, so there is nothing to annotate against. That is honest: a
  person who wants the checkpoints uses the document form.

Add `SelectionInspector` to the inspector slice, per D8.

1. `@document struct SelectionInspector` with one field, `source::Any = nothing`.
   An ordinary reactive field: a function passed to it becomes the cell's thunk,
   which is what makes the follow live.
2. `find_inspected_selection(source, ctx)`, with the three methods of D8.
3. `SelectionInspectorToText`: a printer that reads `inspector.source`, runs
   `find_inspected_selection` **inside a `ComputedCell`**, then draws the two
   sections `ReferenceInspectorToText` already draws — the compact form and the
   human readable form. Reuse that projection; do not copy it. The cell is what
   keeps the document form live; the computed form re-derives on its own.
4. Change `print!` in [EditorModule.jl:253-258](../../source/kernel/editor/EditorModule.jl#L253-L258)
   to put the editor document in the root context under `:root`. That file is not
   sealed.
5. Register the row, and give the type its alias and its title.

`ReferenceInspector` stays as it is. It is the hover probe's own document, it
holds a reference **and** its target, and it is filled by a projection rather
than by a source.

**Test.** `test_selection_inspector()`, four cases, one per form:

- `SelectionInspector()` in a tab: move the selection twice, assert the text
  changes both times. This is the case that proves the `:root` property and the
  reactive read at once.
- `SelectionInspector(reference)`: assert the text names that reference and does
  not change when the selection moves.
- `SelectionInspector(() -> get_selection(document))`: write a new selection into
  `document`, assert the text follows it. Read `inspector.source` twice across
  the write and assert the two answers differ, which is what proves the field
  became a computed cell and not a stored value.
- `SelectionInspector(document)`: the same, through the document form.

Drive a real editor, not the printer alone. A direct read misses a reuse bug.

### Step 4. The log view

Add `MessageLog` to a new slice, `source/log/`. It holds `entries::CellVector`
and a `capacity::Int`, as `GestureLog` does. Install a Julia logger that appends
to it, and remove the logger when the document goes away.

`MessageLog` draws through the syntax fabric, one line per entry, newest first —
the same shape as `GestureLogToSyntax`.

**Open for the user.** A logger is global, so two `MessageLog` documents both
capture everything. That matches the gesture log, and I recommend it.

**Test.** `test_message_log()`: open a log, run `@info "x"`, assert the line is
in `entries`.

### Step 5. The read-eval-print loop

**Ruling (2026-09-18).** Code a person types goes straight to `eval`, and it can
call anything. There is no limit and no sandbox. `execute_julia_code` already
works this way: it parses with `Meta.parseall`, evaluates each top-level form
with `Core.eval` in a scratch module, and keeps the last value
([CodeExecution.jl:157-190](../../source/kernel/tool/CodeExecution.jl#L157-L190)).
The read-eval-print loop uses it and `editor.tools`, so a binding a person makes
is a binding the assistant sees, and back.

`EvaluatorToplevel` exists and holds a sequence of `EvaluatorForm`s. It needs
two things:

1. A projection that draws the sequence: each form's code above its result, the
   way the transcript draws an evaluation. Reuse the section card the
   conversation already builds.
2. A gesture: `Alt+Enter` evaluates the form the cursor is in, appends the
   result, and opens a fresh empty form below. Copy the shape of
   `ComposerEvaluateOperation`
   ([ConversationEditor.jl:340-367](../../source/conversation/ConversationEditor.jl#L340-L367)),
   which already does the whole thing: it calls `execute_julia_code`, keeps a
   `Document` answer live so it renders as itself, falls back to the printed text
   for any other value, and marks the form when the answer is an error.

The last form of a fresh `EvaluatorToplevel` must be an empty one, so a person
can type at once. Give it a `make_insertion_document` method that seeds it.

**Test.** `test_evaluator_toplevel()`: type `1 + 1`, send `Alt+Enter`, assert
the result document holds `2` and that a new empty form follows it.

### Step 6. Titles and aliases

**Status: done for the four tools that exist, 2026-09-18.** `Workspace`,
`MessageLog` and `EvaluatorToplevel` get theirs with their own steps.

| Type | Title | A person types |
| --- | --- | --- |
| `Assistant` | Assistant | `assistant` |
| `GestureLog` | Gestures | `gestures` |
| `ReferenceInspector` | Reference | `reference` |
| `SelectionInspector` | Selection | `selection` |

**`get_document_title` moved to the kernel.** It was declared in the pane slice,
so a slice that wanted to answer it would have had to depend on the pane. It is a
document trait, and it now sits with the other document-wide traits in
`source/kernel/document/DocumentInterface.jl`, which every slice already reaches.
`describe_document` stays in the pane: it says what a document *is* right now,
which is the pane's own question.

The gesture log and the inspector slices gained a dependency on
`ProjecturedDomain`, which is where the alias generic is declared.

Give each of the six a `get_document_title` method and a
`get_insertion_aliases` method, per D7. A tab then names itself after what it
holds, and a person types a short word instead of a type name.

**Test.** `test_tool_titles()`: for each of the six, assert
`get_pane_tab_title_string(PaneTab("", tool))` is the expected word, and assert
`resolve_insertion(Document, alias) === typeof(tool)`.

### Step 7. A file tab holds a `FileDocument`

1. Write one `@projection_template` that draws a `FileDocument` by drawing its
   `content`, and register it for `FileDocument` in the natural table.
2. Give `FileDocument` a `get_document_title` that answers `basename(filename)`.
3. Change `make_workbench_file_editor(path)` to `make_file_tab(path)`, which
   answers the `FileDocument` that `load_file` builds.
4. Move the `Ctrl+S` and `Ctrl+O` bindings from `WorkbenchEditor` to
   `FileDocument`, and make them call `save_file!` and `load_file`.
5. Move `OpenWorkspaceFileOperation` to the pane slice, and delete its workbench
   branch.

**Test.** Extend `test/projectured/editor/ApplicationTest.jl`: open every
format, save one, read it again, and assert the round trip.

### Step 8. The workbench goes away

1. `git mv source/workbench/Workspace.jl source/filesystem/Workspace.jl` and
   `WorkspaceToFileSystem.jl` beside it. Move their exports.
2. `git mv source/workbench/WorkbenchFile.jl source/pane/PaneFile.jl`, without
   `WorkbenchEditor`.
3. Delete `source/workbench/`, `example/workbench/`, `test/workbench/` and the
   three packages.
4. Delete the workbench rows from `example/projectured/Application.jl`, and the
   `:workbench` value of `APPLICATION_WINDOWS`. One window is left, so the
   parameter goes too.
5. Delete the comments that name the workbench in the eight files of section 2.
   They are history comments, which the project rule forbids.
6. Delete the workbench entries from `documentation/`, and write the tool views
   into [documentation/package/pane/pane.md](../../documentation/package/pane/pane.md).

**Test.** `test_package_graph()` and `test_application()`. Then load every
package once and read the import-time warnings: a clean load is not a migration
check.

### Step 9. The user interface saves to a `.pred` file

1. Call `register_pred_type!` for `ScreenDocument`, `WindowDocument`,
   `PaneTree`, `PaneSplit`, `PaneGroup`, `PaneTab`, `DocumentNothing`,
   `PrimitiveString`, and for the six tools. Each call goes in the `__init__` of
   the slice that owns the type.
2. Write the `pred_arguments` and `make_pred_document` pairs of D5.
3. Add `save_user_interface(editor, path)`: build a `FileProject` whose first
   file is the `PredFile` of the editor document, and whose other files are the
   `FileDocument` of every open file tab. Call `save_project!`.

The cut then writes each file tab as `file("a.json")` and writes the file beside
the layout. Nothing else is needed: the recursion already exists.

**Warning.** Do not save before `register_pred_type!` covers every type in the
tree. The save aborts with a `FileCutException` that names the first type it
cannot write, and writes no file. That is the intended behaviour, and it is the
test.

**Test.** `test_user_interface_file()`: build a tree with a file tab, an
assistant and a gesture log, save it, read the text, and assert that the file
tab is a `file(...)` marker and that no `api_key` appears anywhere in it.

### Step 10. The editor opens a saved user interface

Add `load_user_interface(path)`: `load_project(dirname(path), [basename(path)]; follow = true)`,
then take the content of the first file as the editor document. `follow = true`
opens each file a marker names, so every tab comes back with its file.

A marker that names a file that has moved stays a plain leaf, and the tab then
shows the marker text. Turn that into the empty placeholder instead, so a person
can retype the tab.

**Test.** `test_user_interface_round_trip()`: save a tree, load it, and assert
the layout, the titles and the content of each tab. Then move one file and
assert that its tab opens as a placeholder and that the rest is unharmed.

## 5. What this plan does not do

- The command palette does not open a tool. D2.
- A tab switcher does not exist. D3.
- The workbench console and evaluator are not ported. They hold nothing.
- `WorkbenchOperator` and `WorkbenchSearcher` have no replacement. They are
  empty structs that draw an empty box.
- The editor does not open the last saved user interface on start. Step 10 gives
  the function; a person calls it.

## 6. Test order

Run the narrowest test after each step. Run `test_pane()`, `test_syntax()` and
`test_application()` after Step 8, because it moves files between packages. Do
not run `test_all()`; it takes about 47 minutes.

Take a baseline first. A wide refactor needs a count from clean `main` to
compare against, or a pre-existing failure reads as a regression.
