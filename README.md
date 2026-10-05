# ProjecturEd

ProjecturEd: one structure, many editable views — with an AI assistant. It is an application to view and edit structured data, made to be extended with your own data structures and views, and a generic user interface for any Julia program.

> **Status: under development.** Most features work, but ProjecturEd is not a finished product. Some parts are incomplete, and names and interfaces can still change. The [roadmap](documentation/requirement/delivery-roadmap.md) lists what works today and what comes next. Problem reports and questions are welcome as GitHub issues.

ProjecturEd is an application to view and edit structured data, with an AI assistant, and it is made to be extended: you define your own data structures as documents and their views as projections. About twenty domains come with it, among them JSON, YAML, XML, Markdown, SQL, Julia code, math formulas, charts, graphs and state machines. They are examples, not the limit. ProjecturEd shows them in one window, in tabs and split panes, and one document can mix kinds, yours with the others: JSON inside XML inside prose. ProjecturEd is written in Julia. So it is also a generic user interface for your own Julia programs: it shows your documents, and the values of a running program, in the same way.

You can extend ProjecturEd with your own domain: its document types, the projections that make its views, its operations and its key bindings. A domain is a package of its own, and no other domain depends on it. So you can work on your domain without changes to other domains, while other developers work on theirs. Your domain gets the general features with little or no extra code: selection and navigation, search, copy and paste, filtered and sorted views, a text notation and a file format, saving, every backend, and the AI assistant, which can find and call your functions.

A view can be a tree, a statement with syntax colours, a chart, a diagram, a form or a table. When the data changes, every view of it changes with it: each view reads the data through reactive cells, so no view on the screen can show an old value. Most views are also editors: an edit in a view changes the data itself, not a text copy of it. You can design your own user interface from views and widgets. For data that has no view yet, you get one on demand: a generic view that ProjecturEd makes by reflection over the value, or a view that the assistant opens for you.

The same views work in a native window, in a web browser, in a terminal, and without a screen for tests and scripts. A view can also go to a PDF file, an image or a video. The data goes to text files or to binary files. A text file uses the notation of its domain, and several files can refer to each other. So data with shared parts and mutually recursive structures comes back unchanged after a save and a load. Parts of a document that are not on the screen cost nothing, so a view can show a part of a very large document, or of an infinite list.

The AI assistant runs inside the application, with a local model through Ollama or with Claude. It searches the API of the loaded packages, writes Julia code and runs it in the application. It changes the data with the same operations as your key presses. The window is a document too, so the assistant also controls the user interface: it can open a tab, split a pane or scroll a view. The conversation is a document too, with its own view, and you can also run Julia code in it yourself. An external AI client, for example Claude Code, can use the same tools through MCP.


## Screenshots

| JSON editor | Widget forms | Table view |
|---|---|---|
| <img width="396" alt="JSON example" src="asset/image/example/json.png"> | <img width="1024" alt="Widget example" src="asset/image/example/widget.png"> | <img width="397" alt="Table example" src="asset/image/example/table.png"> |

| Syntax tree | Julia AST | Assistant |
|---|---|---|
| <img width="586" alt="Syntax example" src="asset/image/example/syntax.png"> | <img width="336" alt="Julia AST example" src="asset/image/example/julia.png"> | <img width="1285" alt="Assistant example" src="asset/image/example/assistant.png"> |

## What you can do with it

