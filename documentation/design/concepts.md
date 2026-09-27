# Concepts

> **Kind:** design · **Status:** current · **Stands on:** [product-vision.md](../requirement/product-vision.md)

What ProjecturEd is, and the five ideas that carry it: data, views, edits, selection and the tool set. Read this first. It uses no code; [engineer-tour.md](engineer-tour.md) derives the same system in code.

## What ProjecturEd is

ProjecturEd is three things at once, on one set of data:

- a **viewer**: it shows structured data as a tree, a statement with syntax colours, a chart, a diagram, a form or a table;
- an **editor**: most views take your edits, and an edit changes the data itself;
- an **AI assistant**: a language model inside the program, with the same data and the same edits as you.

A view is normally designed: you say how your data looks, in the same way you would design a window of an application. For data that has no designed view, ProjecturEd makes one on demand, from the structure of the value itself. Both kinds of view live in the same window.

## The words of this document

A user of ProjecturEd and a developer of it use different words for the same thing. This document uses the first column, and names the second where it helps.

| Here | In the code | What it is |
| --- | --- | --- |
| data | document | A tree of Julia values. |
| view | projection output | What a view definition makes from the data: widgets, text or graphics. |
| view definition | projection | A pair of functions: one makes the view, one maps an edit back to the data. |
| view on demand | reflection view | A view that nobody designed for this data. |
| edit | operation | A typed change of the data. |
| selection | selection, reference | A path from the root of the data to the part you work on. |
| assistant | `Assistant` | A language model with a set of tools, inside the running program. |
| tool set | `ToolSet` | The functions that the assistant and an external client can call. |

## The five ideas

### 1. Data

The data is a tree of typed Julia values. JSON data is made of an object, an array, a string, a number, a true or false value, and a null. A state machine is made of states and transitions. Each kind of data is a **domain**, and a domain is a package of its own: nothing in the JSON domain refers to the state machine domain, and neither refers to a screen.

Every field of the data is a **reactive cell**. A read of a field records that the reader depends on that field. A write marks every dependent value invalid, so the next read computes it again. This is what keeps a view up to date, and what keeps the cost of a change small.

### 2. View

A **view definition** turns the data into a view. It is a pair of functions:

- the **printer** makes the view from the data, and records which part of the view came from which part of the data;
- the **reader** takes an event in the view — a key press, a click, a paste — and turns it into an edit of the data.

That record of correspondence is what makes the second function possible. Without it, a program can show data but can not map a change in the picture back to the value it came from.

View definitions compose. JSON reaches the screen through four of them: the JSON data becomes a syntax tree, the syntax tree becomes text, the text becomes graphics, and the graphics go to a window. Each step is a small transformation with its own reader, and the chain runs forward to draw and backward to edit.

Because the steps compose, a general step works for every domain. A filter, a sort, a collapsed node, a search result and a copy of a part are steps that go in front of any data, and they need no knowledge of it.

### 3. Edit

An **edit** is a typed change of the data, not a change of a text. "Insert an element at position 3" is an edit; "delete the bracket at line 12, column 7" is not.

Every edit arrives through the reader side of the view definitions. A key press enters the outermost view, and each step translates it until it reaches the domain that owns the data. The same edits are what the assistant makes, so a change by a model and a change by a person are the same kind of thing, and both can be tested.

### 4. Selection

The **selection** says where you are. It is a path from the root of the data to a part of it: the first entry of an object, then its value, then the third character. It is not a position in a text.

Each node of the data holds the rest of the path below itself. A view definition can therefore read the selection of the node it draws, without knowing the whole path, and a change of the selection writes only the nodes along that path.

A path through the data survives what a text position does not: a filtered view, a sorted view, a change in another part of the document, and a move to another kind of view of the same data.

### 5. The tool set

The **tool set** is the set of functions that a language model can call: search the API of the loaded packages, read a guide, run Julia code in the running program, read the data, and change the data through edits.

The tool set is a layer of the kernel, not an add-on beside it. The assistant in the window uses it, and an external client uses the same tool set through MCP, at `http://127.0.0.1:9876/mcp`. The conversation with the assistant is data like any other, with its own view, so you can read it, edit it, save it, and run Julia code in it yourself.

## A designed view and a view on demand

**A designed view** is one you write. You say that a state has a name and a shape, that a transition is an arrow, and that a click on the arrow opens its condition. ProjecturEd gives you the parts: text, widgets, tables, forms, cards, tabs, split panes, charts and diagrams.

**A view on demand** is one that nobody wrote for this data. ProjecturEd makes it from the structure of the value: a struct becomes a form of its fields, a vector becomes a list, and a large or running object becomes a tree that opens one level at a time. So a value of your program can be on the screen before any view definition for it exists.

The two kinds meet in one window: a designed view of your model in one tab, a view on demand of a running object in the next, and the assistant beside them.

## What happens when you press a key

You press the right arrow key in a JSON document.

1. The window hands the key press to the outermost view definition.
2. The graphics step finds the widget under the selection and passes the key press inward.
3. The text step turns the key press into an edit: move the selection one position to the right.
4. The syntax step maps that position to the syntax tree, and the JSON step maps it to the JSON data: the third character of the value of the first entry.
5. The editor applies the edit. The write marks the cells that depend on the selection invalid.
6. The next frame reads the view again. Only the parts that depend on what changed, and that are on the screen, are computed again. The rest is the same as before.

A change by the assistant takes the same path from step 5 on, because it makes the same kind of edit.

## What works and what does not

ProjecturEd is under development. Today:

- About twenty domains open, show, edit and save their data.
- Views work in a native window, in a browser, in a terminal, and without a screen for tests. A view also goes to a PDF file, an image or a video.
- The assistant works with a local model through Ollama, or with Claude.
- Undo and redo work where a program installs a history. The application does, one around each file and one around the window.
- A failure in a view, an edit or a tool does not stop the editor: it takes the broken change back and shows what went wrong.
- Type-in of single characters does not work the same way in every domain.
- A click selects only where a view wires it, and a drag inside a table cell does not select text.

The [roadmap](../requirement/delivery-roadmap.md) says what comes next.

## What to read next

- [engineer-tour.md](engineer-tour.md) — the same system in code, derived step by step.
- [system-anatomy.md](system-anatomy.md) — the packages, the layers of the kernel, and what depends on what.
- [domain-inventory.md](domain-inventory.md) — the twenty domains, and how to add one.
- [../guide/view-your-data-guide.md](../guide/view-your-data-guide.md) — a view of your own data, designed and on demand.
