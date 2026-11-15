# Architecture review: the diagram and data domains

Commit 3a9b4fae4. Reviewer area key: diagram-data-domains.

## Scope

Paths: `source/domain/{chart,sequencechart,graph,fsm,workflow,git,process,research,dbcatalog,database}`,
`source/adapter/{adaptagrams,tulip,odbc}`, `source/platform/plot`. The area holds about 25 800 lines of Julia.

**Read in full (about 3 200 lines of code):**
`ChartPlot.jl`, `ChartToChartPlot.jl`, `ChartSampleReferenceStep.jl`, `SequenceChartPlot.jl`,
`SequenceChartToSequenceChartPlot.jl`, `SequenceChartRowReferenceStep.jl`, `GraphDocument.jl`, `GraphLayout.jl`,
`GraphToGraphLayout.jl`, `GraphLayoutChoice.jl`, `GraphToWidgetScrollPane.jl`, `FsmDiagram.jl`, `FsmToFsmDiagram.jl`,
`FsmDiagramToGraph.jl`, `ProcessDiagram.jl`, `ProcessToProcessDiagram.jl`, `ProcessDebug.jl`, `ResearchMapToGraph.jl`,
`GitRead.jl`, `GitDocument.jl`, `GitRange.jl`, `DatabaseAdapters.jl`, `DatabaseDocument.jl`, `DatabaseInstance.jl`,
`DatabaseInstanceToDbCatalog.jl`, `SqlToCellTable.jl`, `ConnectionPool.jl`, `TulipModule.jl`.

**Read in part (about 2 400 lines), by the outline of the file and then the reader and the printer:**
`ChartPlotToGraphics.jl` (the printer, the reader, the view gestures, the menu, the buttons, the bars),
`SequenceChartPlotToGraphics.jl` (the same parts), `GraphLayoutToGraphics.jl` (the reader, the routing, the registration),
`ChartDocument.jl` and `SequenceChartDocument.jl` (the parts, the verbs, the gesture tables), `ProcessDiagramToGraph.jl`,
`ProcessDebugSession.jl`, `WorkflowToWidget.jl`, `WorkflowEdits.jl`, `ResearchToWidget.jl`, `ResearchVerbs.jl`,
`DbCatalogToSyntax.jl`.

**Sampled by grep only:** `PlotGeometry.jl`, `SequenceChartGeometry.jl`, `FruchtermanReingoldLayout.jl`,
`GraphLayoutEngine.jl`, `AdaptagramsLayout.jl`, `TulipConstraintSolver.jl`, `OdbcAdapter.jl`, the `*ToSyntax.jl` and
`*ToJuliaCode.jl` files of FSM and process, `GitParse.jl`, `GitText.jl`, `GitToWidget.jl`, `GitTree.jl`,
`ResearchDocument.jl`, `ResearchEdits.jl`, `ResearchFolder.jl`, `WorkflowDocument.jl`, `WorkflowList.jl`, the themes.

**Documents read in full:** `concepts.md`, `architecture-decisions.md`, the package documents of the ten domains,
`plot.md`, `graph-layout.md`, `odbc.md`, and the PAR sections on delegation, outside state, view state and
domains. **Plans read (head or the part that applies):** the six plans named for the area, and
`views-compose-as-content-composes.md`, `packages-compose-by-seams.md`, `a-click-reaches-the-innermost-part-in-every-view.md`,
and the done plans `a-view-document-keeps-the-state-of-one-view.md`, `a-chart-zooms-pans-and-fits-by-mouse-and-keys.md`,
`a-graph-keeps-its-view-when-you-edit-scroll-and-zoom.md`, `the-mouse-drags-a-vertex-of-a-graph.md`,
`chart-polygon-and-point-selection.md`.

I ran no Julia and no test. Every claim below comes from reading the code at the cited line.

## State

The area is sound in its large shapes. The state machine, the process and the map of a study draw through the graph
domain and add no drawing code. The two charts share their arithmetic in the plot slice, which is pure. The git domain
reads its outside state through background cells, shows its text through the text domain, its commits through the
roster and its changed files through the tree slice. This is the model that the first principles ask for.

The main weakness is that the newer mechanisms did not reach the older domains, so the same job has two or three
shapes. Outside state enters by a background cell in git, but by a query inside a computation on the loop in the
database adapter, and by a bridge that the host must call in the process domain. The state of a view lives in a view
document that the platform makes (`make_document_view`), in a view document that a hand-copied stage makes inside the
print (four copies here), and in fields on the content.

The second weakness is hand-written copies between sibling domains. The chart and the sequence chart copy the stage,
the gesture reader, the menu, the buttons and the navigation table. Three domains write the stage from their data to a
graph, and none of them keeps its vertices, so the places that a person gives are lost. Workflow and research copy the
IO map of the outline and walk their whole tree in one computation.

The third weakness is reach. Five of the ten domains have no view in the general renderer. The view gestures of the
charts and of the graph live in readers that the gesture help and the assistant can not list.

## Inventory

### 1. How each domain reaches the screen

