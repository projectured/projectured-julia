# Roadmap

> **Kind:** what · **Status:** current · **Stands on:** [accepted-requirements.md](accepted-requirements.md)

What ProjecturEd does today, what is half built, and what comes next. It is written from the plans under `plan/done/` and `plan/pending/`, and each line names the code or the plan that settles it.

The order of the work has been the same from the start: **make the whole path work first** — data, view, edit, back to the data — **then widen it** with more domains, more views and more backends, and only then go outward to other machines and other people.

## Delivered

**The editing path.** An edit is an operation on the data. Insert and delete work on a collection (`make_insert_elements_operation`, `make_delete_elements_operation`), a character edit works inside a string, a number, a key, an XML text and an attribute (`ReplaceStringRangeOperation`), and the reader chain turns a key press into one of them. Julia and SQL are typed through their parsers with live completion; Markdown, math and prose take text as well.

**Twenty domains.** JSON, YAML, XML, Markdown, reStructuredText, SQL, Julia, math, formulas, charts, sequence charts, graphs, state machines, processes, books, the file system, the conversation, the assistant, versioning and the reflection view of any object. [domain-inventory.md](../design/domain-inventory.md) lists them with what each one holds.

**Views that are not text.** Line, bar, histogram, scatter and strip charts, sequence charts, a graph with two layout engines, a state machine as a diagram, and a form or a table of widgets. A table cell takes a click, the arrows, typed characters and Backspace ([edit-inside-a-table-cell.md](../../plan/done/edit-inside-a-table-cell.md)); a drag inside a cell does not select text yet. A data point of a chart is selected like any other part.

**The general steps.** A filter, a sort, a search, a focus, a collapse and a copy are steps in front of any data, so a new domain gets them without code. A search runs over one document by default (`search_references`, `search_documents`).

**The clipboard.** Copy, cut, note and paste move a part of the data, not a text. Where a text conversion exists, the system clipboard carries the text of it.

**Windows.** Tabs and split panes with a pane tree, a command palette, a Files pane, and one application command that opens files of every supported format (`bin/projectured`). A tab typed with a tool's name — `assistant`, `gestures`, `log`, `faults`, `statistics`, `selection`, `reference`, `explorer` or `repl` — opens that tool, and the toolbar has a button for each tool of the window. The window is drawn in its own chrome — a menu bar, a toolbar, a status line, a context menu on a right press and a tooltip under the pointer — and the chrome is a document like the rest ([shell.md](../package/platform/shell/shell.md)). The whole window saves to one file and opens back from it (`save_user_interface`, `load_user_interface`).

**Undo and redo.** An operation answers its own inverse, and an `UndoBuffer` is a document that holds another document and the steps that take it back ([undo.md](../package/platform/undo/undo.md)). It is opt-in: the application puts one around each file and one around the window, and `Ctrl+Z` takes back an edit of a person or of the assistant.

**The editor survives a fault.** A failure in a printer, a reader, an operation, a backend or a tool is contained where it happened: the editor takes a broken change back, draws what went wrong where the view would be, and goes on ([fault.md](../package/platform/fault/fault.md)).

**Backends.** A native window through SDL, a browser over HTTP and WebSocket, a terminal with colour, and no screen at all for a test. A view also goes to a PNG image, a vector PDF with selectable text, or an MP4 video.

**Files.** A text file in the notation of its domain, and a binary file for anything else. Several files can refer to each other, so data with shared parts and mutually recursive structures comes back unchanged after a save and a load.

**The AI assistant.** A tool set in the kernel: search the API, read a guide, run Julia in the running program, and change the data with operations. It works with a local model through Ollama, or with Claude through the Anthropic API. The same tool set answers an external client over MCP. Measured on eleven problems with three seeds each, the local default model solves 29 of 33 turns.

**A binary.** `bin/build_projectured` compiles the application into a directory that runs with no Julia and no checkout, and a distribution build tests a copy of it with the checkout hidden.

**Underneath.** The reactive cell system sets the cell kind per field, every IO map is reactive, and the packages are split one per domain, which is what keeps a domain independent of the others.

## In progress

Each line names the plan that carries it.

| What | How far |
| --- | --- |
| Select any widget and paste it into a tab ([select-a-widget-and-paste-it-into-a-tab.md](../../plan/pending/select-a-widget-and-paste-it-into-a-tab.md)) | twelve steps of thirteen |
| Character type-in in every domain ([live-example-construction.md](../../plan/pending/live-example-construction.md), [simplest-syntax-document.md](../../plan/pending/simplest-syntax-document.md)) | JSON, YAML and XML rebuild from an empty document; SQL, Julia, text and graph do not |
| XML parity with the reference reader ([xml-to-syntax-lisp-parity.md](../../plan/pending/xml-to-syntax-lisp-parity.md)) | five phases of six |
| Excel-style formulas ([excel-julia-formulas.md](../../plan/pending/excel-julia-formulas.md)) | the formulas compute; the operations and the host embedding are open |
| A version history view ([object-versioning.md](../../plan/pending/object-versioning.md)) | the overlay works; the history view is open |
| Every document type in the catalogue ([catalog-all-documents.md](../../plan/pending/catalog-all-documents.md)) | three workstreams of four, with fourteen faults marked in the catalogue |
| Cheaper reactive cells ([cheap-reactive-cells.md](../../plan/pending/cheap-reactive-cells.md)) | four phases of five |
| The template engine behind the printers ([projection-template-engine.md](../../plan/pending/projection-template-engine.md)) | XML and Julia are converted, math in part, two domains not at all |
| A faster start ([faster-executable-startup.md](../../plan/pending/faster-executable-startup.md)) | one tier of five |
| The suite to green ([test-suite-green.md](../../plan/pending/test-suite-green.md)) | eight items of fourteen |

## Next

**A user sees these.**

- **A click that selects in every view.** A click works where a projection wires it, and elsewhere it does nothing.
- **Links between documents** ([document-link-feature.md](../../plan/pending/document-link-feature.md), [document-locator.md](../../plan/pending/document-locator.md)). A reference from one document to another does not exist yet.
- **Richer SQL** ([bound-sql-statement.md](../../plan/pending/bound-sql-statement.md), [sql-select-aggregation-support.md](../../plan/pending/sql-select-aggregation-support.md), [dbcatalog-index-support.md](../../plan/pending/dbcatalog-index-support.md)).

**A developer sees these.**

- Another backend ([cairo-glfw-backend.md](../../plan/pending/cairo-glfw-backend.md)), a parallel projection ([parallel-projection.md](../../plan/pending/parallel-projection.md)), an animation timeline ([chase-animation.md](../../plan/pending/chase-animation.md)).
- A configuration view for the projections ([configuration-overlay-widget.md](../../plan/pending/configuration-overlay-widget.md)).

**Further out.** Live collaboration between two people, a plugin loaded into a running editor, an annotation domain over any document, and ProjecturEd editing its own source.

## What does not change

- The data is the source. Every view is computed from it.
- A projection is a pair: a printer and a reader.
- A domain is a package of its own, and no other domain depends on it.
- Every field of a document is a reactive cell, and indexing is 1-based.
- The tool set is a layer of the kernel, and the assistant and an external client share it.