- **Build an application for your own data.** Define the structure of your data as documents and its views as projections, in a package of its own. [new-domain-guide.md](documentation/guide/new-domain-guide.md) walks through a whole domain, and [view-your-data-guide.md](documentation/guide/view-your-data-guide.md) shows your own Julia values with no new domain.
- **Edit files as structures.** The domains that come with ProjecturEd open, change and save their files through their own parsers, among them JSON, YAML, XML, Markdown, reStructuredText, SQL, Julia and a math notation. See [the domain inventory](documentation/design/domain-inventory.md).
- **Design a tool window without a GUI toolkit.** Widgets, tables, cards, tabs, split panes and a pane tree come from the [widget](documentation/package/platform/widget/widget.md) and [pane](documentation/package/platform/pane/pane.md) packages. ProjecturEd's own window is a complete application of this kind.
- **Look into a running Julia program.** A reflection view shows any object as a tree that opens one level at a time.
- **Show results.** Line, bar, histogram, scatter and strip charts, and [sequence charts](documentation/package/domain/sequencechart/sequencechart.md), are documents. A data point can be selected like any other part.
- **Model behaviour and run it.** A [state machine](documentation/package/domain/fsm/fsm.md) produces runnable Julia code. A [process flowchart](documentation/package/domain/process/process.md) runs with breakpoints and a live trace.
- **Ask for a change in plain words.** The assistant searches the API, writes Julia and runs it against the live editor. It works with a local model through Ollama, or with Claude.
- **Drive the editor from outside.** An MCP client connects to `http://127.0.0.1:9876/mcp` and gets the same tools as the assistant in the window.
- **Put a view somewhere else.** The same view goes to a native window, a browser, a terminal, a PDF file, a PNG file or an MP4 video.
- **Take a change back.** `Ctrl+Z` and `Ctrl+Y` work in the application, for your edits and for the assistant's. The [history](documentation/package/platform/undo/undo.md) is a document too, so you can read it.
- **Keep working after a fault.** A failure in a view, in an edit or in a tool [does not stop the editor](documentation/package/platform/fault/fault.md): the editor takes the broken change back, shows what went wrong where the view would be, and goes on.
- **Open a tool by its name.** Type `repl`, `log`, `gestures`, `selection`, `reference`, `explorer` or `assistant` into an empty tab, and the tab becomes that tool.

## Quick start