| Domain | Chain | Output | Row in the general renderer |
| --- | --- | --- | --- |
| chart | `Chart` → `ChartPlot` → `GraphicsCanvas` | graphics directly | registry table, [ChartModule.jl:74](../../../source/domain/chart/ChartModule.jl#L74) |
| sequence chart | `SequenceChart` → `SequenceChartPlot` → `GraphicsCanvas` | graphics directly | none |
| graph | `GraphGraph` → `WidgetScrollPane` → `GraphLayout` → `GraphicsCanvas` | graphics in a widget pane; the content of a vertex through the recursion | registry table, [GraphLayoutToGraphics.jl:1241](../../../source/domain/graph/GraphLayoutToGraphics.jl#L1241) |
| FSM, notation | `FsmToSyntax` → text | syntax and text | none |
| FSM, diagram | `FsmMachine` → `FsmDiagram` → `GraphGraph` → graph stages | through the graph domain | none |
| process, notation and flowchart | as FSM | syntax and text; through the graph domain | none |
| workflow | `WorkflowNodeToWidget` → layout → graphics | widgets of the outline kit; roster for the list | registry table, [WorkflowModule.jl:65](../../../source/domain/workflow/WorkflowModule.jl#L65) |
| research, outline | `ResearchStudyToWidget` → layout → graphics | widgets of the outline kit | registry table, [ResearchModule.jl:74](../../../source/domain/research/ResearchModule.jl#L74) |
| research, map | `ResearchMap` → `GraphGraph` → graph stages | through the graph domain | registry table |
| git | widgets, the text domain, the tree slice, the roster | mixed | seam method `make_graphics_projection`, [GitToWidget.jl:524](../../../source/domain/git/GitToWidget.jl#L524) |
| dbcatalog | `DbCatalogToSyntax` → text; `DbCatalogToSql` → SQL documents | syntax and text | none |
| database, ODBC | `SqlToCellTable` → `CellTable` | a table document | none |

### 2. Interaction of each view

"table" means a gesture binding table. "reader" means a hand-written `read_intent`. "n.c." means not checked.

| View | Click selects | Hover lights | Drag | Zoom and pan | Keyboard move | Context menu | Tooltip | Edit in place | Listed by gesture help |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| chart | part, sample (reader) | series, crosshair | band zoom, pan (reader) | data window (reader) | parts (table) | yes (binding on `ChartPlot`) | own readout | hide, move, remove a series | table rows only |
| sequence chart | event, arrow, band, lane (reader) | event, arrow | band zoom, pan (reader) | time window, lane scroll (reader) | parts and trace (table) | yes (binding on the plot) | own readout | move, remove a lane | table rows only |
| graph | into the content of a vertex; an edge: no; a label: yes | vertex and its neighbours | moves a vertex (reader) | zoom of the layout by Ctrl+wheel only; scroll by the pane | to the content with the caret; no move from vertex to vertex | edge shape (binding on `GraphLayout`) | yes (table) | through the content; no add or remove | tooltip row only |
| FSM diagram, flowchart | as graph; the real state or step | live highlight | as graph, places lost | as graph | as graph | as graph | as graph | through the notation | as graph |
| research map | as graph, plus the row of the item | as graph | as graph, places lost | as graph | row keys | menu of the item | n.c. | text of the item | n.c. |
| workflow, research outline | caret in the text of a row | reveals the "⋯" | none | none | row keys (bindings on the row) | menu of the row | n.c. | yes | n.c. |
| git pages | caret (text domain) | n.c. | selects text | scroll pane | text domain | n.c. | yes (table) | none, by design | yes, [GitToWidget.jl:133](../../../source/domain/git/GitToWidget.jl#L133) |
| catalog tree | node (reader for each level) | n.c. | none | none | text domain | none | none | fold only | n.c. |
| SQL result | none: `read_intent` answers `nothing`, [SqlToCellTable.jl:47](../../../source/adapter/odbc/SqlToCellTable.jl#L47) | none | none | none | none | none | none | none | none |

### 3. Node and link diagrams

| Diagram | Through the graph domain | Content of a vertex | Vertex objects kept across a change | Reference map | Places that a person gave |
| --- | --- | --- | --- | --- | --- |
| `GraphGraph` as content | it is the graph | any document, by the recursion | yes | field pattern, [GraphToGraphLayout.jl:213](../../../source/domain/graph/GraphToGraphLayout.jl#L213) | `constraints` of the graph (an edit); kept starts in a `Ref` of the print |
| FSM diagram | yes | the `FsmState` itself | no: all made again when the list of states changes, [FsmDiagramToGraph.jl:113](../../../source/domain/fsm/FsmDiagramToGraph.jl#L113) | pattern for states, none for transitions, [FsmDiagramToGraph.jl:192](../../../source/domain/fsm/FsmDiagramToGraph.jl#L192) | lost |
| process flowchart | yes | the node itself; two made-up terminals | no: `_build_flowchart` makes all again, [ProcessDiagramToGraph.jl:168](../../../source/domain/process/ProcessDiagramToGraph.jl#L168) | whole node only, by evaluation and search, [ProcessDiagramToGraph.jl:314](../../../source/domain/process/ProcessDiagramToGraph.jl#L314) | lost |
| research map | yes | a widget card that the stage builds | no: a new `GraphGraph` at each build, [ResearchMapToGraph.jl:119](../../../source/domain/research/ResearchMapToGraph.jl#L119) | outline slots | lost |
| sequence chart | no, and rightly: lanes against time are no graph layout | — | — | row step | computed |
| git history | no node and link drawing exists: the commits are a roster table, [GitRange.jl:62](../../../source/domain/git/GitRange.jl#L62) | — | — | — | — |
| workflow | no: it is an outline of rows | — | — | — | — |

### 4. What the two charts share

| Piece | Chart | Sequence chart | Shared |
| --- | --- | --- | --- |
| scale, ticks, window and scroll bar arithmetic | uses the plot slice | uses the plot slice | yes |
| decimation | plot slice | its own in `SequenceChartGeometry.jl` | partly |
| legend | `_legend_plan`, `_legend_elements!` | none | chart only |
| view document and its stage | `ChartPlot`, `ChartToChartPlot` | `SequenceChartPlot`, `SequenceChartToSequenceChartPlot` | no: copied |
| reader of the view gestures | [ChartPlotToGraphics.jl:2157](../../../source/domain/chart/ChartPlotToGraphics.jl#L2157) to 2690 | [SequenceChartPlotToGraphics.jl:1202](../../../source/domain/sequencechart/SequenceChartPlotToGraphics.jl#L1202) to 1740 | no: copied |
| menu, buttons, bars | lines 2423 to 2507 | lines 1742 to 1803 | the routing helpers are shared (`DrawnChild.jl`, the scroll bar helpers); the rest is copied |
| keys that walk the parts | [ChartDocument.jl:1149](../../../source/domain/chart/ChartDocument.jl#L1149) | [SequenceChartDocument.jl:1235](../../../source/domain/sequencechart/SequenceChartDocument.jl#L1235) | no: 11 rows are the same; plain Left and Right differ, because the sequence chart walks the events with them (corrected by the check, was 13) |
| step that names one record of a column | `ChartSampleReferenceStep` | `SequenceChartRowReferenceStep` | no: two types of one shape |
| statistics | the frame times draw as a `Chart` (`FrameTimeSeriesToChart`) | — | yes |

### 5. Where positions live

| Thing | Place |
| --- | --- |
| chart, sequence chart: the frame | one computed cell of the IO map of the renderer |
| chart, sequence chart: the window | `view` of the plot document, made in the print |
| graph: the computed boxes and routes | `GraphLayout.vertex_layouts`, `edge_layouts`, the output of the first stage |
| graph: the pins and starts of a drop | `GraphGraph.constraints`, content, an edit with undo |
| graph: the corners of the last run | a `Ref` in the closure of the print, written inside a computation, [GraphToGraphLayout.jl:133](../../../source/domain/graph/GraphToGraphLayout.jl#L133) and [158](../../../source/domain/graph/GraphToGraphLayout.jl#L158) |
| graph: the boxes as drawn, with zoom and drag | the cell `drawn_boxes` of the IO map of the second stage |
| graph: zoom, drag, edge shape | fields of `GraphLayout`, made in the print |
| graph: the scroll | the `WidgetScrollPane` that `GraphGraphToWidgetScrollPane` makes in the print |

### 6. How outside state and long work enter

| Domain | What it reads | How | On the loop |
| --- | --- | --- | --- |
| git commit, change, file | the `git` program | `make_background_cell`, [GitDocument.jl:68](../../../source/domain/git/GitDocument.jl#L68) | no |
| git range | `git log`; the folders of the refs | background cell with an apply operation; `watch_folder!`, [GitRange.jl:52](../../../source/domain/git/GitRange.jl#L52) | no |
| catalog of a live database | ODBC queries | `with_connection` inside the computation of a `CellVector` that the print reads, [DatabaseInstanceToDbCatalog.jl:35](../../../source/adapter/odbc/DatabaseInstanceToDbCatalog.jl#L35) | **yes** |
| result of a query | an ODBC query | a computation made in `print_document`, [SqlToCellTable.jl:24](../../../source/adapter/odbc/SqlToCellTable.jl#L24) | **yes** |
| process debugger | a task of the default pool | a plain `ProcessTrace`; the host must call `sync_process_debug!` at each refresh, [ProcessDebugSession.jl:137](../../../source/domain/process/ProcessDebugSession.jl#L137) | the task: no; the copy: where the host calls it |
| FSM diagram | a running machine | a driver writes three cells of `FsmDiagram`; no code here does | — |
| chart function series | a callable of the person | `Base.invokelatest` in the layout of the print, [ChartPlotToGraphics.jl:268](../../../source/domain/chart/ChartPlotToGraphics.jl#L268) | **yes** |
| graph layout | an engine, 0.13 s at 300 vertices by `graph.md` | a computation of the first stage, [GraphToGraphLayout.jl:156](../../../source/domain/graph/GraphToGraphLayout.jl#L156) | yes (long work, not outside state) |
| research folder | files | the verbs `save_study_folder!`, `load_study_folder` | a verb, off the print |

### 7. Where the state of a view lives

| Way | Who uses it |
| --- | --- |
| A. A view document that `make_document_view` makes where a page opens, with `get_edited_field` and `follow_content_selection!`, [DocumentView.jl:33](../../../source/platform/domain/DocumentView.jl#L33) | the navigator, the dashboard, file views; no domain of this area |
| B. A view document that a stage makes inside the print | `ChartPlot`, `SequenceChartPlot`, `FsmDiagram`, `ProcessDiagram`, `GraphLayout` (zoom, drag, edge shape), the scroll pane of a graph |
| C. Fields on the content, named by `get_view_state_fields` | `WorkflowStep.collapsed`, `journal_shown`, [WorkflowDocument.jl:187](../../../source/domain/workflow/WorkflowDocument.jl#L187); `ResearchStudy.folded`, `deciding`, `view`, `editing`, [ResearchDocument.jl:467](../../../source/domain/research/ResearchDocument.jl#L467) |
| D. A view document that the content holds | `GitCommit.tree`, `GitCommitRange.table`, `WorkflowList.table` |
| E. A document that holds the content, made by the caller | `ResearchMap(study)`, `WorkflowJournal(workflow, kind)` |

## Findings

### DD-1 Outside state enters in three ways, and the database is read on the loop

- **Kind:** several-ways · **Value:** high · **Effort:** medium · **Confidence:** high
- **Principle:** first principle 9 (outside state enters by an acquire on a task; a printer reads no disk);
  `PAR-LOOP-RUNS-NO-USER-CODE`, `PAR-STORE-THEN-DRAIN`, `PAR-PRODUCER-CARRIES-THE-PART`.
- **Today:** The git documents read through `make_background_cell`, the kernel function that makes a cell whose value a
  task computes after the frame ([GitDocument.jl:68](../../../source/domain/git/GitDocument.jl#L68),
  [GitDocument.jl:135](../../../source/domain/git/GitDocument.jl#L135), [GitRange.jl:52](../../../source/domain/git/GitRange.jl#L52)).
  The ODBC adapter does not. `DatabaseInstanceToDbCatalog`, the projection from a connection document to the catalog
  tree, builds each level as a `CellVector` whose computation calls `with_connection` and runs the catalog query
  (four places: [DatabaseInstanceToDbCatalog.jl:35](../../../source/adapter/odbc/DatabaseInstanceToDbCatalog.jl#L35), 44, 54, 64).
  `SqlToCellTable`, the projection from a `SELECT` statement to a table, runs the statement in a computation that its
  `print_document` makes ([SqlToCellTable.jl:24](../../../source/adapter/odbc/SqlToCellTable.jl#L24)). Both run when the print
  reads the cell, on the task of the editor. The process domain has a third way: `start_process` spawns a task that writes
  a plain `ProcessTrace` ([ProcessDebug.jl:98](../../../source/domain/process/ProcessDebug.jl#L98)), and the host must call
  `sync_process_debug!` "from the refresh hook" ([ProcessDebugSession.jl:137](../../../source/domain/process/ProcessDebugSession.jl#L137)).
  No feed is registered, and a command of the person is a symbol in the cell `command` that the next call reads
  ([ProcessDebugSession.jl:67](../../../source/domain/process/ProcessDebugSession.jl#L67)). A chart function series calls the
  callable of the person in the layout of the print ([ChartPlotToGraphics.jl:268](../../../source/domain/chart/ChartPlotToGraphics.jl#L268)).
- **Example:**
  ```julia
  # today: a query in a computation that the print reads, on the loop
  CellVector(@computation begin
      names = with_connection(pool, inst) do adapter
          get_db_catalog_tables(adapter, schema_name)
      end
      DbCatalogTable[DbCatalogTable(n, _build_columns(pool, inst, schema_name, n)) for n in names]
  end)

  # proposal: the shape that GitCommit has
  reading = Cell(false)
  tables = make_background_cell(source, () -> (:tables, instance, schema_name);
                                default = DbCatalogTable[], working = reading)
  ```
- **Problem:** A slow or dead database stops every frame of the window, and a failed query throws inside a print. The
  catalog tree needs a special rule to stay cheap: `_children_realized` reads the `valid` flag of the cell so that a
  closed group runs no query ([DbCatalogToSyntax.jl:154](../../../source/domain/dbcatalog/DbCatalogToSyntax.jl#L154)). The process
  debugger works only in a host that knows to call the bridge, so no example of this repository can pause a process.
  The next domain with outside state has three examples to copy, and two of them break the principle.
- **Proposal:** One shape for every domain: the content document holds a background cell for each read, with a
  `reading` flag, as `GitCommit` does. The catalog becomes a document that reads its levels by background cells, and the
  result of a query a document with a background cell for its rows. A run of a process registers a feed, the kernel
  mechanism that copies a plain store into a document on the task of the editor, and a command of the person is an
  operation. The samples of a function series come from a background cell, which `chart.md` already names as "the later
  route".
- **What goes away:** `_children_realized` and its use; the rule in the docs that the host calls `sync_process_debug!`;
  the `command` cell; the projection `DatabaseInstanceToDbCatalog` as a place of queries (about 70 lines become
  constructors); the limit "a slow function slows the frame".
- **What stays:** The lazy catalog (a group reads when it is shown), the pool, the adapter seam, the plain
  `ProcessTrace` for an embedder, the probe protocol, the staleness check.
- **Risk and open questions:** `SqlToCellTable` prints the statement to text to run it; the background input must be
  that text, made on the loop. The owner must say whether a graph layout (long work, not outside state) should follow
  the same route; it changes when a graph first appears.
- **Related plans:** none covers it. `dbcatalog-index-support.md`, `bound-sql-statement.md` (both not started) add
  catalog reads and would copy the present shape.
- **Check:** confirmed. I opened the four `with_connection` computations (lines 35, 44, 54, 64), `SqlToCellTable.jl:24`,
  `ProcessDebug.jl:98`, `ProcessDebugSession.jl:67` and `137`, `ChartPlotToGraphics.jl:268`, the three git calls of
  `make_background_cell` and its docstring ([BackgroundCells.jl:180](../../../source/kernel/editor/BackgroundCells.jl#L180)); every
  statement holds. `chart.md:211` names the background cell as "the later route". No plan in `plan/pending` or
  `plan/tentative` moves the ODBC reads or the bridge of the debugger. Three additions. (1) `sync_process_debug!` has no
  caller in `source` or `example`, only in `ProcessDebugTest.jl`, and the "refresh hook" that `process.md:123` and D12 of
  `plan/done/process-domain.md` name is no function of the kernel today (no hit for it in `source/kernel/editor`); the
  kernel mechanism for this job is a feed (`PAR-PRODUCER-CARRIES-THE-PART`). (2) `_children_realized` does two jobs: a
  closed group runs no query, and a catalog that was built with plain vectors, or explored before, shows open. The second
  job must stay, so the function does not go away whole. (3) The docstring of `make_background_cell` says to make the cell
  where a document is built; the nested levels of the catalog are made when the level above is read, as
  `_make_file_change` of git does it, so the shape is possible, and the pool already has a lock
  ([ConnectionPool.jl:13](../../../source/adapter/odbc/ConnectionPool.jl#L13)). The proposal loses no feature. The value stays high
  for the ODBC part (a dead database stops the window); the process and the function series parts are each a small
  change of their own.

### DD-2 The stage from a domain to a graph is written three times, and none keeps its vertices

- **Kind:** repeated-by-hand · **Value:** high · **Effort:** medium · **Confidence:** high
- **Principle:** first principles 2 and 7 (a general step knows no domain; one mechanism); `PAR-DOCUMENT-IDENTITY`.
- **Today:** `FsmDiagramToGraph`, `ProcessDiagramToGraph` and `ResearchMapToGraph` each build a `GraphGraph` (the graph
  document) from their data: the vertices, the edges, the two highlight cells, the selection cell, the mouse target
  cell, and a pair of reference maps ([FsmDiagramToGraph.jl:103](../../../source/domain/fsm/FsmDiagramToGraph.jl#L103),
  [ProcessDiagramToGraph.jl:248](../../../source/domain/process/ProcessDiagramToGraph.jl#L248),
  [ResearchMapToGraph.jl:73](../../../source/domain/research/ResearchMapToGraph.jl#L73)). The maps differ in power: FSM maps a
  state with its tail and no transition; process maps a whole node only; research uses the slots of the outline kit.
  Each stage makes every `GraphVertex` again when its input changes shape
  ([FsmDiagramToGraph.jl:113](../../../source/domain/fsm/FsmDiagramToGraph.jl#L113)), and each starts with empty constraints
  ([FsmDiagramToGraph.jl:176](../../../source/domain/fsm/FsmDiagramToGraph.jl#L176),
  [ProcessDiagramToGraph.jl:282](../../../source/domain/process/ProcessDiagramToGraph.jl#L282)). The graph stage keys all its
  memory of places by the vertex object: the pins and starts ([GraphToGraphLayout.jl:75](../../../source/domain/graph/GraphToGraphLayout.jl#L75))
  and the corners of the last run ([GraphToGraphLayout.jl:97](../../../source/domain/graph/GraphToGraphLayout.jl#L97)).
- **Example:**
  ```julia
  # today, in each domain: about 110 lines of cells and two map functions
  function print_document(p::FsmDiagramToGraph, recursion, diagram, ctx) ... end
  function map_reference_forward(::FsmDiagramToGraph, iomap, reference) ... end
  function map_reference_backward(::FsmDiagramToGraph, iomap, reference) ... end

  # proposal: the domain says what its nodes and links are
  collect_graph_nodes(diagram::FsmDiagram) = diagram.machine.states
  collect_graph_links(diagram::FsmDiagram) =
      [(source = s, target = t.target, label = t) for s in diagram.machine.states for t in s.transitions
       if t.target !== nothing]
  find_graph_highlight(diagram::FsmDiagram) = (node = ..., link = ...)
  ```
- **Problem:** A drag of a vertex works on a graph that is content, and is lost on every derived diagram: an insert of
  a state makes new vertex objects, so the pins point at nothing and the layout starts from its spiral. `graph.md`
  lists this as a limit ("a graph that a view makes keeps the places of a drop only while the view lives"), and the done
  plan `the-mouse-drags-a-vertex-of-a-graph.md`, section 6, says "a domain that wants to keep the places must map them to
  its own document" (corrected by the check: the sentence is in the plan, not in `graph.md`), so each domain would write
  that too. The process map lights no box for a caret inside a step. The FSM map does not carry a
  selection of a transition. The next diagram (the topology of a simulation, the relations of a catalog) writes the
  fourth copy.
- **Proposal:** One generic stage in the graph domain. A domain gives three functions: the nodes, the links with
  their labels, and the highlight. The stage keeps one `GraphVertex` for each node by identity, so the places survive
  an edit. It maps a path by the longest prefix that reaches a node, so the tail comes for free, and it maps the label
  of a link the same way. The pins and starts are kept by node.
- **What goes away:** three `print_document` methods and six map functions, about 200 lines (corrected by the check,
  was 300: the three stages with their maps are about 310 lines, and the walk of each domain and its highlight stay);
  the limit that a derived graph loses its places; the whole-node limit of the flowchart.
- **What stays:** The label projections of FSM and process, the terminals of a flowchart (nodes with no document), the
  edges with no line of the research map, the highlight that goes around the layout cell.
- **Risk and open questions:** The research map builds a widget card for each vertex in the stage; the generic stage
  would print the item through the recursion, as FSM and process do, with the card as the view of an item in a map.
  The owner must say where the places of a derived diagram are kept across a reprint: on the view document of the
  diagram (see DD-3), or nowhere, as today.
- **Related plans:** `a-graph-lights-the-part-under-the-pointer.md` (pending, the omnet half) is a fourth producer.
  The done plans `the-mouse-drags-a-vertex-of-a-graph.md` and `a-graph-keeps-its-view-when-you-edit-scroll-and-zoom.md`
  record the limit.
- **Check:** confirmed-with-corrections. I read the three stages in full and `GraphToGraphLayout.jl:60` to 165. The facts
  hold: FSM and process make every `GraphVertex` again in one computation, both start with `Cell(GraphConstraint[])`, and
  the graph stage keys the pins, the starts and the last corners by the vertex object. Corrections: the quoted sentence
  is in the done plan and not in `graph.md`; the saving is nearer 200 lines than 300; and "written three times" is two
  close copies and one other shape. FSM and process share a skeleton of about 25 lines and differ in their maps (a field
  pattern against evaluation and search, because a box of a flowchart sits at any path). The research map is another
  shape: one computation makes a new `GraphGraph`, a widget card for each vertex, the slots of the outline kit and the
  routing by `route_outline_paths!`. It joins the generic stage only when the card of an item is a projection of the
  item, which is the work of DD-4; until then the menu, the keys and the decision panel of a card stay where they are.
  One more condition: the stage must keep its vertices by node without a computation that reads its own earlier result
  (`PAR-PURE-THUNK`); `KeptListPrints` of the collection slice is the precedent. No plan covers the stage, and no settled
  decision is touched, because the places stay out of the content tree. The value stays high: the drag of a vertex is a
  feature that works only on a graph that is content, and the omnet topology is the fourth producer.

### DD-3 A view document is made in two ways; the diagram domains copy the second way four times

- **Kind:** several-ways · **Value:** high · **Effort:** medium · **Confidence:** medium
- **Principle:** first principle 7; the rule of the done plan `a-view-document-keeps-the-state-of-one-view.md` ("a view
  document names the content that it shows with `get_edited_field`").
- **Today:** The platform has one way: `make_document_view(document)` answers the view document of a content, and
  `follow_content_selection!` makes its selection and mouse target follow the content by one field step
  ([DocumentView.jl:33](../../../source/platform/domain/DocumentView.jl#L33), [DocumentView.jl:58](../../../source/platform/domain/DocumentView.jl#L58)).
  The navigator and the dashboard call it where a page opens ([NavigatorVisits.jl:264](../../../source/platform/navigator/NavigatorVisits.jl#L264)).
  The diagram domains use another way: a projection stage that makes the view document inside its `print_document`,
  with the same two cells and a pair of maps that add and take one field step. There are four copies of one shape (the
  FSM and the process stage are the same line for line except the names; the two chart stages also make the buttons and
  the bars of the plot and introduce the references of those parts; corrected by the check): [ChartToChartPlot.jl:33](../../../source/domain/chart/ChartToChartPlot.jl#L33),
  [SequenceChartToSequenceChartPlot.jl:34](../../../source/domain/sequencechart/SequenceChartToSequenceChartPlot.jl#L34),
  [FsmToFsmDiagram.jl:33](../../../source/domain/fsm/FsmToFsmDiagram.jl#L33),
  [ProcessToProcessDiagram.jl:31](../../../source/domain/process/ProcessToProcessDiagram.jl#L31).
  `GraphGraphToWidgetScrollPane` is a fifth of the same shape ([GraphToWidgetScrollPane.jl:30](../../../source/domain/graph/GraphToWidgetScrollPane.jl#L30)).
  None of the four view documents of the domains has a method of `make_document_view` or `get_edited_field`;
  `WidgetScrollPane` has `get_edited_field`, `:content`
  ([WidgetDocument.jl:4247](../../../source/platform/widget/WidgetDocument.jl#L4247); corrected by the check).
- **Example:**
  ```julia
  # today, four times: 60 to 100 lines
  struct FsmToFsmDiagram <: Projection end
  function print_document(p::FsmToFsmDiagram, recursion, machine, ctx)
      iomap_cell = Cell(nothing)
      diagram = FsmDiagram(Cell(machine), Cell(0), Cell(0), Cell(0),
          Cell(@computation ... map_reference_forward(p, im, machine.selection) ...),
          Cell(@computation map_mouse_target_forward(machine, ...)))
      ...
  end
  map_reference_forward(::FsmToFsmDiagram, iomap, reference) = ...   # machine.rest
  map_reference_backward(::FsmToFsmDiagram, iomap, reference) = ...  # rest

  # proposal: two declarations for each domain, one generic stage for all
  make_document_view(machine::FsmMachine) = FsmDiagram(machine)
  get_edited_field(::FsmDiagram) = :machine
  ```
- **Problem:** With the second way the state of the view lives only as long as the print. `graph.md` lists the result:
  "a reprint of the graph starts at no zoom", "the pane of a graph does not keep its scroll position". A driver of a
  running machine must find the `FsmDiagram` in the output of the stage. A navigator page of a chart gets no view
  document from `make_document_view`, so the two ways do not meet. Each new diagram copies the stage.
- **Proposal:** Each domain declares its view document by `make_document_view` and `get_edited_field`. One generic,
  domain-free stage of the platform calls them and maps by the edited field, for a content that stands inside another
  document. A place that already holds a view document (a navigator slot, a dashboard slot) passes it on, so the zoom
  of a chart lives as long as its page. The buttons and bars of a plot are made by the constructor of the plot.
- **What goes away:** four stage types, their four IO map types and eight map functions, about 300 lines; the
  reason for the limits quoted above.
- **What stays:** `ChartPlot`, `SequenceChartPlot`, `FsmDiagram`, `ProcessDiagram` and every field of them; two panes
  that zoom one chart apart; the introduced references of the buttons and bars.
- **Risk and open questions:** The pending plan `views-compose-as-content-composes.md` (status LATER) sets the future
  model of content and view, with JSON as the pilot and "the other domains follow". This finding is a smaller step in
  the same direction and should not go against it; the owner should say whether to wait. The scroll pane of a graph is
  a widget, not a view document of the domain, and may need its own answer.
- **Related plans:** `a-view-document-keeps-the-state-of-one-view.md` (done: wrote the rule),
  `views-compose-as-content-composes.md` (pending, LATER, not started).
- **Check:** confirmed-with-corrections, value medium. I read `DocumentView.jl`, the five stages, the done plan and the
  LATER plan. The core holds: the rule in `architecture-rules.md` ("a view document names the content that it shows with
  `get_edited_field`") names `ChartPlot` as a view document, and `ChartPlot`, `SequenceChartPlot`, `FsmDiagram` and
  `ProcessDiagram` have no such method; the navigator and the dashboard are the only callers of `make_document_view`.
  Corrections: (1) the two facts corrected above; (2) the stages total 348 lines with their comments. (3) The example
  `make_document_view(machine::FsmMachine) = FsmDiagram(machine)` does not fit: `make_document_view` answers the one
  view of a page, and DD-8 of this report makes the notation the default view of a machine and of a process. The diagram
  is a second view, so its view document is made by its caller, as `ResearchMap(study)` is (way E of inventory 7), and
  `follow_content_selection!` wires it. `make_document_view` fits the chart and the sequence chart only. (4) A smaller
  repair exists and the report missed it: the four stages, the two stages to a graph, the scroll pane stage and
  `GraphToGraphLayout` write the selection cell and the mouse target cell by hand, where the kernel has
  `make_output_path_cells` ([OutputPaths.jl:29](../../../source/kernel/projection/OutputPaths.jl#L29)), whose docstring says "use
  it wherever a printer wires the selection of its output". The value is lowered from high: the LATER plan
  `views-compose-as-content-composes.md` sets the future model, in which a view makes the view of a part by the identity
  of the part, and its last section says "the other domains; they follow the pilot one at a time". This finding is a
  step that the owner must place before or after that pilot. No feature is lost when the corrections are taken.

### DD-4 The outline of a workflow and of a study walks its whole tree in one computation

- **Kind:** special-case · **Value:** medium · **Effort:** large · **Confidence:** medium
- **Principle:** `PAR-DELEGATE-ONE-LEVEL` (a projection transforms its own level and delegates each child, also a
  child of the same domain); first principles 1 and 6 (incremental; no central walker).
- **Today:** `WorkflowNodeToWidget.print_document` does not use its `recursion` for the steps below the root. One
  computation collects every shown node of the tree (`_collect_workflow_rows`,
  [WorkflowToWidget.jl:339](../../../source/domain/workflow/WorkflowToWidget.jl#L339)) and builds every row
  ([WorkflowToWidget.jl:531](../../../source/domain/workflow/WorkflowToWidget.jl#L531) to 577). `ResearchStudyToWidget` does the
  same for all items of all kinds, and chooses between the outline, the map and the report inside that one computation
  ([ResearchToWidget.jl:881](../../../source/domain/research/ResearchToWidget.jl#L881) to 912). Because no child has an IO map,
  the views keep a second path mechanism, the `OutlineSlot` list of the outline kit, and each copies the same 57 lines
  around it: the IO map type, the step helpers, the two maps and `_make_*_iomap`
  ([WorkflowToWidget.jl:84](../../../source/domain/workflow/WorkflowToWidget.jl#L84) to 140,
  [ResearchToWidget.jl:88](../../../source/domain/research/ResearchToWidget.jl#L88) to 144; a `diff` after a rename shows two
  lines that differ). `ResearchMapToGraph` has a third copy ([ResearchMapToGraph.jl:63](../../../source/domain/research/ResearchMapToGraph.jl#L63)).
- **Example:**
  ```julia
  # today: one build for the whole tree
  print_document(p::WorkflowNodeToWidget, recursion, node, ctx) =
      _make_workflow_iomap(p, node, () -> _build_node_view(p, node))   # walks every node below `node`

  # proposal: a row prints itself and delegates its children
  function print_document(p::WorkflowNodeToRow, recursion, node, ctx)
      children = [print_child(recursion, child, make_child_context(ctx, node, "children", i))
                  for (i, child) in enumerate(node.children) if !node.collapsed]
      ...   # the row of this node, and the children below it; the maps come from the child IO maps
  end
  ```
- **Problem:** A fold of one node, a new entry or a new item builds every row of the view again, and the stage after it
  prints them again; the docs of the workflow say so. A workflow node inside another view (a tree, a map) can not reuse
  the row of one node, because no projection of one node exists. The research map routes the paths of each vertex by
  hand, because the card of a vertex is a widget that the stage built and the graph stages hand it no path
  ([ResearchMapToGraph.jl:130](../../../source/domain/research/ResearchMapToGraph.jl#L130)).
- **Proposal:** A projection for one node (one row and the delegation of its children), in the shape of the syntax
  projections. The maps come from the child IO maps (`PAR-DELEGATE-AND-LIFT`). The slot list stays only for the parts
  inside one row. The three views of a study are three projections that a dispatch on `study.view` chooses.
- **What goes away:** the two whole-tree builds, the two copies of the IO map scaffolding and most uses of
  `route_outline_paths!`; the cost of a full rebuild at each fold.
- **What stays:** The outline kit as the look of a row, the guides, the menus, the keys of a row, the elements through
  the view of their own domain, the by-kind and by-time groups.
- **Risk and open questions:** The dates shown in a row depend on the row before it (`compute_shown_dates`), and the
  by-time order crosses the lists; both need a value that spans rows, which a parent can pass in the printer context.
  I did not find a recorded reason for the one build in `a-study-and-a-workflow-read-as-one-quiet-outline.md`; the owner
  may know one. The outline kit is in the area of the platform widgets.
- **Related plans:** `a-study-and-a-workflow-read-as-one-quiet-outline.md` (done) built the present shape.
- **Check:** confirmed. I read `WorkflowToWidget.jl:60` to 145, 325 to 360 and 505 to 600, `ResearchToWidget.jl:868` to
  925 and `ResearchMapToGraph.jl` in full. `print_document` of both views takes `recursion` and does not use it for the
  nodes below the root; `workflow.md:53` says that one computation builds the outline. The `diff` of the two blocks of 57
  lines shows three lines that differ. `PAR-DELEGATE-ONE-LEVEL` says "even a same-domain child". The recorded reason of
  the one build is in `a-workflow-records-steps-decisions-and-dates.md`, line 333: "as the row view of the data frames
  does", and a static build showed a stale outline. It is a reason for a computation against a static build, not for one
  walk of the tree, so it does not refute the finding. The way to delegate exists today: the output of the outline
  already holds the elements of a node as documents, and the stage after it prints each through the renderer, which has
  a row for `WorkflowStep`. Two costs that the proposal must carry: the date of a row depends on the row before it in
  the flat order, which is the last shown node under the sibling before, so it is a query of the tree and not a value
  that the parent passes; and the output changes from one flat list of rows to nested layouts. The 57 copied lines can
  sink into the outline kit without the rest. The value stays medium, and the effort is large.

### DD-5 The chart and the sequence chart write one plot interaction twice

- **Kind:** repeated-by-hand · **Value:** medium · **Effort:** medium · **Confidence:** high
- **Principle:** first principle 7; `PAR-FRAMEWORKS-SINK` (what two slices both need sinks to the platform).
- **Today:** The arithmetic of a window is shared in the plot slice. The code around it is not. Both renderers have the
  same reader skeleton ([ChartPlotToGraphics.jl:2157](../../../source/domain/chart/ChartPlotToGraphics.jl#L2157),
  [SequenceChartPlotToGraphics.jl:1202](../../../source/domain/sequencechart/SequenceChartPlotToGraphics.jl#L1202)), the same
  drag life cycle (`_drag_start`, `_drag_move`, `_drag_end`, `_cancel_drag`:
  [chart 2549](../../../source/domain/chart/ChartPlotToGraphics.jl#L2549), [sequence chart 1601](../../../source/domain/sequencechart/SequenceChartPlotToGraphics.jl#L1601)),
  the same key reader ([2637](../../../source/domain/chart/ChartPlotToGraphics.jl#L2637), [1701](../../../source/domain/sequencechart/SequenceChartPlotToGraphics.jl#L1701)),
  the same menu, the same three buttons and the same handling of the two bars, with the same comments. Both gesture
  tables repeat 11 rows that walk the parts (corrected by the check, was 13: plain Left and Right of the sequence chart
  walk the events when one is selected) ([ChartDocument.jl:1149](../../../source/domain/chart/ChartDocument.jl#L1149),
  [SequenceChartDocument.jl:1235](../../../source/domain/sequencechart/SequenceChartDocument.jl#L1235)) with their own
  `_step_part`, `_select_part` and `_select_whole`. Both define a reference step of one `index` field for a record of
  a column ([ChartSampleReferenceStep.jl:4](../../../source/domain/chart/ChartSampleReferenceStep.jl#L4),
  [SequenceChartRowReferenceStep.jl:29](../../../source/domain/sequencechart/SequenceChartRowReferenceStep.jl#L29)), while the
  data frame adapter names a row by the range step of the kernel ([DataFrameEdit.jl:299](../../../source/adapter/dataframes/DataFrameEdit.jl#L299);
  line 31 of `DataFrameColumn.jl` is the helper that makes `field[i]`).
  The check counts about 200 lines on each side that are the same but for the names: the menu, the buttons, the
  `KeyPress` reader, the Ctrl branch of the `KeyDown` reader, the start, the clear and the cancel of a drag, the three
  constants, the 11 rows and the step type. (Corrected by the check, was "about 600 lines on each side that differ only
  in names and in the count of axes": the two files have the same outline, but the bodies of the window code differ.)
- **Example:**
  ```julia
  # today, in each chart
  function _key_intent(g, plot::ChartPlot, event::KeyDown) ... end          # and for SequenceChartPlot
  function compute_context_menu(plot::ChartPlot) ... end                    # and for SequenceChartPlot
  function make_chart_buttons(plot::ChartPlot) ... end                      # and make_sequence_chart_buttons

  # proposal: the chart says what its axes are; one kit does the rest
  get_plot_axes(plot::ChartPlot, frame) = (x = (; window, extent, log, scale), y = (; ...))
  write_plot_window(plot::ChartPlot, axis, window) = ...    # the chart keeps how it stores a window
  ```
- **Problem:** A change of a gesture rule must be made twice; the done plan of the zoom notes that the two charts had
  two sets of numbers before. A third plot (a timeline strip, a histogram of results downstream) copies it all again.
- **Proposal:** A plot view kit above the plot arithmetic, in the platform: the drag life cycle, the wheel, the keys,
  the view actions (see DD-6), the bars and the buttons, written once over a small interface (the axes of the plot and
  the write of a window). One helper gives the rows that walk a list of parts. One step type names a record of a
  column, or the range step of the kernel does, with `evaluate_reference_step` by the type of the series.
- **What goes away:** about 600 lines in one of the two charts, one reference step type, one set of constants.
- **What stays:** Every gesture of both charts; the anchored window, `follow_end` and the lane scroll of the sequence
  chart, behind its own write function; the window that stays in the data; each chart's own drawing.
- **Risk and open questions:** Decision D14 of the done plan `a-chart-zooms-pans-and-fits-by-mouse-and-keys.md`
  (owner, 2026-11-10) accepted the present split: the routing of drawn children went to the graphics slice, the scroll
  bar helpers to the widget slice, and "each chart keeps where its parts go". The plan rejected "a new container that
  draws a band of controls over any content" because the two charts were its only users. This finding asks for less:
  the reader and the actions, not a container. The owner should confirm that it does not reopen D14. The plot slice is
  pure today; the kit would be a second fragment or a new slice.
- **Related plans:** `a-chart-zooms-pans-and-fits-by-mouse-and-keys.md` (done).
- **Check:** weakened, value low. I read both readers from the drag to the buttons (`ChartPlotToGraphics.jl:2157` to
  2670, `SequenceChartPlotToGraphics.jl:1601` to 1803), both gesture tables and both step types. The two files have the
  same outline, but the code of the window is not a copy. The chart has two free axes, a `ChartView`, log axes and a
  band over one axis or both. The sequence chart has one time axis, a scroll of the lanes in pixels (`cross_offset`),
  `follow_end`, an anchored window and two orientations, and its Page keys and its pan read the laid-out frame. An
  interface of axes (`get_plot_axes`, `write_plot_window`) must carry all of this for two users, and D13 of the done
  plan rejected a shared container of controls for that reason: "the two charts are its only users now". D14 (the
  owner, 2026-11-10: "Shared code", "this structure is acceptable for both slices") set the line five days before this
  commit: "each chart keeps where its parts go, their print, its buttons and its two bars filled from its own window".
  The kit moves the buttons, the bars and the reader over that line, so it asks the owner to decide D14 again. What
  holds with no kit: the three constants `_ZOOM_STEP`, `_PAN_STEP` and `_DRAG_MIN` are defined in both files, which is
  the "two sets of numbers" that D1 wanted gone; one helper can give the 11 rows that walk a list of parts; and one step
  can name a record of a column (the owner's rule is to add no reference step when a field, an index or a position
  does). The menu and the buttons go with DD-6. A third plot is not in any plan.

### DD-6 The view gestures of a plot and of a graph are in readers, so nothing can list them

- **Kind:** partial-feature · **Value:** medium · **Effort:** small · **Confidence:** medium
- **Principle:** first principles 3 and 10 (one way to act; the surface of the assistant comes by reflection).
- **Today:** The gesture help, the command palette and the assistant's `describe_commands` read gesture bindings
  through the event `CollectIntents` (`GestureHelpModule`). In this area only the git text names it in a reader
  ([GitToWidget.jl:133](../../../source/domain/git/GitToWidget.jl#L133)); a `@gestures` table answers it through
  `fire_gesture_bindings` of the kernel ([GestureBinding.jl:112](../../../source/kernel/binding/GestureBinding.jl#L112)).
  The view actions of the charts are not bindings: `_key_intent` matches the keys by hand
  ([ChartPlotToGraphics.jl:2637](../../../source/domain/chart/ChartPlotToGraphics.jl#L2637)), with the comment that a document
  gesture "only ever sees the chart". But the plot is a document, and its menu is already bound to it
  ([ChartPlotToGraphics.jl:2435](../../../source/domain/chart/ChartPlotToGraphics.jl#L2435)). Each action is then written three
  times, each with its label and its key as text: in the key reader, in the menu
  ([2423](../../../source/domain/chart/ChartPlotToGraphics.jl#L2423)) and in the buttons ([2446](../../../source/domain/chart/ChartPlotToGraphics.jl#L2446)).
  The graph is the same: the zoom of the layout exists only as Ctrl and the wheel in the reader
  ([GraphLayoutToGraphics.jl:759](../../../source/domain/graph/GraphLayoutToGraphics.jl#L759)); it has no key, no menu item and
  no name.
- **Example:**
  ```julia
  # today: three places for one action
  key === :equals && return _zoom_in_view(plot)                                   # the key reader
  item("Zoom in", _zoom_in_view(plot), Any["Ctrl+="])                             # the menu
  button("Zoom in", :zoom_in, "Ctrl+=", _zoom_in_view)                            # the buttons

  # proposal: one table on the view document; the menu and the buttons read it
  @gestures ChartPlot begin
      KeyDown(:equals; ctrl) => "Zoom in" => _zoom_in_view(doc)
      KeyDown(:minus; ctrl)  => "Zoom out" => _zoom_out_view(doc)
      KeyDown(:zero; ctrl)   => "Show all the data" => _show_all_view(doc)
  end
  ```
- **Problem:** A person does not find "Zoom in" of a chart in the command palette, and a model can not run it by name;
  it must build the write of `view` itself. A graph can not be zoomed by a key or by the assistant at all.
- **Proposal:** The view actions are rows of a binding table on the view document. The menu and the toolbar are made
  from the rows (label, key, enabled when the action answers an operation). The reader keeps only what needs the
  geometry: the wheel at a point, the band, the pan.
- **What goes away:** the two `_key_intent` methods in each chart, the labels and key texts repeated in the menu and
  the buttons; about 80 lines in each chart.
- **What stays:** Every key, the menu, the buttons with their disabled state, the rule that a key at a limit is not the
  chart's.
- **Risk and open questions:** I did not check that a key reaches the binding table of a document that a stage made
  (the context menu does). Page Up and Page Down of the sequence chart need the laid-out frame for the lanes and may
  stay in the reader.
- **Related plans:** `key-chords-from-bindings.md` (pending; not read in full) is about bindings and may touch this.
- **Check:** confirmed. I read the reader of the plot (`ChartPlotToGraphics.jl:2157`), `fire_gesture_bindings`, the
  default reader of a leaf ([ProjectionDefaults.jl:145](../../../source/kernel/projection/ProjectionDefaults.jl#L145)) and the
  collection in `Chaining.jl:269`. The open question of the report is answered: the reader of the plot stage is the
  first to get a key, with the plot as its input, so it can fire a table of the plot with `read_bound_gesture(plot,
  event)`, as `GitToWidget.jl:134` fires its rows; a chain asks each of its stages for `CollectIntents`, so the rows
  reach the gesture help. Today the reader answers `nothing` to `CollectIntents`. The comment "a document gesture only
  ever sees the chart" is older than the binding table of the plot, which holds the menu since the zoom plan. A row
  whose operation is `nothing` is skipped, so the rule that a key at a limit is not the chart's stays. The graph fact
  holds: `GraphLayout.jl:106` binds only the edge shape, and the zoom is in `_read_ctrl_wheel` alone. The plan
  `key-chords-from-bindings.md` is about chords and does not touch this. One new piece is needed and the report should
  say so: no helper makes a menu or a toolbar from the rows of a table today. Each action is written four times, not
  three: the `KeyPress` reader repeats it for the plain characters. No feature is lost.

### DD-7 Each domain writes its own plumbing for a verb, and workflow and research keep two code paths

- **Kind:** repeated-by-hand · **Value:** medium · **Effort:** medium · **Confidence:** medium
- **Principle:** first principles 3 and 10; `editor.md`, "A change as a value": "the verb is its method of
  `make_change` and then `apply_change!`, so a change has one code path".
- **Today:** 24 of the 55 methods of `make_change` in the repository are in four domains of this area (research 12,
  workflow 6, sequence chart 4, chart 2). Each domain has a private function that carries an operation from a part to
  the root: `_make_chart_change` ([ChartDocument.jl:1138](../../../source/domain/chart/ChartDocument.jl#L1138)),
  `_make_sequence_chart_change` ([SequenceChartDocument.jl:801](../../../source/domain/sequencechart/SequenceChartDocument.jl#L801)),
  `_find_workflow_change` and two more ([WorkflowEdits.jl:207](../../../source/domain/workflow/WorkflowEdits.jl#L207)),
  `_find_research_change` and two more ([ResearchVerbs.jl:17](../../../source/domain/research/ResearchVerbs.jl#L17)). The chart
  verbs follow the documented rule. The workflow and research verbs do not: the verb evaluates through
  `_evaluate_workflow_operation!`, which falls back to a direct evaluation for a node that no window shows, and
  `make_change` goes through `_make_workflow_change`, which throws in that case
  ([WorkflowEdits.jl:301](../../../source/domain/workflow/WorkflowEdits.jl#L301) and [310](../../../source/domain/workflow/WorkflowEdits.jl#L310)).
  One edit is thus written up to four times: the operation builder, a private wrapper that sets the author, the verb,
  and the `make_change` method.
- **Example:**
  ```julia
  # today, for each verb
  function choose_workflow_option!(decision, index; reason = nothing, editor = get_evaluation_editor())
      run_on_editor_task!(editor; description = "choose_workflow_option!") do
          operation = _make_choose_workflow_option(decision, index; reason)
          _evaluate_workflow_operation!(editor, decision, operation, "Choose an option"); decision
      end
  end
  make_change(::typeof(choose_workflow_option!), decision, index; reason = nothing, editor = ...) =
      run_on_editor_task!(editor; description = "make_change") do
          _make_workflow_change(editor, decision, _make_choose_workflow_option(decision, index; reason), ...)
      end

  # proposal: the domain gives the operation at the part; the kernel gives the verb and its change
  make_part_operation(::typeof(choose_workflow_option!), decision, index; reason = nothing) =
      make_choose_workflow_option_operation(get_document(decision), index; reason, author = :assistant)
  ```
- **Problem:** The rule "one code path" is kept by convention, and half of this area breaks it. Every new verb of every
  domain repeats the task switch, the rooting and the error text.
- **Proposal:** The kernel owns the path from a part to a rooted change, once, with one rule for a part that no window
  shows. A domain verb is one method that answers the operation at its part and its description. The verb function
  itself keeps its docstring, which the assistant reads.
- **What goes away:** the four private rooting helpers and their variants (about 60 lines), and one of the two methods
  for each of 24 verbs.
- **What stays:** Every verb name, `make_change`, `combine_changes`, the author `:assistant`, the answer of each verb.
- **Risk and open questions:** The research helper takes the field of the study that it writes, because
  `find_rooted_operation` "needs a place between the root and the edited node"; the generic path must keep that. This
  reaches into the area of the assistant and the tool set.
- **Related plans:** `assistant-api-consolidation.md` (pending) is about the verbs of panes and of omnet, not about
  this plumbing.
- **Check:** weakened, value low. The counts hold: 55 methods of `make_change` in `source`, of which research 12,
  workflow 6, sequence chart 4 and chart 2. The private helpers are as cited. But the second code path of workflow and
  research is a stated feature and no slip: "a workflow that no view shows takes the operation directly"
  ([WorkflowEdits.jl:203](../../../source/domain/workflow/WorkflowEdits.jl#L203)) and "a study that no view shows takes the
  operation directly" ([ResearchVerbs.jl:9](../../../source/domain/research/ResearchVerbs.jl#L9)). These verbs take a part of
  the window or the plain document, so a script and the assistant can fill a study before a pane shows it; the chart
  verbs and `insert_elements!` of the kernel take only a part of the window and throw. A change from the root can not
  exist for a document that has no root, so `make_change` must throw there. "One rule for a part that no window shows"
  therefore loses this feature if the rule is to throw, and gives the kernel verbs an edit that no history records if
  the rule is to evaluate. The proposal does not say which. The second half, "one of the two methods for each of 24
  verbs goes", needs a mechanism that the report does not give: each verb has its own part, its own answer (the new
  decision, the decision, the item as a part) and its own checks, and the verb function needs a method of its own
  beside the docstring. What holds: the three helpers (find, make, evaluate) are the same in workflow and research and
  close in the two charts, about 80 lines in all, and one helper of the kernel beside `find_rooted_operation` can
  replace them and give one error text.

### DD-8 Five of the ten domains have no view in the general renderer

- **Kind:** partial-feature · **Value:** medium · **Effort:** small · **Confidence:** medium
- **Principle:** first principles 2 and 5 (projections compose; a domain combines with the others).
- **Today:** The general renderer draws a document by the row of its type. Chart, graph, workflow and research add
  their rows to a registry table in `__init__` ([ChartModule.jl:74](../../../source/domain/chart/ChartModule.jl#L74)). Git adds
  methods of the seam `make_graphics_projection` ([GitToWidget.jl:524](../../../source/domain/git/GitToWidget.jl#L524)).
  Sequence chart, FSM, process, dbcatalog and database add nothing; their package documents say "a caller builds the
  chain". The sequence chart even has `make_sequence_chart_projection`, the whole view as one projection
  ([SequenceChartPlotToGraphics.jl:1814](../../../source/domain/sequencechart/SequenceChartPlotToGraphics.jl#L1814)), and no row
  that uses it.
- **Example:**
  ```julia
  # today
  open_pane!(chart)             # a chart
  open_pane!(sequence_chart)    # no row: not the designed view
  GraphVertex(fsm_machine)      # a machine as the content of a vertex of another graph: no row

  # proposal: one method for each domain, as git has
  make_graphics_projection(::Type{<:SequenceChart}; measure, appearance) =
      make_sequence_chart_projection(; measure, theme = get_scaled_theme!(appearance, SequenceChartTheme), ...)
  ```
- **Problem:** A workflow element, an item of a study, a vertex of a graph and a tab can hold a document of any
  domain, but half of the domains of this area then do not show as designed. A simulation trace printed as a sequence
  chart needs its caller to pass the chain in `extra`.
- **Proposal:** Each domain gives `make_graphics_projection` for its root types: the sequence chart its projection, FSM
  and process their notation (the diagram is a second view, by its view document), the catalog its tree.
- **What goes away:** the `extra = Pair{Type,Any}[...]` that callers pass, and the sentence "registers nothing" in five
  documents.
- **What stays:** The explicit chains, for a caller that wants another view.
- **Risk and open questions:** I did not run the renderer to see what it draws for these types today; I assume the
  view on demand. The owner must choose the default view where a domain has two (notation or diagram).
- **Related plans:** `packages-compose-by-seams.md` (in progress), decision C7: the registry tables of the natural
  renderer stay for now and "a later plan" moves them to seams. That covers the two ways to register; it does not add
  the missing rows.
- **Check:** confirmed-with-corrections. A grep of `register_natural` and `make_graphics_projection` in `source/domain`
  and `source/adapter` finds no hit in the sequence chart, FSM, process, dbcatalog and database folders, and the four
  package documents say "registers nothing". The open point of the report is answered by `natural.md:133`: "a document
  that reaches the reflection tail shows its fields. It does not get the view of its domain." So a machine in a tab
  shows as a list of fields today. The proposal agrees with C1 and C7 of the seams plan. Corrections: the graph row is at
  line 1241. The notations of FSM, process and the catalog are syntax views, and a syntax row enters the renderer through
  the syntax tables (`register_natural_domain!` or `register_natural_syntax!`), so that it also shows inside the syntax
  of another document; `make_graphics_projection` with a whole chain to graphics would skip that. C7 leaves the syntax
  tables as tables for now, so these three rows use the table or wait for the later plan. The sequence chart is the
  clean case for the seam method. `DatabaseInstance` has no view that its domain can give alone, because its catalog
  needs a pool, so the count of rows to add is four, not five. No feature is lost. The value stays medium.

### DD-9 The catalog draws its tree by its own projections, and the database domain holds a table model that nothing uses

- **Kind:** several-ways · **Value:** medium · **Effort:** medium · **Confidence:** medium
- **Principle:** first principle 8 (reuse an existing view before a new one is made); "redundant" for the second half.
- **Today:** A tree of nodes that open exists in the platform as the tree slice. A domain joins it with three small
  methods; git does ([GitTree.jl:89](../../../source/domain/git/GitTree.jl#L89) to 108), and so do workflow
  ([WorkflowList.jl:169](../../../source/domain/workflow/WorkflowList.jl#L169)) and research. The catalog browser is the same
  feature in 348 lines of its own: four entity projections of one shape
  ([DbCatalogToSyntax.jl:219](../../../source/domain/dbcatalog/DbCatalogToSyntax.jl#L219), 242, 265, 288), two hand-written map
  helpers ([DbCatalogToSyntax.jl:76](../../../source/domain/dbcatalog/DbCatalogToSyntax.jl#L76)), its own rule for a closed
  group and its own predicate for the fold marker. In the database domain, `DatabaseTable` and the operations
  `UpdateDatabaseCellOperation` and `InsertDatabaseRowOperation` have no projection and no `evaluate_operation`
  ([DatabaseDocument.jl:31](../../../source/domain/database/DatabaseDocument.jl#L31), 44, 55); `database.md` says so. The adapter
  verbs `query_db`, `insert_into_db!`, `update_db!` and `delete_from_db!` have ODBC methods and no caller in `source` or
  `example`. A live table goes through `SqlToCellTable` instead. `DatabaseTable` also holds a live adapter in a field.
- **Example:**
  ```julia
  # today: 348 lines of DbCatalogToSyntax.jl
  # proposal: the catalog joins the tree slice
  get_tree_children_steps(::DbCatalogSchema) = ((FieldReferenceStep("tables"),),)
  format_tree_node_label(table::DbCatalogTable) = table.name
  get_document_decoration(::DbCatalogTable) = DocumentDecoration(; icon = :table)
  ```
- **Problem:** The catalog tree has no icons, no menu and no page for a node, which the tree slice gives. Two models
  of "a table of a database" exist, and the one with edits is dead, so a reader can not tell which is meant.
- **Proposal:** The catalog is a tree of the tree slice. One model of a live table stays: a document that names the
  instance and the statement and reads its rows (see DD-1). The dead table model and its two operations go, or the
  owner keeps them as the start of a planned edit of rows and says so in the plan.
- **What goes away:** most of `DbCatalogToSyntax.jl`, `is_dbcatalog_marker_eligible`, `DatabaseTable`, two operation
  types, and four adapter verbs if no plan needs them.
- **What stays:** `DbCatalogToSql` (the catalog as DDL for a model), the adapter seam, the lazy read of a level.
- **Risk and open questions:** The syntax form of the catalog works in a text backend; I did not check that the tree
  slice does. `sql-insert-update-support.md` (pending, not read) may plan a use of the change verbs.
- **Related plans:** `dbcatalog-index-support.md` (not started) adds a fifth level to each projection and would be
  smaller on the tree slice.
- **Check:** weakened, value low. The second half holds: `DatabaseTable` is built only in `DatabaseDocumentTest.jl`, no
  code evaluates the two operations, the four change verbs have no caller in `source` or `example`, and
  `database.md:84` says so; `sql-insert-update-support.md` is about SQL statement documents and plans no use of them.
  The first half does not hold as written. `DbCatalogToSyntax` is the notation of the catalog: a syntax view that
  prints to text, takes the caret of the text domain, shows in a text backend and stands inside the syntax of another
  document. The tree slice is a widget view (`DocumentTreeToWidgetTree`). They are two views of one content, which is
  what a projection is for, and not one feature written twice; FSM, process, JSON and SQL have a syntax view on the same
  ground. "Most of `DbCatalogToSyntax.jl` goes away" removes a view that exists, against first principle 11. The four
  entity projections already share their node builder and their map helpers (`_catalog_syntax_node`,
  `_catalog_forward_ref`); each is about 20 lines of declaration. What stays of the first half is a missing row: the
  catalog types have no method of `get_tree_children_steps`, `format_tree_node_label` and `get_document_decoration`, so
  an explorer or a tree shows no catalog. That is an addition of about 15 lines beside the notation, and
  `has_tree_children` must answer `nothing` for a level that was not read, so a closed node runs no query.

### DD-10 The default layout engine is one slot of the process

- **Kind:** wrong-place · **Value:** low · **Effort:** small · **Confidence:** high
- **Principle:** the settled decision "no process-global registry: state belongs to an editor"; `PAR-PER-EDITOR-STATE`.
- **Today:** A projection names its engine as a field. The default, `DeferredLayout`, reads a global at each layout:
  `const _PREFERRED_ENGINE = Ref{Any}(nothing)` ([GraphLayoutChoice.jl:19](../../../source/domain/graph/GraphLayoutChoice.jl#L19)),
  which `register_layout_engine!` writes ([GraphLayoutChoice.jl:28](../../../source/domain/graph/GraphLayoutChoice.jl#L28)).
  A package downstream calls it. The choice passes three functions: `resolve_layout_engine`, the factory, and
  `effective_engine` of an engine whose native part is missing. `graph.md` lists the result as a limit: "the registered
  factory is not a cell, so the layout cell does not depend on it".
- **Example:**
  ```julia
  # today: one engine for every editor of the process, and no cell
  register_layout_engine!((; orthogonal) -> SpringEmbedderLayout())

  # proposal: the engine is a value that the view gets, as it gets its theme
  GraphGraphToGraphLayout(engine = get_setting(appearance, :graph_layout_engine))
  ```
- **Problem:** Two editors in one process can not differ. A graph drawn before the registration keeps the old engine.
- **Proposal:** The default engine is a setting of the editor that the registration of the graph view reads, as it
  reads the scaled theme, and the layout cell reads it as a cell. `DeferredLayout` stays only as "the setting, read
  when the layout runs".
- **What goes away:** the global, `register_layout_engine!`, the limit in `graph.md`.
- **What stays:** The engine seam `layout_graph`, the engine as a field for a caller that names one, the fallback of
  `AdaptagramsLayout` when its native part is missing.
- **Risk and open questions:** A package downstream uses the registration and must move to the setting.
- **Related plans:** `packages-compose-by-seams.md` (decision C1, "no registry table") and `sdl-per-editor-state.md`
  are of the same kind; neither names this slot.
- **Check:** confirmed, value low. `GraphLayoutChoice.jl:19` and `28` are as cited, `graph.md:207` lists the limit, and
  the one caller outside the tests is downstream (`ModuleLayout.jl:132` of omnet-julia, from its `__init__`). The slot is
  against C1 of the seams plan ("no registry table, no `__init__` registration") and against the settled decision on
  process-global registries; the carve-out of `PAR-PER-EDITOR-STATE` covers only read-only data from sources that do not
  change. Two notes. The slot is recent and was planned: `release-the-binary-and-the-packages.md`, line 999, gives
  downstream "a `register_layout_engine!` call in its `__init__`", so the owner approved it with that plan. And
  `get_setting(appearance, :graph_layout_engine)` is no function of the repository; the proposal must say how a
  downstream package gives its engine to an editor with no global, for example as a keyword where the editor is built,
  or by naming the engine in its own projections, which a projection can do today. No feature is lost.

## Covered by plans

- The two ways to register a view (registry table, seam method): `packages-compose-by-seams.md`, decision C7, leaves the tables for "a later plan".
- Selection and folds on the content against a view tree: `views-compose-as-content-composes.md` (LATER) sets the model; `WorkflowStep.collapsed` and `ResearchStudy.folded` are cases of it.
- A graph that a widget view makes gets no part under the pointer (the omnet topology): `a-graph-lights-the-part-under-the-pointer.md`.
- A view that prints graphics directly names no domain part under a point: `a-view-names-the-domain-part-under-a-point.md`.
- A click that must reach the innermost part through a container such as the graph: `a-click-reaches-the-innermost-part-in-every-view.md` (in progress).
- Indexes in the catalog, a bound SQL statement, aggregation: `dbcatalog-index-support.md`, `bound-sql-statement.md`, `sql-select-aggregation-support.md`; these are features, not structure.
- A value that moves to its target over time, such as a live highlight: `chase-animation.md` (not started).

## Examined and sound

- The plot slice: pure arithmetic with no cell and no document, used by both charts. Right as it is.
- The git reads: background cells, plain values for hunks and lines, one source for a commit and its changes. It is the model for DD-1.
- The git views: the text domain for a diff, the roster for the commits, the tree slice for the changed files. Principle 8 is kept.
- The FSM diagram and the flowchart add no drawing code and reuse the graph stages. Right; only the stage to the graph repeats (DD-2).
- A series holds one cell for each column, and a sample is a reference step and no document. The reason is recorded and holds; only the two step types repeat (DD-5).
- The sequence chart does not go through the graph domain. Lanes against time are not a graph layout.
- The engine seam `layout_graph(engine, graph, sizes, constraints)` reads no cell and keys by `objectid`. Tulip and Adaptagrams are adapter packages that give an engine or a solver as a value. This follows the adapter decision.
- `GraphLayout` as a separate output for the computed geometry, and the highlight that goes around the layout cell. Right.
- The generators `generate_component` and `realize_process` are functions and no projections. The reason is recorded.
- The edits of a workflow and of a study are builders over the generic write, with no new operation type.
- `make_database_adapter(Val(kind))` is a seam by method, as the seams plan asks.
- The charts print graphics directly and no widgets, so their cost follows the pixels and not the data.
- The timeline of a study, the commits of a range and the list of workflows are rosters, with no table of their own.

## Check of the report

Checked at commit 3a9b4fae4 by a second reviewer, read only: every cited file and line was opened, each count was made
again with grep, and the plan folders were searched for the key names of each finding. No Julia and no test ran.

| Id | Verdict | Value after the check |
| --- | --- | --- |
| DD-1 | confirmed | high |
| DD-2 | confirmed-with-corrections | high |
| DD-3 | confirmed-with-corrections | medium |
| DD-4 | confirmed | medium |
| DD-5 | weakened | low |
| DD-6 | confirmed | medium |
| DD-7 | weakened | low |
| DD-8 | confirmed-with-corrections | medium |
| DD-9 | weakened | low |
| DD-10 | confirmed | low |

Seen during the check and not in the report:

- Eight printers of this area write the selection cell and the mouse target cell of their output by hand
  (`Cell(@computation map_mouse_target_forward(…))` in the four view stages, the two stages to a graph, the scroll pane
  stage and `GraphToGraphLayout`), where the kernel has `make_output_path_cells`
  ([OutputPaths.jl:29](../../../source/kernel/projection/OutputPaths.jl#L29)). The hand-written cell maps `x.selection` as it is
  and does not go through `map_selection_forward`, which is the function that carries a dormant selection.
- The layout computation of a graph reads and writes a `Ref` of its print, the corners of the last run
  ([GraphToGraphLayout.jl:133](../../../source/domain/graph/GraphToGraphLayout.jl#L133) and
  [158](../../../source/domain/graph/GraphToGraphLayout.jl#L158)), so its result depends on its earlier runs, against
  `PAR-PURE-THUNK`. The inventory lists the `Ref`; no finding names it. The corners are state of the view and belong
  with the layout that the stage already makes.
