# Vision

> **Kind:** requirement · **Status:** current · **Stands on:** [concepts.md](../design/concepts.md)

Why ProjecturEd exists: data that is shown and edited as a structure, a user interface you design or get on demand, and a language model that works on the same data as you. It also says where ProjecturEd stands beside the tools a Julia developer already uses.

## The problem

A program holds structured data: a configuration, a model, a measurement, an abstract syntax tree, a network of objects. To look at that data, a developer has three usual ways, and each one loses something.

1. **Print it as text.** A text of a large value is long, flat and read-only. A change means a new line of code and another print.
2. **Write a user interface for it.** A toolkit asks for widgets, layout, event handlers and a way back from the widget to the value. The work is large, and it holds for one data type only.
3. **Serialise it to a file and open the file in an editor.** The editor sees characters. It can not check the structure, and a change of the notation breaks every tool around it.

The same three ways limit an AI assistant. A model that can only print, or only patch text, can not make a structured change and can not show a result.

## What ProjecturEd does instead

The data is the source. A view is computed from it, and an edit in the view is mapped back to the data. That single mechanism gives the three roles of ProjecturEd:

- **A viewer.** Any value can be on the screen, as a tree, a table, a form, a chart or a diagram.
- **An editor.** The view takes your edits, and each edit changes the data itself. There is no text copy to keep in step.
- **An assistant.** A language model calls the same functions and makes the same edits as your key presses.

Two things follow that a toolkit does not give.

**A view on demand.** A value whose view nobody wrote still appears: ProjecturEd builds a view from the structure of the value, one level at a time. So a developer is never blocked by a missing user interface, and a designed view can replace it later, part by part.

**Composition.** A view definition is a pair of functions between two kinds of data, so view definitions chain. A filter, a sort, a search, a collapsed node, a copy of a part, a notation and a file format are steps in that chain, and each of them works for every domain. A new domain gets those features with no extra code.

## Why the assistant is in the core

The tool set is a layer of the kernel, beside the data and the views. It is not a plug-in beside the program, for three reasons.

1. **The same edits.** The assistant changes the data with the operations that your keys make, so a change by a model is as safe and as testable as a change by a person.
2. **The same views.** The assistant can open a view of a value it made, in the window you are looking at.
3. **One tool set, two clients.** The assistant in the window and an external client over MCP call the same functions. A tool that a developer adds is there for both.

The conversation is data too, with its own view, so it is saved, edited and searched like every other document.

## Where ProjecturEd stands beside the tools you know

**Pluto and Jupyter.** A notebook runs code and shows the result of each cell, and Pluto also re-runs the cells that depend on a change. ProjecturEd starts from the data rather than from the cell: a value is on the screen with a view of its own, the view is editable, and the incremental step is per field of the data and per part of the screen. A notebook is the better place for a narrative of code and prose; ProjecturEd is the better place for a structure you look at and change.

**VS Code with an AI extension.** The editor sees files of characters, and the model writes patches of characters. ProjecturEd sees the structure, and the model makes the same typed edits as the user. The cost is that ProjecturEd is not a general code editor: it edits the domains it has.

**Makie with Observables.** An `Observable` gives a plot that follows a value, which is the same idea in one direction. ProjecturEd adds the way back — a click or a key press in the picture becomes a change of the data — and applies it to trees, text, forms and tables, not to plots alone.

**The Julia GUI and web packages** (Gtk4, QML, Genie, Dash, Stipple). They give widgets and a browser page, and you write the mapping from your data to those widgets and back. ProjecturEd gives that mapping as its subject: you write a view definition, and the general features come with it. ProjecturEd also draws its own widgets, text and layout in Julia, so a view runs in a window, in a browser, in a terminal and in a file with no change.

**Term and REPL display.** `show` prints a value, and ProjecturEd is not a replacement for it. It is what you reach for when the value is too large, too deep or too alive for a printed line.

## Prior work

**JetBrains MPS** is the large projectional editor: a language workbench with generators and an editor per language concept. ProjecturEd shares the idea that the data is the source and the view is computed. It differs in scale and host: MPS is a Java platform for language design; ProjecturEd is a Julia library for any structured data, with the composition of view definitions as its centre.

**Lamdu** is a projectional editor for a functional language, with type-driven editing. It shows what a structure editor can do for code. ProjecturEd is not tied to one language.

**Hazel** is a structure editor with holes: an incomplete program still has a meaning. ProjecturEd has a placeholder for a missing part, but it does not evaluate an incomplete program.

**Tree-sitter** parses text into a tree for tools that still edit text. ProjecturEd keeps the tree and computes the text from it, which is the other direction.

## The limits this vision accepts

- ProjecturEd is under development. The [roadmap](delivery-roadmap.md) says what works and what is next.
- Undo and redo are opt-in: the application keeps a history, and a program that installs none has none.
- It is not a general text editor, and not a replacement for a notebook.
- The packages are not in the General registry.
