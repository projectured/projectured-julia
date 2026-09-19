# Documentation rewrite: a viewer, an editor and an AI assistant

**Status (2026-09-17): NOT STARTED.** The survey is done. The owner answered
most questions of §4 on 2026-09-17. The open questions of §4.2 come before the
step that they affect.

**Goal:** the documentation is correct against the code, it is written in plain
technical English, and it presents ProjecturEd as a generic viewer, editor and
AI assistant for Julia data, with user interfaces that you design and that you
can also get on demand. A reader on Reddit or on Julia Discourse can find out in
a few minutes what ProjecturEd does, what it is good for, how to try it, where
its strengths are, and what does not work yet.

**Repositories:** projectured-julia, and the text of the web site repository
`projectured.github.io` (D13). The private downstream repositories change only
if a rule document gets a new name (§3.9).

**Private names:** the public documents do not name the private downstream
repositories or their products (D9). The public documents are the README,
`CONTRIBUTING.md`, `documentation/`, the web site and the posts. `plan/`, the
git history, code comments and tests can keep the names (D16).

**Sealed files:** no Markdown file is sealed. Step 1 changes code in
`source/kernel/tool/`, and no file there is sealed. `SEALING.md` changes only
after decision D10.

**Companion file:** [documentation-rewrite-survey.md](documentation-rewrite-survey.md)
holds the ten survey reports, with one findings table for each document, and
the comparison of the two binary builds (section J). It is the checklist for
Steps 3, 6 and 7.

**Split plan:** the application and its build are in
[application-and-build.md](application-and-build.md) (D18, D20 to D25).

## 1. The request

> Do a survey regarding the current state of the projectured documentation, all
> markdown files of the repository. The survey should cover inconsistencies
> between code and documentation, missing important documentation parts,
> obsolete parts of the documentation, missing aspects important for users and
> developers, etc.
>
> The whole documentation should be made up-to-data and it should also be a bit
> refactored around the idea of projectured being a generic on demand user
> interface with AI integration from the ground up. It's not merely an
> structured editor now, but a completely generic on demand user interface. The
> documentation should reflect that.
>
> The AI language should be the plain English techincal language we are using
> here. We should cut the AI slop, remove the business bullshit, we are not sales
> person and our audience are not customers. Also avoid the type of language,
> where weird inanimate objects do things, is awkward to read.
>
> Let's create a plan for what needs to be done in this regard. The final goal is
> that I want to share the project on reddit and Julia discourse. So other people
> should see the capabilities of projectured, what is it good for, how to use it,
> what's its strength, etc.

## 2. The new framing

The owner set the framing on 2026-09-17 (D3):

> the framing is too strong, you can design a user interface, the on-demand
> nature is just an addition, projectured is a viewer and an editor and an AI
> assistant using on-demand user interface, it's all of that

### 2.1 The texts

The owner and I worked on these texts in three drafts on 2026-09-17. The owner
approved the tagline and the introduction ("they are good texts"). Step 4 puts
them into the README without changes of meaning. The web site (Step 9), the
slide deck and the posts use the same texts.

Points that the owner set during the drafts:

- ProjecturEd is an application first. It is also a generic user interface for
  other Julia programs, and a set of packages.
- Viewer, editor and AI assistant have equal weight. A designed user interface
  comes first; a view on demand is an addition.
- The REPL stays in the background: one clause in the introduction. It gets
  more weight when it has its own view.
- The extension paragraph speaks about developers: each works on a domain of
  their own, without changes to the domains of others.
- The word "projectional editor" appears only in "How it works".
- The original Common Lisp ProjecturEd is not mentioned.

**Tagline** (approved). The first line of the README, the post titles:

> ProjecturEd: an application to view, edit and transform structured data with
> an AI assistant, and a generic user interface for any Julia program.

**Short tagline** (approved with the tagline). The GitHub description:

> An application to view and edit structured data with an AI assistant, and a
> generic user interface for Julia programs.

**Preface** (approved, D19). A short note directly under the tagline:

> **Status: under development.** Most features work, but ProjecturEd is not a
> finished product. Some parts are incomplete, and names and interfaces can
> still change. The [roadmap](documentation/requirement/delivery-roadmap.md)
> lists what works today and what comes next. Problem reports and questions
> are welcome as GitHub issues.

**Introduction** (approved). The first five paragraphs of the README:

> ProjecturEd is an application to view, edit and transform structured data,
> with an AI assistant. It works with about twenty kinds of data, among them
> JSON, YAML, XML, Markdown, reStructuredText, SQL, Julia code, math formulas,
> charts, graphs and state machines. It shows them in one window, in tabs and
> split panes, and one document can mix kinds: JSON inside XML inside prose.
> ProjecturEd is written in Julia. So it is also a generic user interface for
> your own Julia programs: it shows your documents, and the values of a running
> program, in the same way.
>
> A view can be a tree, a statement with syntax colours, a chart, a diagram, a
> form or a table. When the data changes, its views change with it. Most views
> are also editors: an edit in a view changes the data itself, not a text copy
> of it. You can design your own user interface from views and widgets. For data
> that has no view yet, you get one on demand: a generic view that ProjecturEd
> makes by reflection over the value, or a view that the assistant opens for
> you.
>
> The same views work in a native window, in a web browser, in a terminal, and
> without a screen for tests and scripts. A view can also go to a PDF file, an
> image or a video. The data goes to text files or to binary files. A text file
> uses the notation of its domain, and several files can refer to each other. So
> data with shared parts and mutually recursive structures comes back unchanged
> after a save and a load. Parts of a document that are not on the screen cost
> nothing, so a view can show a part of a very large document, or of an
> infinite list.
>
> The AI assistant runs inside the application, with a local model through
> Ollama or with Claude. It searches the API of the loaded packages, writes
> Julia code and runs it in the application. It changes the data with the same
> operations as your key presses. The conversation is a document too, with its
> own view, and you can also run Julia code in it yourself. An external AI
> client, for example Claude Code, can use the same tools through MCP.
>
> You can extend ProjecturEd with your own domain: its document types, the
> projections that make its views, its operations and its key bindings. A domain
> is a package of its own, and no other domain depends on it. So you can work on
> your domain without changes to other domains, while other developers work on
> theirs. Your domain gets the general features with little or no extra code:
> selection and navigation, search, copy and paste, filtered and sorted views, a
> text notation and a file format, saving, every backend, and the AI assistant,
> which can find and call your functions.

**How it works** (draft). A later section of the README:

> ProjecturEd is a projectional editor. The data is the source, and every view
> is computed from it. A projection turns the data into a view, and it turns an
> edit in the view back into an operation on the data. Projections compose: one
> view can show several kinds of data, and one piece of data can have many
> views. Each field of the data is a reactive cell. After a change, ProjecturEd
> recomputes only the parts of the views that depend on the change and are on
> the screen.

**Claims that the code must support before the posts.** Step 10 checks each
one again:

- "an application" and "in one window, in tabs and split panes": the
  application of [application-and-build.md](application-and-build.md) (D18).
- "the values of a running program" and "a generic view ... by reflection":
  the call of Step 1 that opens a window on any value (D4).
- "a view that the assistant opens for you": `open_pane!` exists; Step 1 adds
  the application window where the assistant stands beside the panes.
- "with a local model through Ollama or with Claude": Step 1 (D5, D6).
- "about twenty kinds of data": the 20 domain packages of
  `documentation/design/domain-inventory.md`.
- "comes back unchanged after a save and a load": `source/serialization/`
  (the file cut and splice for text, `Serialization` for `.pdoc`).

### 2.2 The words for a reader outside the project

A user-facing document uses the left column and defines the word at its first
use. A developer document uses the right column.

| User-facing word | Code term | Definition in one sentence |
| --- | --- | --- |
| data | document | A tree of Julia values whose fields are reactive cells. |
| view | projection output | What a projection makes from the data: widgets, text or graphics. |
| view definition | projection | A pair of functions: one makes the view, one maps an edit back. |
| view on demand | `NaturalToGraphics`, `ReflectionToWidget`, `ObjectToWidget` | A view that nobody designed for this data. |
| edit | operation | A typed change to the data. A key press and the assistant both make operations. |
| selection | selection, reference | A path from the root of the data to the selected part. |
| assistant | `Assistant`, agent | A language model with a set of tools, inside the running program. |
| tool set | `ToolSet` | The functions that the assistant and an MCP client can call. |

### 2.3 What ProjecturEd is good for

Each item names the code that exists today. The survey checked each one (§3).

- **View and edit structured files as structures.** JSON, YAML, XML, Markdown,
  RST, SQL, Julia and a math notation open, change and save through their
  parsers (`register_natural_domain!`).
- **Design a tool window without a GUI toolkit.** Widgets, tables, cards, tabs,
  split panes and a pane tree come from the widget and pane packages. The
  workbench example is a complete application of this kind.
- **Look into a running Julia program.** `reflect_document` and
  `ReflectionToWidget` show any object as a tree that opens one level at a
  time.
- **Show results.** Line, bar, histogram, scatter and strip charts, and sequence
  charts, are documents. A data point can be selected like any other part.
- **Model behaviour and run it.** A state machine produces runnable Julia code.
  A process flowchart runs with breakpoints and a live trace.
- **Ask for a change in plain words.** The assistant searches the API, writes
  Julia and runs it against the live editor. It works with Claude or with a
  local model through Ollama.
- **Drive the editor from outside.** An MCP client connects to
  `http://127.0.0.1:9876/mcp` and gets the same tools as the in-editor
  assistant.
- **Put a view somewhere else.** The same view goes to an SDL window, a browser,
  a terminal, a PDF file, a PNG file or an MP4 video.

### 2.4 The strengths

- **One mechanism for all views.** Data and projections compose. One view can
  mix domains, and one piece of data can have many views.
- **Incremental update.** A write marks the dependent cells invalid, and a read
  computes only what the screen needs. Data that is not on the screen costs
  nothing, and a lazy `ListNode` can be infinite.
