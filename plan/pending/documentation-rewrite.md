# Documentation rewrite: an on-demand user interface with AI from the ground up

**Status (2026-09-17): NOT STARTED.** The survey is done. The owner's decisions
in §4 come before Step 1.

**Goal:** the documentation is correct against the code, it is written in plain
technical English, and it presents ProjecturEd as a generic, on-demand user
interface for Julia data with AI integration from the ground up. A reader on
Reddit or on Julia Discourse can find out in a few minutes what ProjecturEd
does, what it is good for, how to try it, where its strengths are, and what does
not work yet.

**Repositories:** projectured-julia. Two small links in omnet-julia and
inet-julia change only if a rule document gets a new name (§3.9). The web site
repository `projectured.github.io` is in scope only if the owner says so (D13).

**Sealed files:** no Markdown file is sealed. Step 1 changes code in
`source/kernel/tool/`, and no file there is sealed. `SEALING.md` changes only
after decision D10.

**Companion file:** [documentation-rewrite-survey.md](documentation-rewrite-survey.md)
holds the ten survey reports, with one findings table for each document. It is
the checklist for Steps 3, 6 and 7.

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

This section is a proposal. The owner confirms it or changes it (D3).

### 2.1 The statement

> ProjecturEd is a Julia library that builds a user interface on demand for any
> data. You do not design the screens in advance. A value, a file, a document or
> a running program gets an interactive view when you ask for one. The view can
> be a generic one, made by reflection over the value. It can be a domain view:
> a JSON tree, an SQL statement, a chart, a state machine. Or the AI assistant
> can write the view for you. Every view is live: it shows the current data.
> Every view is editable: an edit in the view changes the data.
>
> The AI assistant is part of the same system. It runs Julia inside the running
> editor. It reads the data and the views with the same functions that a person
> calls from the REPL, and it changes them with the same operations that a key
> press makes. An external AI client, for example Claude Code, gets the same
> tools through MCP.

Projectional editing stays in the documentation as the mechanism: a view is the
output of a projection, and a projection maps an edit back to the data. The
mechanism moves from the headline to the "how it works" section.

### 2.2 The words for a reader outside the project

A user-facing document uses the left column and defines the word at its first
use. A developer document uses the right column.

| User-facing word | Code term | Definition in one sentence |
| --- | --- | --- |
| data | document | A tree of Julia values whose fields are reactive cells. |
| view | projection output | What a projection makes from the data: widgets, text or graphics. |
| view definition | projection | A pair of functions: one makes the view, one maps an edit back. |
| edit | operation | A typed change to the data. A key press and the assistant both make operations. |
| selection | selection, reference | A path from the root of the data to the selected part. |
| assistant | `Assistant`, agent | A language model with a set of tools, inside the running program. |
| tool set | `ToolSet` | The functions that the assistant and an MCP client can call. |

### 2.3 What ProjecturEd is good for

Each item names the code that exists today. The survey checked each one (§3).

- **Look into a running Julia program.** `reflect_document` and
  `ReflectionToWidget` show any object as a tree that opens one level at a
  time. omnet-julia uses this for its watch and inspector panes over a running
  simulation.
- **Edit structured files as structures.** JSON, YAML, XML, Markdown, RST, SQL,
  Julia and a math notation open, change and save through their parsers
  (`register_natural_domain!`).
- **Build a tool window without a GUI toolkit.** Widgets, tables, cards, tabs,
  split panes and a pane tree come from the widget and pane packages. The
  omnet-julia IDE is built this way.
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
- **A real application.** omnet-julia builds its whole IDE on it (D9).

### 2.5 The limits that the documentation must state

The README must list these. A reader who finds a limit by trial stops trusting
the rest.

- There is no undo and no redo (`grep -rn UndoOperation source/` finds nothing).
- Character type-in does not work the same way in every domain.
- No single call opens a window on any Julia value (D4).
- No example uses a real language model. Every example passes `FakeLlm()` (D5).
- The assistant needs an Anthropic API key or a local Ollama server.
- The packages are not in the General registry. A user clones the repository
  and uses `environment/all`.
- SDL2 and SDL_ttf must be installed for a native window.
- The licence allows only non-commercial use of unmodified copies (D1).
- "Duplicate a pane" and "select any widget with Alt+click" are plans, not code.

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
  answers HTTP 404 to an anonymous request. The clone command in the README and
  the link on the web site do not work for the public (D2).