There are two ways to start: add the packages to a project of your own, or run the application from the source. You need Julia 1.12 or later, and SDL2 with SDL_ttf for a native window. [Which repository is which](#which-repository-is-which) says where each part lives.

### The packages in your own project

The packages are in the registry [`ProjecturedRegistry`](https://github.com/projectured/ProjecturedRegistry), not in the [General](https://github.com/JuliaRegistries/General) registry. Add it once, with General, then add the packages that your program uses by name:

```
pkg> registry add General
pkg> registry add https://github.com/projectured/ProjecturedRegistry
pkg> add Projectured ProjecturedSDL ProjecturedDataFrames DataFrames SimpleDirectMediaLayer

julia> using Projectured, DataFrames, SimpleDirectMediaLayer
julia> display_in_editor(DataFrame(n = 1:1000, square = (1:1000) .^ 2))
```

`using Projectured` loads ProjecturedSDL and ProjecturedDataFrames by itself, because their triggers are loaded. The [front page of Projectured.jl](https://github.com/projectured/Projectured.jl) lists the packages, and says how to load each one by name instead. Update all ProjecturEd packages together, with `pkg> update`: each version of a package is made for the versions of the other packages of the same release.

### The application from the source

Clone the repository, and AutoIntegration beside it: the umbrella names that folder.

```sh
git clone https://github.com/projectured/AutoIntegration.jl auto-integration
git clone https://github.com/projectured/projectured-julia
cd projectured-julia
bin/projectured
```

`bin/projectured` opens a window with a file navigator on the left, the open files in tabs in the middle, and the assistant on the right. The navigator lists the directory you start it in, and a double click opens a file. Name the files on the command line to open them at once: `bin/projectured notes.md data.json`. The first start compiles the code, which takes some minutes; later starts are fast.

The window is drawn in its own chrome: a menu bar, a toolbar and a status line that says which tab has the focus. The toolbar has one picture for each tool of the window: the file explorer, the assistant, the evaluator, the message log, the gesture log, the fault log, the frame statistics and the selection. A press opens the tool in a tab, or gives the focus to the tab that already holds it, and the pointer at rest on a picture names the tool. A right press opens the menu the thing under the pointer offers, **F1** lists the keys that work where you are, and **Ctrl+Shift+P** finds a command by its name. **View → Gesture log** opens a tab that lists every gesture of the session and what each one did, including the gestures made before the tab opened.

```sh
bin/projectured --help                       # every option
bin/projectured --assistant=none notes.txt   # no assistant
bin/projectured --backend=web a.json         # in a browser, at http://127.0.0.1:8080
bin/projectured --mcp a.json                 # with an MCP server for an external client
```

The menu bar has **Open** and **Save As** for a file outside the directory the navigator lists. `save_user_interface(editor, path)` writes the whole window — its panes, its tabs and what each one holds — to one file, and `load_user_interface(path)` brings it back; an open file tab is saved as a reference to its file, not as a copy.

**The assistant.** By default it asks a local model through [Ollama](https://ollama.com): the Ollama server must run on your machine, and the model must be pulled. For Claude, set `ANTHROPIC_API_KEY` in your environment and start with `--assistant=anthropic`. Without a server and without a key, the assistant pane opens and says what it needs.

**A binary.** `bin/build_projectured` compiles the application into `build/projectured/`, which runs without Julia and without this checkout. [build-guide.md](documentation/guide/build-guide.md) says what the build does and what it costs.

**From a session.** Load the packages and open any value or example:

```julia
julia --project=environment/all
using Projectured, ProjecturedExample, ProjecturedSDL
run_example("json")                          # one example in a window
```

[setup-guide.md](documentation/guide/setup-guide.md) says what to do when a load fails, and [examples-tour.md](documentation/guide/examples-tour.md) lists the examples.

## How it works

ProjecturEd is a projectional editor. The data is the source, and every view is computed from it. A projection turns the data into a view, and it turns an edit in the view back into an operation on the data. Projections compose: one view can show several kinds of data, and one piece of data can have many views. Each field of the data is a reactive cell. After a change, ProjecturEd recomputes only the parts of the views that depend on the change and are on the screen.

Five ideas carry the whole system.

| Idea | What it is |
| --- | --- |
| Document | The data: a tree of typed structures, each field a reactive cell. |
| Projection | A pair of functions: a printer that makes the view, and a reader that turns an intent in the view into an operation. |
| Selection | Where you are, as a path into the data, not as a caret in a text. |
| Operation | A change of the data, from a key press or from the assistant. |
| Tool set | What the assistant and an MCP client can call: search the API, read a guide, run Julia, change the data. |

A key press goes through the projections to the data, and the change comes back through the same projections to the screen. [concepts.md](documentation/design/concepts.md) explains the five ideas without code, and [engineer-tour.md](documentation/design/engineer-tour.md) derives the system from them.

## Status and limits

ProjecturEd is under development. These limits are true today:

- Undo and redo work in the application, which puts a history around each file and one around the window. A window of your own has none until you put one there.
- Type-in of single characters does not work the same way in every domain.
- A drag inside a table cell does not select text. A click, the arrows and typing edit the cell.
- A click selects where a projection wires it, and elsewhere it does nothing.
- The assistant needs a local Ollama server with a pulled model, or an Anthropic API key.
- The packages are not in the General registry. You clone the repository and use `environment/all`.
- SDL2 and SDL_ttf must be installed for a native window.

The [roadmap](documentation/requirement/delivery-roadmap.md) says what comes next.

## Where to read next

**To use it**: [setup-guide.md](documentation/guide/setup-guide.md), then [examples-tour.md](documentation/guide/examples-tour.md), [keyboard-and-mouse-guide.md](documentation/guide/keyboard-and-mouse-guide.md) and [the assistant guide](documentation/guide/assistant-guide.md).

**To show your own data**: [concepts.md](documentation/design/concepts.md), then [view-your-data-guide.md](documentation/guide/view-your-data-guide.md) and [own-project-guide.md](documentation/guide/own-project-guide.md).

**To work on ProjecturEd**: [concepts.md](documentation/design/concepts.md), [engineer-tour.md](documentation/design/engineer-tour.md), [system-anatomy.md](documentation/design/system-anatomy.md), then [CONTRIBUTING.md](CONTRIBUTING.md) and the rules in [documentation/rule/](documentation/rule/). [The guide index](documentation/README.md) lists every document.

## Which repository is which

| Repository | What it is | Who uses it |
|---|---|---|
| [projectured-julia](https://github.com/projectured/projectured-julia) | This repository: the source, the application, the examples, the tests and the guides | a person who runs the application from the source, or changes ProjecturEd |
| [Projectured.jl](https://github.com/projectured/Projectured.jl) | The released packages, one folder for each, which the release writes from this repository | Pkg, when you add a package; a change belongs here, not there |
| [ProjecturedRegistry](https://github.com/projectured/ProjecturedRegistry) | The Julia registry that names each version of the released packages | Pkg, after you add the registry once |
| [AutoIntegration.jl](https://github.com/projectured/AutoIntegration.jl) | The package that loads an installed package when its triggers are loaded; `Projectured` depends on it | Pkg installs it; a clone of this repository needs it beside it, in `auto-integration` |
| [AutoPrecompile.jl](https://github.com/projectured/AutoPrecompile.jl) | The package that builds one package image for the packages that a session loads, from recorded precompile statements | a person who wants the next session to show a data frame fast; Pkg installs it when you add it |

## Repository layout

One dimension per level: what a file **is** decides its top folder, the **group** of its slice the folder under that, and the **slice** the folder under the group. The groups are `kernel`, `platform`, `domain`, `backend`, `adapter` and `tool`.

| Path | Contents |
|---|---|
| [source/](source/) | The system — one folder per group, one folder per slice in it, and `kernel/` with its layers |
| [test/](test/) | The suites, in the same groups and slices, plus `suite/` for what belongs to no package |
| [example/](example/) | Documents, galleries and workload bodies, in the same groups and slices |
| [package/](package/) | One directory per package: a `Project.toml` and a `src/<Name>.jl`, and nothing else |
| [environment/](environment/) | `all/` for the whole suite, `build/` for a build. No code |
| [documentation/](documentation/) | The guides — see [the guide index](documentation/README.md) |
| [asset/](asset/) | Fonts, screenshots, the web client, and the precompile recording |
| [bin/](bin/) | The commands: run the application, build the binary |
| [tool/](tool/) | Scripts that are not part of the system |
| [plan/](plan/) | Design notes and plans |

A package and its code do not share a directory. `package/ProjecturedJSON/` is a name and an include list; the code it includes is `source/domain/json/`, its suite is `test/domain/json/` and its documents are `example/domain/json/`.

## Contributing

Forks and pull requests are welcome. [CONTRIBUTING.md](CONTRIBUTING.md) says how the repository is organised, what a change must keep, and how to add a domain of your own. If you are an AI assistant working in this repository, read [CLAUDE.md](CLAUDE.md) and [SEALING.md](SEALING.md) first.

## How the code is made

ProjecturEd began in Common Lisp in 2013. I wrote that version by hand, and it is still available as [projectured-lisp](https://github.com/projectured/projectured-lisp). This Julia version is a port of it, which I started in May 2026. Most of the code is written by Claude Code, an AI coding tool, but the design and the decisions are mine.

I work plan first. Each change starts from a written plan in [plan/](plan/), and I refine the plan with the tool until I agree with each decision in it: the concepts, the alternatives, the risks and the order of the work. There are more than 400 plans so far. A typical plan went through several rounds of refinement, and the larger ones through dozens; about half of the more than 4,000 commits change a plan. The rules that every change must keep are in [documentation/rule/](documentation/rule/). Static guards check the rules that a program can check, the test suites check the behaviour, and [CI](.github/workflows/CI.yml) runs both.

I review the code file by file against its [architecture invariants](documentation/rule/architecture-invariants.md), and I seal each file after the review. [SEALING.md](SEALING.md) lists the sealed files. So far I sealed only files of the kernel; the other packages will follow. When I seal a file, I read all its types and the interface of each public function, but I do not check the implementation of every function. Outside the sealed files, I read the parts that I am interested in.

## Licence, author and contact

ProjecturEd is under the [Mozilla Public License 2.0](LICENSE). You can use it, change it and build products on it, commercial ones included. A change to a file of ProjecturEd stays under the MPL, and its source must be available to the people you give it to; files of your own, such as a package that extends ProjecturEd, can be under any licence.

Author: Levente Mészáros. Contact: projectured@gmail.com.
