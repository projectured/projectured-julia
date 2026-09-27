Title: ProjecturEd: one structure, many editable views — with an AI assistant

Category: Tooling
Tags: gui, llm, mcp, ai

Paste everything below the line. Each paragraph is one line, because Discourse turns a newline into a line break.

---

ProjecturEd is an application to view and edit structured data, and it's made to be extended: you define your own data structures as documents and their views as projections, and they combine with the twenty or so domains that come with it, from JSON and Markdown to Julia code, math and charts. You and an AI assistant work on the same data and the same views, with the same typed edits. It's written in Julia, so it's also a generic user interface for your own Julia programs. It isn't finished, but most of it works, and I think it's far enough along to show and to get some feedback.

Why: structured data almost always ends up as text. You print it, or you edit the characters of a file, or you write a GUI for that one type and then maintain it. An LLM has the same limit: it writes characters, and you find out afterwards whether the result parses. I wanted the data itself to be the thing you look at and change, with the keyboard or through a model, and I wanted a view to be cheap enough that any value can have one.

In this video a local model (qwen3.8:27b through Ollama) builds a study of an M/M/1/K queue from seven requests: it writes the model and the formulas, runs OMNeT++, plots the results and finds the answer. The OMNeT++ tool in the video is built on ProjecturEd, and its code isn't in the public repository. https://projectured.org/assets/videos/queue-study.mp4

The data is the source, and every view is computed from it. A projection is a pair of functions: the printer makes the view and records which part of it came from which part of the data, and the reader uses that record to turn a key press or a click into a typed operation on the data. Projections chain, so JSON reaches the screen as JSON → syntax → text → graphics, and a key goes back the same way. Every field is a reactive cell: a computed value stays until something it depends on changes, the parts off screen cost nothing, and no view can show a stale value.

A domain of your own is a package: its document types, projections, operations and key bindings. Navigation, search, the clipboard, sorted and filtered views, files, every backend and the assistant come with little or no extra code. The JSON domain is about 560 lines; the web page has a walk-through of it, and the repository has a guide for a new domain.

The assistant runs Julia in the editor process with `editor` bound, so it calls the same API you would, and there's no fixed list of commands. It finds functions by name, by pattern or by meaning, it can open tabs and arrange the window, and Ctrl+Z takes back its change like one of yours. It runs on a local model through Ollama by default, or on Claude, and an MCP client gets the same tools with `--mcp`.

### Where it fits

I don't think it replaces anything you already use. Pluto and Jupyter are the better place for a narrative of code and prose. Makie with Observables is the same idea in one direction; ProjecturEd adds the way back, for trees, text, forms and tables too. With Gtk4, QML, Genie or Stipple you write the mapping between your data and the widgets yourself; here that mapping is what you write, and the rest comes with it. JetBrains MPS, Hazel and Lamdu are the projectional and structure editors I know of. If you know a tool that already combines composable projections over your own Julia data, fine grained reactivity and a model that makes the same typed edits as you, I'd like to hear about it.

### Try it

```sh
git clone https://github.com/projectured/projectured-julia
cd projectured-julia
bin/projectured
```

Or from a REPL started with `julia --project=environment/all`, with more than a hundred examples to choose from:

```julia
using Projectured, ProjecturedExample, ProjecturedSdl
run_example("json")
```

It's under development, and the README says what doesn't work yet. One warning up front: the code tool runs anything the process can run, and the MCP server has no authentication (it listens only on the loopback address), so don't start it on a machine you share. I use and test it on Linux.

* The web page, with videos: https://projectured.org
* The code and the guides: https://github.com/projectured/projectured-julia
* The Common Lisp original: https://github.com/projectured/projectured-lisp

It's free for noncommercial use, modification included. Commercial use needs a licence from me, so it isn't open source in the OSI sense, and I'd rather say that up front. Forks and pull requests are welcome. The Julia code, about 125k lines plus 63k lines of tests, was written with Claude Code; none of it was typed by hand.

### What I'd like to hear

* Would you use it for your own data, and for what kind of data?
* Does the projection model make sense to you, or does it look like too much machinery for what it gives?
* What would you expect from an assistant that edits the data instead of the text?

I'm happy to answer questions about the projections, the reactive cells, or how a domain of your own would fit.