- **The licence conflicts with contributions.** `LICENCE-PD` §3 gives no right
  to modify the software, also not for non-commercial use.
  `CONTRIBUTING.md` asks the reader to fork the repository and send a pull
  request (D1).
- **The README headline is "a projectional editor".** The AI material exists,
  but it is the second section.
- **The README says that the assistant falls back to an offline backend.** This
  is false (§3.2 and the errata).
- **Three Julia versions.** The README and `CONTRIBUTING.md` say 1.11 or later.
  `setup-guide.md` says 1.10 or later. No `Project.toml` has a `julia` compat
  entry for 1.11. The manifest of `environment/all` says 1.13.0 (D7).
- **Three contact addresses.** The licence files and the README use
  `levente.meszaros@gmail.com`. The web site uses `projectured@gmail.com`. The
  git identity is `levente.meszaros@omnest.com` (D8).
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
| Use ProjecturEd from your own project | omnet-julia does it with `[sources]` | No guide. |
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
- **Other repositories link to four rule documents.** 14 files in omnet-julia and
  inet-julia link to `naming-rules.md`, `architecture-invariants.md`,
  `division-terminology.md` and `layout-rules.md`. Keep these four names.
  `tool/juliac-trim/README.md` links to `static-compilation-guide.md`.
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

## 4. Decisions for the owner

Each decision has my recommendation.

| # | Question | Recommendation |
| --- | --- | --- |
| D1 | The licence forbids modification. Do the posts wait for a new licence, and does `CONTRIBUTING.md` keep the fork-and-pull-request process? | Decide the licence before the posts. Readers on Reddit and Discourse ask first whether the code is open source. If the licence stays, `CONTRIBUTING.md` must say how a contribution is possible, and the README must say plainly that the code is source-available, not open source. |
| D2 | The repository is private. When does it become public? | Make it public before the posts, after Step 10. |
| D3 | Is the statement of §2.1 correct? | Confirm or edit it before Step 4. Every front-door document starts from it. |
| D4 | Add one call that opens a window on any Julia value? | Yes, in Step 1. A small `run_…` function over `NaturalToGraphics`, with the reflection view as an option. Without it, the headline claim needs a paragraph of setup code. |
| D5 | Add a way to run the assistant example with a real model? | Yes, in Step 1. For example a `backend` keyword on the assistant example, and a clear error when the backend package is not loaded. |
| D6 | Which default model for the Anthropic backend? | A current model, for example `claude-sonnet-5` or `claude-opus-5`. The owner chooses. |
| D7 | Which Julia version do the documents name? | The version that the quick start is tested with. Add a `julia` compat entry to match. |
| D8 | Which contact address is public? | One address for the README, the licence files, `CONTRIBUTING.md` and the web site. |
| D9 | Can the public documents name omnet-julia (OMNET-NG) and show its IDE? | Yes, if omnet-julia is public or soon public. It is the strongest example of an on-demand user interface. |
| D10 | The kernel file renames of 2026-09-14 changed four sealed files: `cell/PerformanceCounter.jl`, `clock/Clock.jl`, `event/EventPattern.jl` and `gesture/GestureRecognizer.jl` got the `Module` suffix. Does the seal carry over to the new names? | The owner decides for each file. Then `SEALING.md` gets the real inventory, in load order. |
| D11 | Merge `editor-concepts.md` and `editor-derivation.md`? | Make `design/concepts.md` the one "start here" document, from `editor-concepts.md` and §5.4 of `editor-derivation.md`. Keep `editor-derivation.md` as `design/engineer-tour.md` for engineers. |
| D12 | Where do the drafts of the two posts go? | In §9 of this plan. They are one-time text, not documentation. |
| D13 | Is the web site in scope? | Yes, for the text only: the framing, the line count, the contact address, the "not bolted on" sentence. |
| D14 | Which forums? | r/Julia and the Julia Discourse. A wider forum only after the first feedback. |
| D15 | Videos? | Yes. Three short recordings (§5, Step 9). A post with a video gets more attention than a post with screenshots. |

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

- [ ] Get the owner's answers to §4. Write them into this plan.
- [ ] Make the worktree `workspace/projectured-julia-documentation`.
- [ ] Record the baseline: the counts of the guard of Step 2 (write the guard
      first, if it is not there yet), the number of long dashes, the list of
      broken links.

