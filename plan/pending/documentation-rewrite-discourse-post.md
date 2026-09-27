Title: ProjecturEd: one structure, many editable views — with an AI assistant

Category: Tooling
Tags: gui, llm, mcp, ai

Paste everything below the line. Each paragraph is one line, because Discourse turns a newline into a line break.

---

I'd like to show you ProjecturEd, a projectional editor I've been working on.

It's an application to view and edit structured data. You can define your own data structures and your own views for them. They work together with the domains that come with it, like JSON, Markdown, Julia code, math and charts. An AI assistant works with you on the same data and the same views. It's written in Julia, so you can also use it as a user interface for your own Julia programs.

It's not finished, but most of it works. I think it's ready to show, and I'd like to get some feedback.

Some history. I started ProjecturEd in Common Lisp in 2013. Structured data almost always ends up as text. You print it, you edit a file, or you write a GUI just for that one type. An LLM has the same problem, it writes text and you only find out later if it parses. I wanted to look at and change the data itself, with the keyboard or through a model. And I wanted any value to have a view.

I created the Julia version for a new port of a well known and widely used discrete event simulator. It's a complete rewrite, with many more domains, more backends and the AI assistant.

In this video a local model builds a study of an M/M/1/K queue from seven requests. It writes the model and the formulas, runs OMNeT++, plots the results and finds the answer. The model is qwen3.8:27b in Ollama, on my machine. The OMNeT++ tool in the video is built on ProjecturEd, but its code is not public.
https://projectured.org/assets/videos/queue-study.mp4

How it works, in short. The data is the source, and every view is computed from it. A projection turns the data into a view. It also turns your edits in the view back into typed operations on the data. Projections can be chained, for example JSON goes to syntax, then to text, then to graphics. Every field is a reactive cell. A computed value stays until something it depends on changes. What's not on the screen is not computed, and a view never shows stale data.

The most important part for me is that you can add your own domain. A domain is a package with its document types, projections, operations and key bindings. Navigation, search, copy and paste, sorting, filtering, files, all the backends and the assistant work with it, with little or no extra code. The whole JSON domain is a few hundred lines. The web page shows how it's built.

The assistant runs Julia code inside the editor, so it uses the same API as you do. It can search the API by name, by pattern or by meaning. It can also open tabs and arrange the window. You can undo its changes with Ctrl+Z, like your own. By default it uses a local model through Ollama, but it also works with Claude. Other AI tools can use the same tools through MCP. Note that it's not a sandbox, and the MCP server has no authentication. Please don't run it on a shared machine.

It's under development, the README lists what doesn't work yet.

* Web page with more videos: https://projectured.org
* Code and guides: https://github.com/projectured/projectured-julia
* The original Common Lisp version: https://github.com/projectured/projectured-lisp

It's free for noncommercial use, including modifications. For commercial use you need a licence from me, so it's not open source in the OSI sense. Forks and pull requests are welcome. The Julia code is about 125k lines plus 63k lines of tests. I wrote it with Claude Code, I didn't type any of it by hand.

What I'd like to hear from you:

* Would you use it for your own data? What kind of data?
* Does the projection model make sense to you, or is it too much machinery?
* What would you expect from an assistant that edits data instead of text?

I'm happy to answer any questions.
