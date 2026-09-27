Title: ProjecturEd: one structure, many editable views — with an AI assistant

Category: Tooling
Tags: gui, llm, mcp, ai

Paste everything below the line. Each paragraph is one line, because Discourse turns a newline into a line break.

---

I'd like to show you ProjecturEd, the projectional editor I've been working on. It's an application to view and edit structured data, and I made it to be extended: you define your own data structures as documents and their views as projections, and they combine with the twenty or so domains that come with it, from JSON and Markdown to Julia code, math and charts. You and an AI assistant work together on the same data and the same views, with the same typed edits. It's written in Julia, so it's also a generic user interface for your own Julia programs. It isn't finished, but most of it works, and I think it's far enough to show it and to ask for feedback.

I started ProjecturEd in Common Lisp in 2013, and the reason hasn't changed since. Structured data almost always ends up as text. You print it, you edit the characters of a file, or you write a GUI for that one type and then maintain it. An LLM has the same limit: it writes characters, and you find out afterwards whether the result parses. I wanted the data itself to be the thing you look at and change, with the keyboard or through a model, and I wanted a view to be cheap enough that any value can have one. The Julia version is a new implementation of that idea, with a lot more domains, more backends and the assistant.

In this video a local model (qwen3.8:27b through Ollama) builds a study of an M/M/1/K queue from seven requests: it writes the model and the formulas, runs OMNeT++, plots the results and finds the answer. The OMNeT++ tool in the video is something I built on ProjecturEd, and its code isn't in the public repository. https://projectured.org/assets/videos/queue-study.mp4

In ProjecturEd the data is the source, and every view is computed from it. A projection is a pair of functions: the printer makes the view and records which part of it came from which part of the data, and the reader uses that record to turn a key press or a click into a typed operation on the data. Projections chain, so JSON reaches the screen as JSON → syntax → text → graphics, and a key goes back the same way. Every field is a reactive cell: a computed value stays until something it depends on changes, the parts off screen cost nothing, and no view can show a stale value.

The part I care about most is that you can add your own. A domain of your own is a package: its document types, projections, operations and key bindings. Navigation, search, the clipboard, sorted and filtered views, files, every backend and the assistant come with little or no extra code. The JSON domain is about 560 lines; the web page walks through it, and the repository has a guide for a new domain.

The assistant runs Julia in the editor process with `editor` bound, so it calls the same API you would, and there's no fixed list of commands. It finds functions by name, by pattern or by meaning, it can open tabs and arrange the window, and Ctrl+Z takes back its change like one of yours. It runs on a local model through Ollama by default, or on Claude, and an MCP client gets the same tools. It isn't a sandbox, it's a tool for your own machine, and the MCP server has no authentication, so please don't run it on a machine you share.

It's under development, and the README says what doesn't work yet.

* The web page, with more videos: https://projectured.org
* The code and the guides: https://github.com/projectured/projectured-julia
* The Common Lisp original: https://github.com/projectured/projectured-lisp

It's free for noncommercial use, modification included. Commercial use needs a licence from me, so it isn't open source in the OSI sense, and I'd rather say that up front. Forks and pull requests are welcome. I wrote the Julia code, about 125k lines plus 63k lines of tests, with Claude Code, and I haven't typed any of it by hand.

### What I'd like to hear from you

* Would you use it for your own data, and for what kind of data?
* Does the projection model make sense to you, or does it look like too much machinery for what it gives?
* What would you expect from an assistant that edits the data instead of the text?

I'm happy to answer questions about the projections, the reactive cells, or how a domain of your own would fit.