- **Structured edits.** An edit is an operation on the data, for a person and
  for the assistant. The assistant does not patch text.
- **AI in the core.** The tool set is a kernel layer. The conversation is a
  document with its own view. The assistant finds the API by keywords, by a
  pattern or by a description (meaning search).
- **Pure Julia.** ProjecturEd does its own layout, text, widgets and PDF output.
  SDL only puts pixels in a window.
- **One system for three roles.** The viewer, the editor and the assistant use
  the same data, the same views and the same operations. A designed view and a
  view on demand can share one window.

### 2.5 The limits that the documentation must state

The README must list these. A reader who finds a limit by trial stops trusting
the rest.

- ~~There is no undo and no redo.~~ Undo and redo landed on 2026-09-18
  (`plan/done/undo-and-redo.md`): an operation answers its own inverse, and an
  `UndoBuffer` holds a document and its history. It is opt-in; the application
  installs one around each file and one around the window. Every public
  document that said "no undo" is corrected.
- Character type-in does not work the same way in every domain.
- The assistant needs a local Ollama server with a model, or an Anthropic API
  key.
- The packages are not in the General registry. A user clones the repository
  and uses `environment/all`.
- SDL2 and SDL_ttf must be installed for a native window.
- Commercial use needs a licence from the author (D1).
- ~~"Duplicate a pane" and "select any widget with Alt+click" are plans, not
  code.~~ Both landed while this plan ran: `Ctrl+Shift+D` duplicates the
  focused tab (`source/pane/PaneGestures.jl`), and an Alt+click selects the
  widget under the pointer (`is_whole_selection_press` in
  `source/focus/WholeSelection.jl`). The README does not list them as
  missing.

Three more limits are true today. Step 1 removes the first two (D4, D5), and
`application-and-build.md` removes the third (D18): no single call opens a
window on any Julia value, no example uses a real language model, and no single
command opens files of every supported format in one window.

## 3. The survey

### 3.1 Method

Ten read-only subagents checked every Markdown file outside `plan/done/`
against the code at commit `c28e6e30`. Each agent checked paths, names, counts,
links and code samples with grep, find and git. No agent ran Julia. One agent
made an inventory of what works today from the code alone. One agent checked
the plan folders. I checked a sample of the findings myself and found five
errors in the reports. The errata table of the companion file lists them.

Size of the documentation: 402 Markdown files. 69 of them are outside `plan/`,
with about 131,000 words. These 69 files have 1,836 long dashes, and about 200
uses of the verbs "knows", "wants", "asks", "declines", "owns" and "answers".
Not every use is wrong (§3.8).

### 3.2 Faults in the code

The survey found these faults. They are not documentation errors, but the
rewrite depends on them.