### Step 1: the code faults (projectured, tool, assistant, mcp, anthropic slices)

- [ ] Replace the guide names in `DEFAULT_ASSISTANT_SYSTEM` and
      `_WHOLE_SURFACE_DESCRIPTION` with names that exist. Better: make the list
      from the index, so that a new name can not break it.
- [ ] Make `list_guides()` skip the metadata line. Extend `test_list_guides` so
      that no description starts with `> **Kind:**`.
- [ ] Make the docstring of `DEFAULT_ASSISTANT_SYSTEM` true about MCP.
- [ ] Fix the dead references in code comments and the docstring of
      `precompile_workload` (§3.2).
- [ ] D4: the call that opens a window on any value, with a test.
- [ ] D5: the assistant example with a real backend.
- [ ] D6: the default Anthropic model.
- [ ] Test: `test_list_guides()`, `test_read_guide()`, `test_search_guides()`,
      and the tests of each changed file.

### Step 2: the writing rules and the documentation guard

- [ ] Write `documentation/rule/writing-rules.md` (§6).
- [ ] Write the static guard `test/suite/documentation.jl` with
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
- [ ] The guard also prints a report that does not fail: sentences with the
      verbs of the personification list, and the slices under `source/` that no
      guide names.
- [ ] Add `test_documentation()` to `test_all()`, as `test_naming()` is.
- [ ] Run the guard on the old documents. Record the counts in this plan.

### Step 3: the mechanical sweep

- [ ] A Sonnet subagent fixes the patterns of §3.4 and the broken links, one
      commit for each group of documents.
- [ ] Remove the history sentences that the survey lists.
- [ ] The guard reports zero broken links and zero dead paths.

### Step 4: the front door

- [ ] `README.md`, at most about 250 lines, in this order:
  1. What ProjecturEd is: the statement of §2.1, short.
  2. A video or an animated image, and three screenshots.
  3. What you can do with it: the list of §2.3, each item with a link.
  4. Quick start: clone, the environment, the first example, the assistant
     with a key or with Ollama, a window on your own value.
  5. How it works: data, views, edits, cells, the tool set. One diagram. A link
     to `design/concepts.md`.
  6. Status and limits: the list of §2.5.
  7. Where to read next: one path for a user, one for a Julia developer, one for
     a contributor.
  8. The repository layout, short.
  9. Licence and contact (D1, D8).
- [ ] `design/concepts.md` (D11): the one "start here" document. No code. The
      statement, the words of §2.2, the five ideas, the assistant, one walk from
      a key press to the screen, what works and what does not.
- [ ] `requirement/product-vision.md`: why a user interface on demand, why the AI
      is in the core, and a comparison with tools that the audience knows:
      Pluto, Jupyter, VS Code with an AI extension, Makie with Observables, the
      Julia GUI and web packages. MPS, Lamdu and Hazel move to a short
      "prior work" section.
- [ ] `requirement/delivery-roadmap.md`: delivered, in progress and next, from
      `plan/done/` and `plan/pending/`. Undo, redo and uniform type-in stay in
      "next".
- [ ] `requirement/accepted-requirements.md`: a requirement for a view of any
      value, and one for the tool set that the assistant and an MCP client
      share. The owner reviews them.
- [ ] `design/architecture-decisions.md`: why the tool set is a kernel layer,
      why one tool set for the assistant and MCP, why the core tool runs Julia
      instead of a fixed list of commands.
- [ ] `guide/setup-guide.md`: install, the first window, the SDL libraries, the
      first-start time, what to do when a load fails.
- [ ] `guide/examples-tour.md`: the examples in groups (data files, widgets and
      layout, charts, models, the assistant, the workbench), and the REPL call
      that lists every name.
- [ ] `documentation/README.md`: the new documents and the reading paths.

### Step 5: the new user guides

Each guide has runnable code. Run each snippet once, in one warm session.

- [ ] `guide/assistant-guide.md`: open the assistant, choose a backend, the key,
      the model, a local model with Ollama, the meaning search, what to ask,
      what the assistant can change, the limits.
- [ ] `guide/mcp-guide.md`: start the server (`mcp = true`), the address, a
      client configuration for Claude Code and for a generic MCP client, the
      tools and resources that the client gets, one client for each editor.
- [ ] `guide/view-your-data-guide.md`: a window on your own value (D4), the
      reflection view of a running object, a form from a `@document` struct, a
      small tool window from widgets, a chart of your numbers.
- [ ] `guide/keyboard-and-mouse-guide.md`: the common keys (arrows, `Alt` +
      arrows, clipboard, tabs, zoom, collapse), and F1 and Ctrl+Shift+P for the
      full live list.
- [ ] `guide/own-project-guide.md`: use the packages from your own project,
      which package to load, `run_editor!`, a backend.

### Step 6: the reference documents

- [ ] Kernel guides: REWRITE `macros.md`, `selection.md` and `editor.md`. UPDATE
      the others by the findings.
- [ ] Procedure guides: REWRITE `new-domain-guide.md` around `@domain` and
      `@projection_template`, with the package root that loads. UPDATE the
      others.
- [ ] Package guides: REWRITE `workbench.md` and `syntax.md`. UPDATE the others.
- [ ] Design documents: UPDATE `system-anatomy.md`, `domain-inventory.md`,
      `editor-derivation.md`.
- [ ] Make one table of the 17 layers, in `system-anatomy.md`, and link to it
      from `architecture.md`.

### Step 7: the missing package guides

- [ ] Tier 1: `package/assistant/assistant.md`, `package/natural/natural.md`,
      `package/reflection/reflection.md` (the value reflection, and how it
      relates to `NaturalToGraphics` and `ObjectToWidget`),
      `package/gesturehelp/gesturehelp.md`, `package/mcp/mcp.md`.
- [ ] Tier 2: one guide for each slice of §3.6, tier 2. `database`, `dbcatalog`
      and `odbc` share one guide.
- [ ] Tier 3: one paragraph for each slice in `system-anatomy.md`.
- [ ] The guard's list of slices with no guide is empty, or each remaining slice
      has its paragraph.

### Step 8: rules, contributor documents, seal list, plans

- [ ] Rule documents: the fixes of §3.5. Wording only in
      `architecture-invariants.md`.
- [ ] `CONTRIBUTING.md` and `CLAUDE.md`: links instead of copies (§3.7). Keep
      the sealed-file warning in `CLAUDE.md`.
- [ ] `SEALING.md`: the real inventory, after D10.
- [ ] Plans: move the five superseded plans and `plan/tentative/gesture-help.md`
      to `plan/obsolete/`. Fix the two links in `plan/tentative/`. Fix the facts
      of `nlnet-application.md`.

### Step 9: pictures, videos, slides, web site

- [ ] Make new screenshots with `generate_example_screenshots`: the assistant,
      the workbench, a chart, a sequence chart, a state machine, a rendered RST
      page, a reflection view.
- [ ] Record three short videos with `record_example_video`: the assistant
      builds a view from a request; a chart with zoom and selection; a view of a
      running object that opens level by level.
- [ ] Rewrite `presentation/projectured-overview.md` from the new README. No
      emoji, no source-path footers.
- [ ] D13: correct the text of the web site.

### Step 10: the review

- [ ] A fresh-reader test: a subagent with no knowledge of the repository gets
      only the README and the guides that it links. It follows the quick start
      and writes down where it stops or guesses.
- [ ] A language review against `writing-rules.md`, one document group at a
      time.
- [ ] An assistant test: `list_guides()` shows a real summary for each guide,
      and each guide name in the prompts resolves. If the machine has the
      memory free, one real session with Ollama.
- [ ] Check again every claim of §2.3, §2.5 and the roadmap against `main`.
- [ ] `test_documentation()` passes. Record the final counts.

### Step 11: the posts, and close

- [ ] Write the drafts of §9: one for r/Julia, one for Julia Discourse.
- [ ] The owner reads them, makes the repository public (D2) and posts.
- [ ] Move this plan and the survey file to `plan/done/`.

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
- **A rule document gets a new name.** Links in omnet-julia and inet-julia
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

## 9. The post drafts

Step 11 writes the drafts here. Each draft has: what ProjecturEd is, a video, what
it is good for, how to try it in three commands, what does not work yet, the
licence, and the feedback that the owner wants. Each draft is short. It has no
marketing words and no emoji.

## 10. Out of scope

- New features beyond Step 1: undo and redo, duplicate a pane, Alt+click
  selection, uniform type-in.
- The renames of the seven noun-first functions. They belong to
  `naming-rule-violations.md`.
- The content of `plan/done/`.
- The documentation of omnet-julia and inet-julia, except for broken links.
- A registration in the General registry. It depends on D1.