| Fault | Evidence | Effect |
| --- | --- | --- |
| The assistant prompt names guides that do not exist | `DEFAULT_ASSISTANT_SYSTEM` in [AssistantDocument.jl:18](../../source/assistant/AssistantDocument.jl#L18) and `:32` names `resource://guide/orientation`, `.../editor/finding-and-selecting`, `.../operations`. `_WHOLE_SURFACE_DESCRIPTION` in [DefaultTools.jl:19](../../source/kernel/tool/DefaultTools.jl#L19) names `.../getting-started`, `.../editor/reference`, `.../editor/selection`. The index in [Documentation.jl:53](../../source/kernel/tool/Documentation.jl#L53) names them `guide/orientation`, `kernel/finding-and-selecting`, `kernel/operation`, `guide/setup-guide`, `kernel/reference`, `kernel/selection`. | The first "MANDATORY" read of the model fails with "not found". |
| The guide list shows the metadata line as the description | `list_guides()` in [Documentation.jl:98](../../source/kernel/tool/Documentation.jl#L98) takes the first paragraph after the title. In most guides that is `> **Kind:** … · **Status:** … · **Stands on:** …`. `test_list_guides` checks only that the result is not empty. | The model sees no summary of a guide. |
| `documentation/package/README.md` is not in the index | The walk in [Documentation.jl:78](../../source/kernel/tool/Documentation.jl#L78) skips `documentation/package/`, and the per-slice roots take only folders. | `documentation/README.md` lists a document that the assistant can not read. |
| The MCP prompt and the assistant prompt differ | The docstring of `DEFAULT_ASSISTANT_SYSTEM` says that MCP uses the same text. [Mcp.jl:6](../../source/mcp/Mcp.jl#L6) uses `DEFAULT_MCP_INSTRUCTIONS`. | A statement in a docstring is false. |
| The default Anthropic model is old | `_DEFAULT_MODEL = "claude-opus-4-5-20251101"` in [Anthropic.jl:5](../../source/anthropic/Anthropic.jl#L5) | D6. |
| Code comments name documents and ids that do not exist | `package/visual/doc/widget.md` in `LayoutToGraphics.jl` (2), `WidgetToGraphics.jl` (2) and `ProjectionConfiguringTest.jl` (1). `TableToGraphics` in `GraphLayoutToGraphics.jl` (3). `PAR-REACTIVE-PRINTER` in `ObjectFieldToWidget.jl:97`. `getting-started` in the docstring of `Documentation.jl`. | A reader follows a dead reference. |
| A docstring names a parameter that the function does not have | `precompile_workload(level::Symbol = :minimal; …)` in the docstring at [Precompile.jl:114](../../example/projectured/Precompile.jl#L114). The function is `precompile_workload(; atoms)`. | Same. |

### 3.3 The front door and the audience

- **The repository is private.** `https://github.com/projectured/projectured-julia`
  answers HTTP 404 to an anonymous request. The owner makes it public after the
  documentation work (D2).
- **The licence text conflicts with contributions.** `LICENCE-PD` §3 gives no
  right to modify the software, also not for non-commercial use. The owner wants
  forks and pull requests (D1). Neither licence file has a clause about
  contributions. The owner decided both points (D1a, D1b).
- **The README headline is "a projectional editor".** The AI material exists,
  but it is the second section.
- **The README says that the assistant falls back to an offline backend.** This
  is false (§3.2 and the errata).
- **Three Julia versions.** The README and `CONTRIBUTING.md` say 1.11 or later.
  `setup-guide.md` says 1.10 or later. No `Project.toml` has a `julia` compat
  entry for 1.11. The manifest of `environment/all` says 1.13.0 (D7).
- **Two contact addresses.** The licence files and the README use
  `levente.meszaros@gmail.com`. The web site uses `projectured@gmail.com`. Both
  are correct, and `projectured@gmail.com` is the primary one (D8).
- **Old screenshots.** The six screenshots in the README are from 2026-06-23.
  `asset/image/example/assistant.png` is from 2026-09-16, and no document uses
  it. There is no screenshot of a chart, a graph, a state machine or the
  transcript, and there is no video of the Julia version.
- **The examples tour shows 6 of 109 examples.** Its "Available names" list has
  23 names. The generated catalog adds about 295 atomic documents.
- **The slide deck is the worst document.** All ten source-path footers are
  wrong. It has "Batteries included", "isn't bolted on — it's part of the
  architecture", emoji titles, and two slides that present undo, redo and
  collaboration as facts.
- **The web site is closer to the new framing than the README.** It also has a
  "not bolted on" sentence, and it says "roughly seventy thousand lines" where
  `source/` has 103,188.

### 3.4 Facts that are wrong in many documents

| Pattern | Where | Fix |
| --- | --- | --- |
| `package/kernel/main/…`, `package/<slice>/main/`, `main/<File>.jl` in prose. The link targets are correct. | all 14 kernel guides, `fsm.md`, `process.md`, `pane.md`, `versioning.md`, `debugging-guide.md`, `architecture-rules.md` | Write `source/<slice>/…`. |
| `visual/…` paths | `widget.md`, `collection.md`, `bounded-sync.md`, 5 code comments | Write the real path. |
| Files that got a new name: `Editor.jl`, `Playback.jl`, `AgentServer.jl`, `EventPattern.jl`, `Clock.jl`, `PerformanceCounter.jl`, `Intent.jl`, `ProjectionApi.jl`, `Projection.jl`, `Text.jl`, `Syntax.jl`, `Math.jl`, `Chart.jl`, `Rst.jl`, `Versioning.jl`, `Examples.jl` | many guides | Use the real file name. |
| `ProjectionApiModule` | `architecture.md`, `new-domain-guide.md`, `naming-rules.md` | `ProjectionModule`; the interface is `ProjectionInterface.jl`. |
| `TableToGraphics` and a `Table` domain | `projection-system.md`, `system-anatomy.md`, `examples-tour.md` | Remove. No such code exists. |
| `ProjecturedAssistant` is missing from every package count and table | `system-anatomy.md`, `domain-inventory.md`, `package-rules.md`, README | Add it, and say which kind of package it is. |
| Guide names without their folder prefix | `orientation.md`, `setup-guide.md`, two prompts in code | Use the names of the index, or generate the list. |
| Numbered requirement ids `#72`, `#68` | `architecture-rules.md` | `PAR-INTERFACE-DECLARES-ONLY`, `PAR-NO-TEST-DOUBLES-IN-MAIN`. |
| `package/repl/PrecompileStatements.jl` | `code-quality-rules.md`, `package-rules.md` | `asset/precompile/PrecompileStatements.jl`. |

### 3.5 Verdict for each document

KEEP means small fixes. UPDATE means several facts are wrong. REWRITE means the
structure or the framing is wrong. The companion file has the findings.

| Document | Verdict | Main work |
| --- | --- | --- |
| `README.md` | REWRITE | Framing, the assistant backends, screenshots, package tables, version, licence text |
| `CONTRIBUTING.md` | UPDATE | Licence conflict, version, link to the rules instead of copies |
| `CLAUDE.md` | UPDATE | Replace the copies of the naming, comment and test rules with links |
| `SEALING.md` | UPDATE | 10 listed paths do not exist, 13 files are missing (D10) |
| `documentation/README.md` | UPDATE | New documents, reading paths, `orientation.md`, `package/README.md` |
| `requirement/product-vision.md` | REWRITE | Framing; the MCP start is opt-in (`mcp=true`); tools the audience knows |
| `requirement/accepted-requirements.md` | UPDATE | A requirement for a view of any value, and one for the shared tool set |
| `requirement/delivery-roadmap.md` | REWRITE | Four months of work are missing |
| `design/editor-concepts.md` | REWRITE, MERGE | Base of the one "start here" document (D11) |
| `design/editor-derivation.md` | UPDATE | Framing, broken link; stays as the tour for engineers (D11) |
| `design/system-anatomy.md` | UPDATE | Assistant package, `natural` name, history sentence, a status section for the AI stack |
| `design/architecture-decisions.md` | UPDATE | Decisions for the AI stack |
| `design/domain-inventory.md` | UPDATE | Assistant, the workbench row, the reflection path |
| `rule/architecture-invariants.md` | UPDATE | Wording only: two sentences with personification |
| `rule/architecture-rules.md` | UPDATE | The "triad" section describes the old layout |
| `rule/code-quality-rules.md` | UPDATE | Paths and counts |
| `rule/division-terminology.md` | UPDATE | One module for each slice; history sentence; copied leaf text |
| `rule/layout-rules.md` | UPDATE | The first sentence contradicts §6 |
| `rule/naming-rules.md` | UPDATE | Seven exported noun-first functions |
| `rule/package-rules.md` | UPDATE | Widget does not depend on Reflection; workload levels; Assistant |
| `guide/orientation.md` | REWRITE | Every guide name is wrong |
| `guide/setup-guide.md` | REWRITE | Version, first window, the MCP section moves to a new guide |
| `guide/examples-tour.md` | REWRITE | Grouped tour and the full list |
| `guide/debugging-guide.md` | UPDATE | Three broken links, `write_example_image` |
| `guide/testing-guide.md` | UPDATE | `test_database`, the catalog, the functions that `test_all` runs, `test_ollama` |
| `guide/new-domain-guide.md` | REWRITE | `@domain`, `@projection_template`, the package root boilerplate |
| `guide/static-compilation-guide.md` | UPDATE | Title and scope; link to the real build path |
| `presentation/README.md` | UPDATE | One link label |
| `presentation/projectured-overview.md` | REWRITE | Everything |
| `package/README.md` | UPDATE | History sentence |
| `package/kernel/architecture.md` | UPDATE | Layer numbers, `clock/`, `ProjectionApiModule`; the layer table is a copy of the one in `system-anatomy.md` |
| `package/kernel/cell.md` | UPDATE | Two file names; a link to the cell kinds of `@document` |
| `package/kernel/document.md` | KEEP | A pointer to the reflection packages |
| `package/kernel/macros.md` | REWRITE | `@projection_template`, the layout list of `@document`, `@document_preset`, Rule C, a wrong example |
| `package/kernel/projection-system.md` | UPDATE | `ProjectionInterface.jl`, the pure printer, table names |
| `package/kernel/generic-projections.md` | UPDATE | `ObjectToWidget` is in the widget package |
| `package/kernel/higher-order-projections.md` | UPDATE | Locations, three file names, a contradiction |
| `package/kernel/reference.md` | UPDATE | The XML table is wrong |
| `package/kernel/selection.md` | REWRITE | Canonical paths, `SelectionMismatchException`, the in-place sync, dormant selections |
| `package/kernel/operation.md` | UPDATE | One link |
| `package/kernel/editor.md` | REWRITE | `Editor` fields, `run_frame!`, `mcp_instructions`, `on_start`, zoom keys |
| `package/kernel/finding-and-selecting.md` | KEEP | None |
| `package/kernel/devices-and-backends.md` | UPDATE | Two links, `record_video`, the help window and the command palette |
| `package/kernel/agent.md` | UPDATE | File names; link to the new assistant and MCP guides |
| `package/json/json.md` | UPDATE | The files of the slice |
| `package/xml/xml.md` | UPDATE | `push!(elem, …)` has no method |
| `package/rst/rst.md` | UPDATE | File list, "twelve" is eleven, three function names, two paths |
| `package/fsm/fsm.md` | UPDATE | Path, plan link, `supertype` field |
| `package/process/process.md` | UPDATE | Path |
| `package/graph/graph-layout.md` | KEEP | One file name |
| `package/math/math.md` | UPDATE | Two links |
| `package/chart/chart.md` | UPDATE | One file name |
| `package/sequencechart/sequencechart.md` | KEEP | A file map |
| `package/workbench/workbench.md` | REWRITE | `Assistant` is not a `WorkbenchDocument`; a projection name; a constructor; the pane program |
| `package/conversation/transcript.md` | UPDATE | The composer (`ConversationEditor.jl`) |
| `package/versioning/versioning.md` | UPDATE | Two paths |
| `package/text/text.md` | UPDATE | `TextLine` has a layout now; `span_path` |
| `package/syntax/syntax.md` | REWRITE | 2 of 9 syntax types; the gesture tables |
| `package/graphics/graphics.md` | KEEP | 3 of 8 graphics types |
| `package/widget/widget.md` | UPDATE | 42 widget types, not 33; history; "first-class" |
| `package/pane/pane.md` | KEEP | One path label |
| `package/collection/collection.md` | KEEP | One path |
| `package/reflection/bounded-sync.md` | UPDATE | History paragraph, "the visual package" |
| `package/adaptagrams/README.md` | KEEP | One keyword |
| `package/executable/README.md` | UPDATE | The project tree, `BuildSpec` fields |
| `tool/juliac-trim/README.md` | KEEP | None |
| `test/graph/reference/README.md` | KEEP | None |
| `example/filesystem/fixture/**/*.md` | do not change | Test fixtures |

### 3.6 Missing documentation

**Tier 1: the new framing needs these.**

| Subject | Code | Now |
| --- | --- | --- |
| The in-editor assistant | `source/assistant/` (1,407 lines) | No document names `ProjecturedAssistant`. |
| How to use the assistant: backends, keys, models, Ollama, meaning search | `source/anthropic/`, `source/ollama/`, `source/kernel/llm/` | No document names `ANTHROPIC_API_KEY`, the Ollama address or a default model. |
| How to connect an MCP client | `source/mcp/Mcp.jl` | Nothing in the repository names Claude Code, Claude Desktop or an MCP client configuration. |
| A view of any value | `source/natural/` (`NaturalToGraphics`, "almost any document"), `source/reflection/` (`reflect_document`, `ReflectionToWidget`), `source/widget/ObjectToWidget.jl` | Three mechanisms. No document says how they relate. `reflect_document` has no caller in this repository except its tests. |
| The natural notation | `source/natural/` (668 lines) | One line in `system-anatomy.md`, with a wrong name. |
| The help window (F1) and the command palette (Ctrl+Shift+P) | `source/gesturehelp/` (838 lines) | One sentence in `devices-and-backends.md`. |
| Keyboard and mouse for a user | the `@gestures` tables of 22 files | No user-facing summary. |
| Use ProjecturEd from your own project | a downstream project can use `[sources]` path dependencies | No guide. |
| The assistant's tool discovery | `plan/done/assistant-finds-the-api.md`, `three-kinds-of-search.md` | Partly in `agent.md`. |

**Tier 2: large slices with no guide.** `sql` (3,455 lines), `julia` (2,504),
`layout` (3,116), `style` (2,460), `serialization` with `.pdoc` and `.pred`
(1,561), `markdown` (1,289), `formula` (1,102), `plot` (869), `clipboard`
(808), `screen` (770), `yaml` (758), `book` (750), `domain` (720), `dbcatalog`
with `database` and `odbc` (1,300), `gesturelog` (545), `filesystem` (461), the
composer in `conversation`, and the `Workspace` and file wrapper of
`workbench`.

**Tier 3: small slices.** `primitive`, `focus`, `inspector`, `tooltip`,
`dragging`, `component`, `fileformat`, `projection`, `tulip`, `video`. A short
paragraph in `system-anatomy.md` is enough for each.

### 3.7 Duplication and contradictions

- `editor-concepts.md`, `editor-derivation.md` and the README have the same
  diagram, and the first two have the same worked example. Both are the first
  entry of "Start here".
- The naming rules, the comment rule and the test catalog each exist in two or
  three of `README.md`, `CONTRIBUTING.md` and `CLAUDE.md`.
  `documentation/README.md` itself says "Cite, do not repeat".
- The 17-layer table exists in `architecture.md` and in `system-anatomy.md`.
- `orientation.md` and `setup-guide.md` both explain the three search tools.
- The leaf text exists in `division-terminology.md` and in `package-rules.md`.
- `higher-order-projections.md` says that its projections "never touch any
  specific domain", and then lists three that select by a domain type.
- `layout-rules.md` says "every widget … decides its size", and its §6 says the
  opposite.
- `product-vision.md` calls the terminal and web backends future work and then
  lists them as delivered.

### 3.8 Language

- 1,836 long dashes outside `plan/`.
- Marketing and slop: "first-class" (17), "under the hood" (3), "batteries
  included", "out of the box", "seamless", "you literally cannot type a syntax
  error", "eliminates all of these problems by construction".
- Personification: "knows" (31), "wants" (28), "asks" (12), "declines" (11),
  "owns" (63), "answers" (48). Not every hit is wrong: "a domain owns its
  operations" is a normal statement about code ownership. Examples that are
  wrong: "A domain knows nothing about how it is displayed", "the layer wants an
  implementation fragment", "every widget decides its size", "A step type that
  wants to appear in a rules pattern".
- The best models for the new style: `pane.md`, `collection.md`,
  `transcript.md`, `rst.md` (it has a "Known limits" section), `fsm.md`,
  `process.md`.

### 3.9 Constraints on the rewrite

- **A guide name is part of the assistant's interface.** The index derives the
  name from the path: `documentation/guide/x.md` is `guide/x`, and
  `documentation/package/<slice>/x.md` is `<slice>/x`. A move or a new name
  changes `resource://guide/<name>`. The guard of Step 2 must check every
  `resource://guide/…` string in `source/` and `documentation/`.
- **The index does not read `plan/`.** A fact that a user or the assistant needs
  must be in `documentation/`.
- **Other repositories link to four rule documents.** 14 files in the two
  private downstream repositories link to `naming-rules.md`,
  `architecture-invariants.md`, `division-terminology.md` and
  `layout-rules.md`. Keep these four names. `tool/juliac-trim/README.md` links
  to `static-compilation-guide.md`.
- **Private names stay out of public text (D9).** Today they occur in
  `documentation/README.md` (the folder structure "is the one omnet-julia
  uses"), `documentation/rule/code-quality-rules.md` (two links to
  `omnet-team/policy/code-quality-rules.md`), one comment in
  `source/dragging/DraggingWrapper.jl`, three test files, 13 pending plans,
  28 done plans and 129 commit messages. The name patterns are `omnet-julia`,
  `omnetpp-julia`, `inet-julia`, `omnet-team`, `omnetpp-team` and `OMNET-NG`.
  `OMNeT++` and `INET` are public products; they can stay. Only the public
  documents must lose the names; plans, commit messages, code comments and
  tests can keep them (D16).
- **The seal audit reads `architecture-invariants.md`.** A change must not
  change the meaning of a `PAR-…` rule without the owner's approval.
- **The fixtures** under `example/filesystem/fixture/` are test data.
- **Work on `main` continues.** New plans and code arrive every day. A fact
  that the rewrite writes must be checked again at Step 10.

### 3.10 The plan folders

- About 40 of the 53 pending plans have had no real change since the audit of
  2026-08-12. None of them is done secretly.
- `animation-global-time.md`, `discovered-example-catalog.md`,
  `document-native-variant-layouts.md`, `kernel-cleanup.md` and
  `printer-locality-session-log.md` are superseded. They can move to
  `plan/obsolete/`.
- `plan/tentative/gesture-help.md` is done through `plan/done/command-palette.md`.
- `plan/tentative/layout-extensions.md` and `search-input-widget.md` link to
  plans that are in `plan/done/` now.
- `nlnet-application.md` asks for money to build web-backend parity, but a web
  backend exists. Its positioning ("AI-native", model-agnostic, offline-capable,
  MCP) must agree with the new README.

## 4. Decisions

### 4.1 The owner's answers of 2026-09-17

> for 1, the licence stays. I will make the repository public. People will be
> able to fork and submit PR. For commercial purposes a licence is to be
> obtained from me, for public domain work it can be used freely.
> for 2, when we finished the documentation work
> for 3, the framing is too strong, you can design a user interface, the
> on-demand nature is just an addition, projectured is a viewer and an editor
> and an AI assistant using on-demand user interface, it's all of that
> for 4, yes
> for 5, Anthropic should use the latest claude model whichever it is and more
> future proff, the system in general could use ollama LLM by default
> for 6, both projectured@gmail.com and levente.meszaros@gmail.com is fine but
> the former is the primary address, I'm (Levente) the main author
> for 7, no, that's hidden
> for 8, yes
> for 9, yes

| # | Question | Decision |
| --- | --- | --- |
| D1 | Licence and contributions | The dual licence stays. Non-commercial use is free. Commercial use needs a licence from the author. The repository accepts forks and pull requests. The README and `CONTRIBUTING.md` say this in plain words. They do not call the code "open source". |
| D2 | When the repository becomes public | After the documentation work: Step 11, after the review of Step 10. |
| D3 | The framing | ProjecturEd is a viewer, an editor and an AI assistant. A user interface is designed; a view on demand is an addition (§2.1). |
| D4 | One call that opens a window on any Julia value | Yes, in Step 1. |
| D5 | The assistant with a real model | Yes, in Step 1. Ollama is the default backend of the whole system. The assistant example can run with a real backend. |
| D6 | The Anthropic model | The Anthropic backend uses the newest Claude model that the key can use, and it must keep working when a new model comes out (Step 1). |
| D8 | Contact | `projectured@gmail.com` is the primary address; `levente.meszaros@gmail.com` is also correct. Levente Mészáros is the main author. The README and `CONTRIBUTING.md` name the author and the primary address. The licence files stay as they are. |
| D9 | The private downstream application | It stays hidden. No public document names it or shows it. Step 11 removes the names (§3.9). |
| D10 | The seal of the four renamed kernel files | The seal carries over to the new names (Step 8). |
| D11 | Merge the two "start here" documents | Yes: `design/concepts.md` and `design/engineer-tour.md` (§7). |
| D13 | The web site | In scope, for the text (Step 9). |

The second answers of 2026-09-17:

> for 1, yes for non-commercial purposes the code can be modified
> for 2, yes
> for 3, it's ok to keep the private names there, we just no advertise it
> for 4, that is also private, but the name doesn't matter

| # | Question | Decision |
| --- | --- | --- |
| D1a | Modification | Non-commercial use includes modification. `LICENCE-PD` §3 gets a clause that allows it (Step 11). |
| D1b | Contribution terms | `CONTRIBUTING.md` states terms under which a contribution can be offered under both licences (Step 8). |
| D16 | Private names in `plan/` and in the history | They can stay. The repository becomes public as it is. Only the public documents do not name the private repositories. |
| D17 | The name "omnest" | Private, like the others. It can stay where it is; no public document advertises it. |

The third answers of 2026-09-17, after the three drafts of §2.1:

> very good, save the tagline and the introduction, they are good texts!
>
> we should add a preface that this project is under development currently,
> it's mostly working but it's not a finalized product
>
> for the question, yes, we already have a build system, but it should be
> perhaps generalize a bit. take a look at how omnet-julia builds binaries and
> copy what can be applied from there

| # | Question | Decision |
| --- | --- | --- |
| D18 | An application entry point before the posts | Yes. One command and one binary open any number of files, in every supported format, in one window with the assistant. The existing build system (`ProjecturedBuilder`, `ProjecturedExecutable`) becomes more general, and it takes what applies from the binary build of omnet-julia ([application-and-build.md](application-and-build.md)). |
| D19 | A preface | Yes: the project is under development, most features work, and it is not a finished product (§2.1). |

The fourth answers of 2026-09-17:

> for 1, yes
> for 2, we can have both using command line arguments to select
> for 3, move and call the environment build not tool, makes more sense
> for 4, should
>
> put the build thing into a separate plan from the documentation plan

| # | Question | Decision |
| --- | --- | --- |
| D19 | The text of the preface | Approved as written in §2.1. |
| D20 to D23 | The application window, the builder, the binary release, the build environment | See §2.1 of [application-and-build.md](application-and-build.md). That plan holds the application and build work from now on. |

### 4.2 Open questions

Each one has my recommendation. Each one comes before the step that it names.

| # | Question | Recommendation | Before |
| --- | --- | --- | --- |
| D7 | Which Julia version do the documents name? | The version that the quick start is tested with. Add a `julia` compat entry to match. The manifest of `environment/all` is from Julia 1.13.0. | Step 4 |
| D12 | Where do the drafts of the two posts go? | In §9 of this plan. They are one-time text, not documentation. | Step 11 |
| D14 | Which forums? | r/Julia and the Julia Discourse. A wider forum only after the first feedback. | Step 11 |
| D15 | Videos? | Yes. Three short recordings (Step 9). | Step 9 |

## 5. Steps

The implementation follows the global rules: a dedicated git worktree as a
sibling in `workspace/`, one commit for each step, explicit paths in each
commit, and this plan updated as each part is done.

Before you run Julia, read the process rules: one Julia process at a time, a
memory cap of 20 GB, a timeout, and output to a log file.

**Delegation.** A Sonnet subagent does the mechanical work: the sweep of
Step 3, the reference updates of Step 6, the tier 2 guides of Step 7. Its brief
names the findings of the companion file and the writing rules. Opus writes the
front door (Step 4), the new user guides (Step 5) and the tier 1 guides of
Step 7, because the framing and the audience matter most there. Opus reads
every diff of a subagent before the commit.

### Step 0: the worktree and the baseline

- [x] Get the owner's answers to §4. Write them into this plan (2026-09-17).
- [x] Make the worktree `workspace/projectured-julia-documentation`, branch
      `documentation-rewrite` (2026-09-17).
- [x] Record the baseline: the counts of the guard of Step 2 (write the guard
      first, if it is not there yet), the number of long dashes, the list of
      broken links.

**The baseline of 2026-09-17**, from `julia test/suite/documentation.jl`:

| What the guard found | Count |
| --- | --- |
| a path `package/<slice>/main` or `package/<slice>/doc` | 28 |
| a link whose file is not there | 28 |
| a phrase the rules forbid | 26 |
| a link to a heading the file does not have | 14 |
| a path under `visual/` | 10 |
| a `resource://guide/…` that names no guide | 8 |
| a document with no summary after its header | 1 |
| **all** | **115** |

Every document under `documentation/` already has its header line. The report
that fails nothing holds 121 lines: 96 sentences that give a verb of a person
to an object, and 25 slices under `source/` that no guide names. Step 7 writes
the missing guides.

### Step 1: the code faults and the entry points (tool, assistant, mcp, anthropic, ollama slices; the example package)

Each part is one commit with its test.

- [ ] Replace the guide names in `DEFAULT_ASSISTANT_SYSTEM` and
      `_WHOLE_SURFACE_DESCRIPTION` with names that exist. Better: make the list
      from the index, so that a new name can not break it.
- [x] Make `list_guides()` skip the metadata line. Extend `test_list_guides` so
      that no description starts with `> **Kind:**`. The test walks every
      guide of the list: 146 assertions, and none of them carries the header.
- [ ] Make the docstring of `DEFAULT_ASSISTANT_SYSTEM` true about MCP.
- [ ] Fix the dead references in code comments and the docstring of
      `precompile_workload` (§3.2).

**D4: a window on any Julia value.** Done on 2026-09-17 in `b83a6567`:
`run_value_viewer(value)` and `make_value_viewer(value)` in
`example/projectured/ValueViewer.jl`, with `test_value_viewer()`. The default
is the reflected tree, which opens one level at a time and draws a struct, a
dictionary, a vector and a value that refers to itself. `tree = false` draws
the value itself through `NaturalToGraphics`, and that path still raises for a
dictionary, because it reflects the fields of the implementation; the test
marks it broken.

- [x] Add one function that opens a window on any value. It uses
      `NaturalToGraphics`, which shows a struct with no view of its own through
      the reflection table of `ObjectToSyntax`. A keyword selects the tree view
      of `reflect_document` and `ReflectionToWidget` for a large or running
      object, which opens one level at a time.
- [x] Put the function beside `run_example` and `run_file_editor` in
      `example/projectured/`, unless `package-rules.md` gives it another home.
      Name it by the naming rules, for example `run_value_viewer`.
- [x] Test without a window: the view of a plain struct, a `Dict`, a `Vector`,
      and a struct that refers to itself. The test prints the view instead of
      writing an image, because the printed output is what a reader of a
      failure can act on.

**D5: Ollama is the default backend, and the assistant example can use a real
model.**

- [x] `Assistant` gets `backend = :ollama` as its default. If
      `ProjecturedOllama` is not loaded, a submit gives the existing error, which
      lists the loaded backends. The error also names the package to load.
- [x] If the Ollama server does not answer, or the model is not on the server,
      the error names the server address, the models that the server has, and
      the `ollama pull` command. The code does not choose another model without
      a word. `_describe_chat_refusal` says it, and `get_ollama_models` asks the
      server what it has; a server that is down answers an empty list rather
      than a second error.
- [x] Every place that makes an `Assistant` for a person uses the default
      backend. The application passes the backend of its command line, and an
      `Assistant()` with no argument names `:ollama`. An example keeps its
      `FakeLlm`, which wins over the named backend, so a sweep reaches no
      server.
- [x] The assistant example gets `backend` and `model` keywords. The call is
      `run_assistant_example(; backend = :ollama)` and not
      `run_example("assistant"; backend = …)`: the gallery passes its keywords
      to the window, and the backend belongs to the document, which the example
      builds. `make_assistant_document_example(; backend, model)` is the
      factory. Without a keyword it keeps `FakeLlm()`, so the test sweeps reach
      no model, and the first turn of the canned transcript says that the
      replies are canned and names the call.
- [ ] The meaning search uses the meaning model of the Ollama backend
      (`nomic-embed-text`). The assistant guide of Step 5 says how to pull it.
- [ ] Test: the error texts with a fake server, and one live test with Ollama.
      The default and the example keywords are covered: `test_workbench()` 144
      pass with the known 3 fails and 2 broken, `test_ollama()` 99 pass,
      `test_conversation()` 167 pass, `test_application()` 72 pass, and the
      printer walk of the assistant example reports no error.

**D6: the newest Claude model.**

- [x] When `model` is empty, the Anthropic backend asks the Models API
      (`GET /v1/models`) once in each process. The list arrives newest first,
      so the first model whose `capabilities.thinking.types.adaptive.supported`
      is true is the newest one this backend can drive. Every current model
      takes tools, and the list has no capability for it, so the choice reads
      the thinking capability alone.
- [x] If the list request fails, or no key is exported, the backend uses the
      alias `claude-opus-5`. An alias and not a dated id, so the name still
      works after a new model comes out.
- [x] A value in the `model` field overrides the choice.
- [x] The request body uses only parameters that every current model accepts.
      It already did: `_thinking_param` sends `{"type": "adaptive", "display":
      "summarized"}` and nothing else, with no `budget_tokens`, no sampling
      parameter and no prefill.
- [ ] A reply with `stop_reason: "refusal"` shows in the transcript as a
      refusal, not as an empty reply. (Still open.)
- [x] Before you write the code, check the order and the fields of the list
      response against the live API documentation. Checked on 2026-09-18 at
      `platform.claude.com/docs/en/api/models/list`: the list is newest first,
      and each entry carries `id`, `created_at`, `display_name` and a
      `capabilities` block with `thinking.types.adaptive.supported`.
- [x] Test: the choice from a recorded list response, with no network. One
      live test runs only when `ANTHROPIC_API_KEY` is set. `test/anthropic/`
      and `ProjecturedAnthropicTest` are made the way `test/ollama/` and
      `ProjecturedOllamaTest` are: 20 assertions pass and the live one skips.
      `test_anthropic()` runs in `test_all()`, and the tree, naming and package
      graph guards hold.

**D18: the application and its build** are in
[application-and-build.md](application-and-build.md). This plan needs its
Steps 1 to 5: the application command for the README quick start (Step 4 here),
and the binary for the release (Step 11 here).

Steps 1 to 7 of that plan are done (2026-09-17), so Step 4 here can name the
commands as they are:

- `bin/projectured a.json b.md` runs the application from a checkout, and
  `bin/build_projectured` builds the binary. The options are
  `--window=pane|workbench`, `--backend=sdl|web`,
  `--assistant=ollama|anthropic|none`, `--model=NAME`, `--root=DIRECTORY` and
  `--mcp`.
- [build-guide.md](../../documentation/guide/build-guide.md) is the guide for
  both, and Step 11 attaches the archive that `bin/build_projectured
  --distribution` writes.
- **Build the release archive again after this plan removes the private names
  from `documentation/`**, because the bundle carries that folder.

**Close of the step.**

- [x] D7: the `julia` compat entry. The documents name Julia 1.11 or later,
      because `[sources]` needs it, and say that the environment of the
      repository is resolved with 1.13. The two packages that declared a
      `julia` compat said 1.10, which no `[sources]` entry can hold; both say
      1.11 now.
- [ ] Test: `test_list_guides()`, `test_read_guide()`, `test_search_guides()`,
      `test_ollama()`, the new anthropic tests, and the tests of each changed
      file.

### Step 2: the writing rules and the documentation guard

- [x] Write `documentation/rule/writing-rules.md` (§6).
- [x] Write the static guard `test/suite/documentation.jl` with
      `test_documentation()`, beside `test/suite/naming.jl`. It loads no
      package. It fails when:
  - a relative link in a Markdown file outside `plan/` has no target file or no
    target heading;
  - a `resource://guide/<name>` string in `source/` or `documentation/` names no
    guide, with the name derived as in `_all_guides()`;
  - a document under `documentation/` (except a Marp deck) has no header line,
    or has no summary paragraph after the header;
  - a document has a phrase from the list in `writing-rules.md`;
  - a document names a dead path pattern (`package/<slice>/main`, `visual/`).
- [x] The guard also prints a report that does not fail: sentences with the
      verbs of the personification list, and the slices under `source/` that no
      guide names.
- [ ] The check for the private names of §3.9 is not part of the guard. It
      runs in Step 11 on the public documents.
- [x] Add `test_documentation()` to `test_all()`, as `test_naming()` is.
- [x] Run the guard on the old documents. Record the counts in this plan.
      Until Step 3 sweeps them, `test_documentation()` fails; that is what the
      baseline above records.

### Step 3: the mechanical sweep

- [x] A Sonnet subagent fixes the patterns of §3.4 and the broken links, one
      commit for each group of documents.
- [x] Remove the history sentences that the survey lists.
- [x] The guard reports zero broken links and zero dead paths.

Done on 2026-09-17, in seven commits (`1059da75` to `e8af10c8`): 115
violations to 0, over 49 files, 163 lines added and 162 removed. The agent
also found three faults outside its brief, which a later step must answer:

- `naming-rules.md` still describes an `Api` layer marker and `*Api.jl` files;
  no such file is in `source/` (the real ones are `*Interface.jl`).
- `architecture-rules.md` shows the label `package/kernel/test/layering/
  CheckLayering.jl`, although the link beside it is right.
- The stage table of `system-anatomy.md` names `Sdl.jl`, `Web.jl`,
  `backend/Console.jl` and `backend/Pdf.jl`, which are not the file names.

I corrected one thing the sweep wrote: the slide deck claimed thirty domains
(its own older claim), and there are about twenty.

### Step 4: the front door

Done on 2026-09-17 in `e70040b0`, except the roadmap, the requirements, the
decisions and the two older guides, which are the rest of this step.

- [x] `README.md`, at most about 300 lines, in this order:
  1. The tagline and the preface of §2.1.
  2. The introduction of §2.1, as approved.
  3. A video or an animated image, and three screenshots.
  4. What you can do with it: the list of §2.3, each item with a link.
  5. Quick start: download the application binary (D22) or clone the
     repository; open files with the application command (D18, from
     `application-and-build.md`); the assistant with Ollama (the default) or
     with an Anthropic key; a window on your own value.
  6. How it works: the text of §2.1, then data, views, edits, cells and the tool
     set. One diagram. A link to `design/concepts.md`.
  7. Status and limits: the list of §2.5.
  8. Where to read next: one path for a user, one for a Julia developer, one for
     a contributor.
  9. The repository layout, short.
  10. Licence, author and contact: free for non-commercial use, modification
     included; a commercial licence from the author; forks and pull requests
     are welcome (D1, D1a, D1b). Author: Levente Mészáros. Contact:
     `projectured@gmail.com` (D8).
- [x] `design/concepts.md` (D11): the one "start here" document, made from
      `editor-concepts.md` and §5.4 of `editor-derivation.md`. No code. The
      statement, the words of §2.2, the five ideas, a designed view and a view
      on demand, the assistant, one walk from a key press to the screen, what
      works and what does not.
- [x] `design/engineer-tour.md` (D11): `editor-derivation.md` with a new name,
      the new framing at the start, and its §5 moved forward. Use `git mv`.
      Update every link to the two old names. The guard finds the links that
      remain.
- [x] `requirement/product-vision.md`: why a user interface on demand, why the AI
      is in the core, and a comparison with tools that the audience knows:
      Pluto, Jupyter, VS Code with an AI extension, Makie with Observables, the
      Julia GUI and web packages. MPS, Lamdu and Hazel move to a short
      "prior work" section.
- [x] `requirement/delivery-roadmap.md`: delivered, in progress and next, from
      `plan/done/` and `plan/pending/`. Undo, redo and uniform type-in stay in
      "next".

A subagent surveyed the two plan folders for it (2026-09-18). What it found:
nothing in the old roadmap was false, but four months of work sat under it,
unsaid. 122 of the 264 done plans changed after the roadmap's last real edit,
in twelve themes; 29 of the 57 pending plans are part built; 21 are not
started. Five items are named "superseded" and can move to `plan/obsolete/`
(§3.10 lists them): `kernel-cleanup.md`, `document-native-variant-layouts.md`,
`printer-locality-session-log.md`, `animation-global-time.md` and
`discovered-example-catalog.md`.
- [x] `requirement/accepted-requirements.md`: a requirement for a view of any
      value, and one for the tool set that the assistant and an MCP client
      share. They are `PR-VIEW-OF-ANY-VALUE` and `PR-ONE-TOOL-SET`. **The owner
      still reviews them.**
- [x] `design/architecture-decisions.md`: why the tool set is a kernel layer,
      why one tool set for the assistant and MCP, why the core tool runs Julia
      instead of a fixed list of commands. Each one states its cost as well.
- [x] `guide/setup-guide.md`: install, the first window, the SDL libraries, the
      first-start time, what to do when a load fails.
- [x] `guide/examples-tour.md`: the examples in groups (data files, widgets and
      layout, charts, models, the assistant, the workbench), and the REPL call
      that lists every name. There are 106 examples; the tour groups them all
      and keeps its six deep sections.
- [x] `documentation/README.md`: the new documents and the reading paths.

### Step 5: the new user guides

Each guide has runnable code. Run each snippet once, in one warm session.

- [x] `guide/assistant-guide.md`: open the assistant; Ollama as the default
      backend, the server address, the default model, `ollama pull`; the
      Anthropic backend, the key and the rule that chooses the newest Claude
      model; how to name a model; the meaning search; what to ask; what the
      assistant can change; the limits.
- [x] `guide/mcp-guide.md`: start the server (`mcp = true`), the address, a
      client configuration for Claude Code and for a generic MCP client, the
      tools and resources that the client gets, one client for each editor.
- [x] `guide/view-your-data-guide.md`: first a designed user interface: a small
      tool window from widgets and domain views, a form from a `@document`
      struct, a chart of your numbers. Then the views on demand: a window on
      your own value (D4), and the reflection view of a running object.
- [x] `guide/keyboard-and-mouse-guide.md`: the common keys (arrows, `Alt` +
      arrows, clipboard, tabs, zoom, collapse), and F1 and Ctrl+Shift+P for the
      full live list. Every key in it comes from a `@gestures` declaration of
      the code. Step 10 must press them in a window: the guide is written from
      the declarations, not from a session.
- [x] `guide/own-project-guide.md`: use the packages from your own project,
      which package to load, `run_editor!`, a backend.

### Step 6: the reference documents

- [x] Kernel guides: REWRITE `macros.md`, `selection.md` and `editor.md`. UPDATE
      the others by the findings.
- [x] Procedure guides: REWRITE `new-domain-guide.md` around `@domain` and
      `@projection_template`, with the package root that loads. UPDATE the
      others.
- [x] Package guides: REWRITE `workbench.md` and `syntax.md`. UPDATE the others.
- [x] Design documents: UPDATE `system-anatomy.md`, `domain-inventory.md`,
      `engineer-tour.md`.
- [x] Make one table of the 17 layers, in `system-anatomy.md`, and link to it
      from `architecture.md`.

Done on 2026-09-18 by a subagent, in four commits (`87a18368` to `ffcc2031`):
32 files, 939 lines added and 579 removed, with the guard at zero after each
group. It checked each survey finding against the tree of today rather than
against the tree the survey read, and it ran the snippets of the rewritten
guides in a session.

I checked its claims and corrected one: two guides said that every structural
projection is written with `@projection_template`. Eleven of the twenty-three
domain-to-syntax projections use it, and seventeen files in all.

What it reported and did not fix:

- Two timing figures in `testing-guide.md` are not measured again.
- `widget.md` says that an extension widget is printer-only and its reader a
  no-op; the reader of `WidgetSwitch` is not a no-op.

### Step 7: the missing package guides

- [x] Tier 1: `package/assistant/assistant.md`, `package/natural/natural.md`,
      `package/reflection/reflection.md` (the value reflection, and how it
      relates to `NaturalToGraphics` and `ObjectToWidget`),
      `package/gesturehelp/gesturehelp.md`, `package/mcp/mcp.md`.
- [x] Tier 2: one guide for each slice of §3.6, tier 2. `database`, `dbcatalog`
      and `odbc` share one guide, and `anthropic` and `ollama` share
      `package/llm/llm.md`. Fifteen slices had none; each has one now.
- [x] Tier 3: not needed. Every slice has a guide of its own, so the paragraph
      that would stand in for one has nothing left to cover.
- [x] The guard's list of slices with no guide is empty.

### Step 8: rules, contributor documents, seal list, plans

- [ ] Rule documents: the fixes of §3.5. Wording only in
      `architecture-invariants.md`.
- [x] `CONTRIBUTING.md` and `CLAUDE.md`: links instead of copies (§3.7). Keep
      the sealed-file warning in `CLAUDE.md`. `CLAUDE.md` is 98 lines from 112,
      and its reading list is four links and two sentences.
- [x] `CONTRIBUTING.md`: the licence in plain words, the contribution terms
      (D1b), the fork and pull request process, the author and the primary
      contact address (D8).
- [x] `documentation/README.md` and `code-quality-rules.md`: remove the private
      names (§3.9). `code-quality-rules.md` links to a private policy file;
      copy the rules that a contributor needs into the document, or drop the
      link. One document under `documentation/package/` still names a private
      checkout: `graph/graph-layout.md`, which the reference sweep has open.
      A comment in `source/builder/BuildContext.jl` and one in
      `source/dragging/DraggingWrapper.jl` name it too, and D16 lets a code
      comment keep it.
- [x] `SEALING.md` (D10): make the inventory from the real include order of
      `ProjecturedKernel.jl`, and keep each seal state:
  - `cell/PerformanceCounter.jl`, `clock/Clock.jl`, `event/EventPattern.jl` and
    `gesture/GestureRecognizer.jl` are sealed. Their new names
    `cell/PerformanceCounterModule.jl`, `clock/ClockModule.jl`,
    `event/EventPatternModule.jl` and `gesture/GestureRecognizerModule.jl` get
    🔒.
  - `operation/Intent.jl`, `agent/AgentServer.jl`, `editor/Editor.jl` and
    `editor/Playback.jl` are not sealed. Their new names `IntentModule.jl`,
    `AgentServerModule.jl`, `EditorModule.jl` and `PlaybackModule.jl` get ⬜.
  - `projection/ProjectionApi.jl` and `projection/Projection.jl` are not sealed.
    The files that took their place, `ProjectionModule.jl`,
    `ProjectionInterface.jl`, `ProjectionDefaults.jl` and `ProjectionMacro.jl`,
    get ⬜.
  - `binding/GestureBindingModule.jl` is new and gets ⬜.
  - Check the list against the include order with a script, as the survey did.
- [x] Plans: move the five superseded plans and `plan/tentative/gesture-help.md`
      to `plan/obsolete/`. Fix the two links in `plan/tentative/`.
      `plan/pending/` holds 52 plans now. A link from a plan in `plan/done/` to
      a moved plan is left: a done plan is history and says where it pointed.
- [x] Fix the facts of `nlnet-application.md`. The text is a funding pitch that
      the owner submits, so it keeps its own words; a note at its head lists
      the five facts that moved, among them the web backend it asks money for
      and the word "open source", which D1 rules out.

### Step 9: pictures, videos, slides, web site

- [x] Make new screenshots with `generate_example_screenshots`: the assistant,
      the workbench, a chart, a sequence chart, a state machine, a rendered RST
      page, a reflection view. Every example was drawn again on 2026-09-18:
      106 images, 36 of them new. Two faults were fixed to make them right: the
      workbench example declared no render size and came out as a strip, and
      the generator needs the SDL package loaded, which writes the image.
- [ ] Record three short videos with `record_example_video`: the assistant
      builds a view from a request; a chart with zoom and selection; a view of a
      running object that opens level by level. **Deferred by the owner on
      2026-09-19.**
- [x] Rewrite `presentation/projectured-overview.md` from the new README. No
      emoji, no source-path footers. 31 slides, with the ten screenshots, the
      five ideas, the assistant and MCP, the limits, and where to start. It
      drops every claim it could not trace to the README or a guide: undo,
      redo, versioning, collaboration, and the thirty domains.
- [x] D13: correct the text of the web site in `projectured.github.io`: the
      framing of §2.1, the line count of `source/`, the "not bolted on"
      sentences, and the author and contact of D8. Use the new screenshots.
      The site must not name the private application.

      **Done on 2026-09-19, with the owner's word, as commit `b873226` in the
      site repository. It is committed and not pushed: the push publishes the
      live site, and that is the owner's step** (`git -C
      workspace/projectured.github.io push`).

      What the commit does: the title, the hero, the meta text and a redrawn
      social card carry the approved framing; the assistant section says what
      the tool set does; the line count says "more than a hundred thousand";
      the footer names the author. The hero picture and the demo video, which
      showed the private application, are replaced by the picture the editor
      draws of its own assistant, and `hero.jpg`, `mm1k-demo.mp4` and
      `mm1k-poster.jpg` leave the tree, so the site no longer serves them. They
      stay in the history of that repository. The page was rendered once with a
      headless browser to check it.

      **A second pass, the same day, as commit `ac6edd0`, also not pushed.**
      The owner read the first pass and said that the page still sold a
      product. That was right: the first pass corrected the framing and the
      facts, and kept the voice. The second pass rewrites all 67 headings and
      paragraphs of the page as plain description of the program as it is. It
      removes the claim of a sandbox, which was false: `execute_julia_code`
      runs in the process of the editor. The lineage paragraph names the Common
      Lisp editor and says what the Julia version adds. The domain list follows
      the domains of the repository today. The layout, the pictures and the
      examples did not change. A script did the replacement from a table of old
      text and new text, and a check of the tag balance passed after it.

      **The videos are deferred by the owner (2026-09-19).** The posts keep
      their `[the video]` placeholder, and the site shows a picture until one
      exists.

      What the site said before:

      - The hero picture and the whole "See it in action" section show the
        private application: an M/M/1/K queueing study with an OMNeT++ model
        running inside the editor, in the image, the alt text, the caption and
        the video. D9 says that application stays hidden.
      - "roughly seventy thousand lines" — `source/` holds 106,966 lines, and
        the whole tree 170,263.
      - The title, the hero and the meta text carry the old framing, and one
        heading is "Built for an AI collaborator — not bolted on".
      - The contact is already `projectured@gmail.com`; the author is not
        named.

      The prepared edit puts the approved tagline in the title and the meta
      text, says in the hero what the application does, rewrites the assistant
      section around the tool set, writes the measured line count, and puts the
      new workbench screenshot where the private pictures are. A video of this
      editor alone would be better than a screenshot, and that is the video
      item above, which is not started.

### Step 10: the review

- [x] A fresh-reader test: a subagent with no knowledge of the repository gets
      only the README and the guides that it links. It followed the quick start
      on 2026-09-18 and ran sixteen commands, every one that needs no window.

**What it found, and what I did.** Five faults, all in documents this plan
wrote, and all now fixed and re-run:

1. `setup-guide.md` wrote `print_object(editor.document)`, and no page binds
   `editor`. A reader met an `UndefVarError`. The guide now shows the document
   it just parsed, and says that `print_object` answers a string rather than
   writing it, so a script prints it itself.
2. The same guide called `print_example()` "the JSON example as text". It
   writes the whole structure down to each graphics primitive and each font —
   thousands of lines. The guide now says what it writes and when to reach for
   it, and it names `print_natural_text` for the text of a document.
3. `examples-tour.md` said `catalog()` answers the same list as `examples`. It
   answers 487 entries against 106: one for each document of each domain with
   each projection. The guide says that now.
4. `own-project-guide.md` said `print_document` "gives the view as data". It
   answers an IO map; `iomap.output` is the view.
5. `view-your-data-guide.md` showed three steps as if they were a script. Step
   2 is where a projection of your own is written, and the guide says so.

It also checked one thing I could not: every link and every screenshot it
followed exists. It could not check anything that needs a window, and its
machine had a warm cache, so the first-start cost is still unmeasured.

The model tag `qwen3.8:27b` looked wrong to it. It is right: that model is on
the server of this machine, and it is the default of `source/ollama/Ollama.jl`.
- [x] A language review against `writing-rules.md`, one document group at a
      time.

      **Done on 2026-09-19 and 2026-09-20.** The owner asked whether the
      language was technical and informative, and the honest answer was no: the
      documents of this plan were, and the older ones and the web site were
      not. Two subagents then read every older document, one for
      `documentation/package/kernel/` and `documentation/design/`, one for the
      guides, the rules, the older slice guides and `CONTRIBUTING.md`. They
      changed the form of a sentence and kept its fact: a verb of a person on an
      object became what the program has, returns or computes, a dash or a
      parenthesis with more information became a sentence, and a history
      sentence became the constraint in the present tense. For the `PAR-…`
      rules they changed single words only.

      The report of the guard went from 124 lines to 21, and each of the 21 has
      a person as its subject (a reader, a caller, a consumer) or is a quoted
      example. The guard itself reports zero violations.

      **What the review found that was a fault of fact, all corrected:**

      - Every layer number in the kernel guides was one too low, because the
        fault layer is layer 1. The layer list of `architecture.md` was right.
      - `operation.md` listed three imports and the layer has five
        (`FaultModule`, `CellModule`, `DocumentModule`, `ReferenceModule`,
        `SelectionModule`). `reference.md` said ten fragments and then eleven;
        the module includes eleven, and the diagram missed
        `ReferencePatternString.jl`. Both guides gave an "index in the DAG"
        that no other document defines, and now say which layers are above.
      - 33 link labels carried a file name from before a rename.
      - `writing-rules.md` named five kinds for the header, and
        `documentation/README.md` defines seven others. The index governs. Four
        documents of this plan took the kind of their index row, and
        `header_violations` now reports a kind outside the list.
      - `naming-rules.md` said 12 colliding names and then 13. The count is 10.
      - `graph-layout.md` named a private checkout. It names the OMNeT++ source
        tree.
- [x] An assistant test: `list_guides()` shows a real summary for each guide,
      and each guide name in the prompts resolves. If the machine has the
      memory free, one real session with Ollama.

`test_list_guides()` walks every guide of the list, 146 assertions, and none of
them carries the header line. The guard checks every `resource://guide/…` string
of `source/` and `documentation/`, and finds none that answers to nothing.

**The live session (2026-09-18, no GPU, the model on the processor).** One turn,
asked: "Name the ProjecturEd function that opens a window on any Julia value.
Use search_api to find it. Answer with the name only."

| Model | Time | What it did |
| --- | --- | --- |
| `mistral:latest` (7B) | 13 s | called no tool and answered nonsense |
| `qwen3.8:27b` (the default) | 49 s | searched the API by description, said "Not it — let me refine the search", searched again, searched the guides, read `resource://guide/guide/view-your-data-guide`, and answered `run_value_viewer` |

So the local path works end to end, and the guide written today is what the
model read to answer. The small model is not enough for a tool-using turn, which
is why the assistant guide names the model to pull.
- [x] Check again every claim of §2.3, §2.5 and the roadmap against `main`.

**The check of 2026-09-19, after 92 commits of other work landed on `main`.**
The documents said things that stopped being true in one day, which is the risk
§3.9 named. What changed, and what the documents say now:

- **Undo and redo exist.** Every public document that said "no undo" is
  corrected: the README, `concepts.md`, `engineer-tour.md`, the assistant
  guide, the vision, the deck and both post drafts. The roadmap lists it under
  "Delivered", and says it is opt-in.
- **The workbench domain is gone**, and with it `--window`. The application is
  one window, drawn in its own chrome, and a tab typed with a tool's name
  becomes that tool: `assistant`, `repl`, `explorer`, `log`, `gestures`,
  `selection`, `reference` (the names are the `get_insertion_aliases` of the
  code). The keyboard guide has a section for them.
- **New options**: `--context=TOKENS` and `--gesture-log`. **New commands**:
  Open and Save As in the menu bar. **New functions**: `save_user_interface`
  and `load_user_interface` for the whole window.
- **The editor survives a fault.** The README, `concepts.md`, the roadmap and
  the post drafts say so, with a link to `fault.md`.
- **The kernel has 18 layers**: `fault` is the first one. `architecture.md`
  listed 17 with the old numbers, and `division-terminology.md` said
  seventeen; both are rebuilt from the kernel root. `SEALING.md` missed
  `operation/Inversion.jl` and `operation/Description.jl`.
- **There are 105 examples**, not 106: the workbench example went.
- The assistant measurement is 29 of 33 turns on the local default model, from
  `plan/done/assistant-recovers-from-a-miss.md`.

**A fault found on the way, not fixed here.** A screenshot of `bin/projectured`
on this display shows the panes in the top left part of the window: the window
shell does not get the size of its window, so it hugs its content. The comment
in `example/projectured/Application.jl` says "the window scene gives the shell
the size it was opened at", and the picture says it does not. The README has no
picture of the application until that is fixed.
- [ ] `test_documentation()` passes. Record the final counts.

### Step 11: the posts, and close

- [x] Write the drafts of §9: one for r/Julia, one for Julia Discourse. Both
      wait for the video and for the owner's words in the two marked places.
- [ ] Check that the public documents do not name the private repositories or
      products (§3.9, D16, D17). The result of the `git grep` must be empty.
- [ ] D1a: change `LICENCE-PD` §3 so that it allows modification for
      non-commercial purposes. The owner approves the wording.
- [ ] D22: attach the archive of `application-and-build.md` Step 5 to a GitHub
      release. The owner approves the release.
- [ ] Move this plan and the survey file to `plan/done/`.
- [ ] The owner reads the drafts, makes the repository public (D2) and posts.

## 6. The writing rules

Step 2 writes these rules into `documentation/rule/writing-rules.md`. They
apply to every document under `documentation/`, the root Markdown files, and
docstrings.

**Plain technical English.** The rules follow Simplified Technical English
(ASD-STE100):

- One word for one thing. Do not use a synonym for variety.
- Active voice. Simple tenses: present, past, future, imperative.
- An instruction has at most 20 words. A description has at most 25 words. A
  paragraph has at most six sentences, and one topic.
- "must" for a requirement, "can" for a possibility.
- No contractions, no idioms, no metaphors.
- An abbreviation gets its full form at its first use.
- A procedure has numbered steps. A condition comes before its instruction.
- No additional information between dashes or in parentheses. Write a new
  sentence.

**No slop and no marketing.** Do not use: "seamless", "powerful", "robust",
"elegant", "first-class", "out of the box", "batteries included", "under the
hood", "it's not X — it's Y", "not bolted on", "by construction" as a claim,
"literally", "customers", "value proposition". Do not use emoji in a heading or
a list. Use bold only for a term where the document defines it, or for the
first words of a list item. Do not group items in threes to make a rhythm. A claim names the code that makes it true, or a
measurement.

**No personification.** The subject of a sentence is a person (you, the user,
the developer) or a program part that computes, returns, stores or calls
something. An object does not know, want, ask, decide, refuse, offer, promise
or tell.

| Do not write | Write |
| --- | --- |
| A domain knows nothing about how it is displayed. | A domain has no reference to a projection. |
| A card folds only from its chevron. | A click on the chevron folds the card. A click elsewhere on the card does not. |
| A flow breaks at the width it is offered. | The flow layout breaks a line at the width that its parent gives it. |
| The reader declines the gesture. | The reader returns `nothing` for the gesture, so the next reader gets it. |
| The assistant isn't bolted on — it's part of the architecture. | The tool set is a kernel layer. The assistant and an MCP client use it. |

**Present state only.** A document says what is. It does not say what was, what
moved, or what a refactor did. History goes into `plan/done/` and into the
commit message.

**Honest status.** A feature that exists only in a plan is not in the present
tense. A limit is stated where a reader looks for the feature.

**Header and summary.** Each document starts with the title, the header line
(`Kind`, `Status`, `Stands on`), and then one paragraph of at most three
sentences that says what the document answers. The assistant shows that
paragraph in its guide list.

## 7. The target structure

```
README.md                         REWRITE  the front door
CONTRIBUTING.md                   UPDATE
CLAUDE.md                         UPDATE   links, not copies
SEALING.md                        UPDATE   after D10
documentation/
  README.md                       UPDATE   the map and the reading paths
  requirement/
    product-vision.md             REWRITE
    accepted-requirements.md      UPDATE
    delivery-roadmap.md           REWRITE
  design/
    concepts.md                   NEW      from editor-concepts.md (D11)
    engineer-tour.md              RENAME   from editor-derivation.md (D11)
    system-anatomy.md             UPDATE
    architecture-decisions.md     UPDATE
    domain-inventory.md           UPDATE
  rule/
    writing-rules.md              NEW
    (seven rule documents)        UPDATE   the file names stay
  guide/
    orientation.md                REWRITE  for the assistant
    setup-guide.md                REWRITE
    examples-tour.md              REWRITE
    assistant-guide.md            NEW
    mcp-guide.md                  NEW
    view-your-data-guide.md       NEW
    keyboard-and-mouse-guide.md   NEW
    own-project-guide.md          NEW
    debugging-guide.md            UPDATE
    testing-guide.md              UPDATE
    new-domain-guide.md           REWRITE
    static-compilation-guide.md   UPDATE   the file name stays
  package/
    assistant/ natural/ mcp/ gesturehelp/             NEW (tier 1)
    reflection/reflection.md                          NEW (tier 1)
    sql/ julia/ layout/ style/ serialization/ ...     NEW (tier 2)
    (existing guides)                                 by §3.5
  presentation/
    projectured-overview.md       REWRITE
```

**Reading paths** for `documentation/README.md` and the README:

- **A user:** README → `design/concepts.md` → `guide/setup-guide.md` →
  `guide/examples-tour.md` → `guide/assistant-guide.md` →
  `guide/keyboard-and-mouse-guide.md`.
- **A Julia developer:** README → `design/concepts.md` →
  `guide/view-your-data-guide.md` → `guide/own-project-guide.md` →
  `design/engineer-tour.md` → the kernel guides.
- **A contributor:** the developer path → `rule/` →
  `guide/new-domain-guide.md` → `guide/testing-guide.md` → `CONTRIBUTING.md`.
- **The assistant:** `guide/orientation.md` → the guide index → the search tools.

## 8. Risks

- **A new guide name breaks the assistant.** The guard of Step 2 checks every
  guide name in code and documents. Step 1 makes the prompt list from the
  index.
- **A rule document gets a new name.** Links in the private downstream repositories
  break. Keep the four names of §3.9. If a name must change, change the links in
  both repositories in the same change.
- **A document describes a plan as a feature.** Check each claim against the
  code when you write it, and again in Step 10. Work on `main` continues during
  the rewrite.
- **A wording fix changes a rule's meaning.** In `architecture-invariants.md`,
  change wording only. Ask the owner before any change of meaning.
- **The survey has errors.** The sample check found five. Treat each finding as
  a lead and check it first.
- **The work is large.** About 131,000 words to read and a large part to
  rewrite. The guard makes the mechanical work checkable, so a Sonnet subagent
  can do it. Opus reviews each diff.
- **Julia runs for the snippets and the media.** One process at a time, with a
  memory cap and a timeout. Do not unload an Ollama model that another session
  uses.
- **Concurrent commits on `main`.** Work in the worktree, rebase often, and
  commit with explicit paths.
- **A public document names a private repository.** New work on `main` can add
  a name after the check. Run the check of Step 11 immediately before the
  repository becomes public.
- **The newest Claude model is not the expected one.** The rule of Step 1 can
  choose a model of a higher price tier, or a new small model. The assistant
  guide states the rule, the status shows the model in use, and the `model`
  field overrides the choice.
- **Ollama as the default needs memory.** A local model can take most of the
  memory of a small machine. The assistant guide names the memory that the
  default model needs, and a smaller model that also works.

## 9. The post drafts

Each draft has: what ProjecturEd is, a video, what it is good for, how to try it
in three commands, what does not work yet, the licence, and the feedback that
the owner wants. Each draft is short. It has no marketing words and no emoji.

**Both drafts are written below (2026-09-18). They wait for two things**: the
video of Step 9, which is not recorded, and the owner's own words in the two
places marked `[…]`. The owner reads and changes them before anything is
posted.

### 9.1 r/Julia

> **Title:** ProjecturEd: an application to view, edit and transform structured
> data with an AI assistant, and a generic user interface for any Julia program
>
> I have been building ProjecturEd for a while, and it is now far enough to
> show.
>
> It opens structured data — JSON, YAML, XML, Markdown, reStructuredText, SQL,
> Julia code, math, charts, graphs, state machines, about twenty kinds — in one
> window, in tabs and split panes, and one document can mix kinds: JSON inside
> XML inside prose. The views are not text: a view is computed from the data,
> and most views take your edits, so an edit changes the data itself rather
> than a text copy of it.
>
> Because it is written in Julia, it is also a user interface for your own
> programs. `run_value_viewer(value)` opens a window on any value — a struct, a
> dictionary, a vector, an object of a running program — and shows it one level
> at a time. If you write a view for your own data, you get the general
> features with it: selection, navigation, search, copy and paste, filtering,
> sorting, a text notation, a file format, and every backend.
>
> An AI assistant runs inside the application, with a local model through
> Ollama or with Claude. It searches the API of the loaded packages, writes
> Julia and runs it in the program, and changes the data with the same typed
> edits your key presses make. An external client, for example Claude Code,
> gets the same tools over MCP.
>
> Because an edit is a typed operation, it has an inverse: `Ctrl+Z` takes back
> a change of yours or of the assistant, and the history is a document you can
> read. A failure in a view or in a tool does not stop the editor; it takes the
> broken change back and shows what went wrong.
>
> [the video]
>
> To try it:
>
> ```
> git clone https://github.com/projectured/projectured-julia
> cd projectured-julia
> bin/projectured
> ```
>
> The first start compiles, which takes a few minutes. `bin/build_projectured`
> makes a binary that starts in under a second.
>
> What does not work yet: type-in of single characters is not the same in
> every domain; a click selects only where a projection wires it; a table
> renders but does not take an edit. Undo and redo work in the application. The assistant
> needs a local Ollama server with a pulled model, or an Anthropic key. Linux
> on x86-64, with SDL2 for the native window.
>
> The licence is free for non-commercial use, modification included; commercial
> use needs a licence from me. Forks and pull requests are welcome.
>
> What I would like to hear: [what the owner wants to know].

### 9.2 Julia Discourse

> **Title:** ProjecturEd — structured data, editable views, and an AI assistant
> in one window
>
> **Category:** Community → Show and tell
>
> ProjecturEd is an application to view, edit and transform structured data
> with an AI assistant. It is written in Julia, and it is also a generic user
> interface for a Julia program.
>
> **The idea.** The data is the source, and every view is computed from it. A
> projection is a pair of functions: a printer that makes the view, and a
> reader that turns an edit in the view back into a typed operation on the
> data. Projections compose, so one view can show several kinds of data, one
> piece of data can have many views, and a filter, a sort or a search is one
> more step in front of any domain. Every field of the data is a reactive cell,
> so a change recomputes only the parts of the views that depend on it and are
> on the screen.
>
> **What that gives you today.** About twenty domains open, show, edit and save
> their data. Views run in a native window, in a browser, in a terminal, and
> with no screen at all for a test; a view also goes to a PDF with selectable
> text, a PNG or an MP4. `run_value_viewer(value)` shows any Julia value, one
> level at a time, without a projection written for it. The AI assistant works
> on the same data with the same operations, through Ollama or Claude, and an
> external MCP client gets the same tools. An operation answers its own
> inverse, so undo and redo are one more document around your data, and a
> fault in a printer, a reader or a tool is contained where it happened
> instead of stopping the editor.
>
> [the video]
>
> ```
> git clone https://github.com/projectured/projectured-julia
> cd projectured-julia
> bin/projectured                 # the window
> ```
>
> The README has the quick start, the guides and the limits:
> <https://github.com/projectured/projectured-julia>
>
> **What does not work yet.** Type-in of single characters differs between
> domains. A click selects only where a projection wires it. A
> table renders and navigates but does not take an edit. The packages are not
> in the General registry, so you clone the repository. Linux on x86-64, with
> SDL2 and SDL_ttf for the native window.
>
> **Licence.** Free for non-commercial use, modification included. Commercial
> use needs a licence from me. Forks and pull requests are welcome.
>
> **Feedback I am after.** [what the owner wants to know] — and I am glad to
> answer questions about the projection model, the reactive cells, or how a
> domain of your own would fit.

## 10. Out of scope

- New features beyond Step 1: undo and redo, duplicate a pane, Alt+click
  selection, uniform type-in.
- The renames of the seven noun-first functions. They belong to
  `naming-rule-violations.md`.
- The content of `plan/done/`.
- The documentation of the private downstream repositories, except for broken
  links.
- A registration in the General registry. It depends on D1.
