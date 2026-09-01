---
marp: true
title: ProjecturEd — Feature Overview
description: The most important features of the ProjecturEd projectional editor
author: ProjecturEd
paginate: true
theme: uncover
class: lead
backgroundColor: "#0e1116"
color: "#e6edf3"
style: |
  :root {
    --accent: #58a6ff;
    --accent2: #7ee787;
    --muted: #8b949e;
    --card: #161b22;
  }
  section {
    font-family: -apple-system, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    font-size: 28px;
    line-height: 1.4;
    padding: 52px 84px;
    text-align: left;
    justify-content: flex-start;
  }
  section.lead {
    text-align: center;
    justify-content: center;
  }
  h1 {
    color: var(--accent);
    font-size: 1.7em;
    line-height: 1.1;
  }
  h2 {
    color: var(--accent);
    font-size: 1.15em;
    border-bottom: 2px solid #21262d;
    padding-bottom: 0.2em;
    margin-bottom: 0.5em;
  }
  h3 { color: var(--accent2); font-size: 0.85em; margin: 0.2em 0; }
  strong { color: var(--accent2); }
  a { color: var(--accent); }
  code {
    background: #1f2630;
    color: #e6edf3;
    border-radius: 6px;
    padding: 0.08em 0.35em;
    font-size: 0.85em;
  }
  pre {
    background: var(--card);
    border: 1px solid #21262d;
    border-radius: 10px;
    font-size: 0.7em;
  }
  ul { margin-top: 0.2em; }
  li { margin: 0.25em 0; }
  .muted { color: var(--muted); font-size: 0.8em; }
  .tag {
    display: inline-block;
    background: #1f6feb33;
    color: var(--accent);
    border: 1px solid #1f6feb55;
    border-radius: 999px;
    padding: 0.1em 0.7em;
    font-size: 0.6em;
    margin-bottom: 0.6em;
  }
  .cols {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 0 1.6em;
    align-items: start;
  }
  .cols ul { margin: 0; padding-left: 1.1em; }
  .cols li { font-size: 0.92em; }
  footer { color: var(--muted); font-size: 0.5em; }
  section::after {
    color: var(--muted);
    font-size: 0.6em;
  }
---

<!-- _class: lead -->

# ProjecturEd

### A generic-purpose **projectional editor**

<br>

Documents are structured data — trees, ASTs, graphs — presented
through **bidirectional, composable projections**.
You edit the projection; the editor maps it back to the model.

<br>

<span class="muted">A Julia reimplementation of ProjecturEd · Feature overview</span>

---

<!-- _class: lead -->

## Not a text editor

In a text editor, the **string is the truth** and structure is guessed.

In ProjecturEd, the **structured model is the truth** —
every view is *derived* from it, and every edit is *structural*.

<br>

> One model. Many views. No parsing, no re-serialization, no drift.

---

## The features at a glance

<div class="cols">
<div>

- 🤖 **AI assistant** built in
- 🔍 **Introspection** of objects
- 🪞 **Self-reflection**
- 🪟 **On-demand UI** for huge data
- 🖥️ **Multiple backends**
- ⚡ **Lazy & incremental** engine

</div>
<div>

- 🧩 **Composition** of docs & projections
- 📚 **Many domains** built in
- ⌨️ **Standard editor functions**
- ⏱️ **Undo, redo & versioning**
- 🤝 **Built to collaborate on**

</div>
</div>

<span class="muted">One slide each — and the deck is built to grow.</span>

---

<!-- _class: lead -->

# 🤖 AI assistant built in

The assistant isn't bolted on — it's part of the architecture.

---

## 🤖 AI assistant built in

<span class="tag">first-class, not a plugin</span>

- An **in-editor assistant panel** (`WorkbenchAssistant`) backed by Claude,
  with a deterministic **offline fallback** when no API key is set.
- The AI edits the document **structurally** — it runs Julia against a live
  `editor` (`execute_julia_code`), it does not fake keystrokes.
- An **MCP server** (JSON-RPC over HTTP) exposes the same tool surface to
  external AI clients — in-editor and external AI share one interface.
- The **chat itself is a document** (`Conversation` domain): messages and
  executed code blocks are structured, selectable, editable data.

<span class="muted">package/kernel/main/agent/AgentServer.jl · tool/ToolSet.jl · document/Conversation.jl</span>

---

<!-- _class: lead -->

# 🔍 Introspection

See — and edit — the structure of any object, live.

---

## 🔍 Introspection

<span class="tag">reflection-driven, zero UI code</span>

- **`ObjectToWidget`** turns *any* Julia object into an editable widget form
  by reflecting over its fields — no templates, no per-type UI code.
- Field types pick the control: bool → checkbox, string/number → text input.
- The form is **bidirectional**: edit a field, the backing cell invalidates,
  the projection re-runs, and the change appears everywhere.
- The **Descriptor panel** shows docs + an auto-generated form for whatever
  node the selection is on.

<span class="muted">projection/generic/ObjectToWidget.jl · document/Workbench.jl</span>

---

<!-- _class: lead -->

# 🪞 Self-reflection

An editor general enough to edit itself.

---

## 🪞 Self-reflection

<span class="tag">the ultimate generality test</span>

- A **Julia domain** models Julia code as structured data —
  identifiers, calls, `if`, functions, blocks — with a bidirectional
  **`JuliaToSyntax`** projection.
- Because domains nest, you can edit **code as data**: a Julia expression
  living inside a JSON field, a book, or a table.
- **Self-hosting** — editing ProjecturEd's own source inside ProjecturEd —
  is the stated long-term goal: if the system can edit itself, every design
  assumption is validated.

<span class="muted">document/Julia.jl · projection/primitive/JuliaToSyntax.jl · guide/roadmap.md</span>

---

<!-- _class: lead -->

# 🪟 On-demand UI

Project a window onto data that never fully materializes.

---

## 🪟 On-demand UI

<span class="tag">finite views over infinite data</span>

- **`ListNode`** is a doubly-linked list whose `prev`/`next` can be lazy
  thunks — an *infinite* list is built in O(1) and walked on demand.
- **`FocusingProjection`** projects only the focused window; everything
  outside it is never computed.
- Pull-based cells mean **off-screen subtrees cost nothing** until seen —
  the same pipeline serves a tiny doc and an unbounded one.

```julia
# infinite integers, projected to just the visible slice
node = ListNode(value = 0, next = ComputedCell(() -> succ(node)))
```

<span class="muted">document/Collection.jl · projection/generic/Focusing.jl</span>

---

<!-- _class: lead -->

# 🖥️ Multiple backends

One document. One projection. Three rendering paths.

---

## 🖥️ Multiple backends

<span class="tag">display & input fully decoupled</span>

- **SDL2** — native windows and fonts.
- **Console** — renders styled text directly with ANSI colors,
  *skipping graphics entirely* (proof the pipeline is backend-agnostic).
- **Web** — HTTP + WebSocket server rendering to a browser `<canvas>`/SVG.
- **PDF** export — vector output with self-contained TrueType embedding,
  headless, no SDL required.

Swapping is one argument: `run_editor!(WebBackend(), proj, doc)`.
The projection only ever sees neutral events like `KeyDown(:left)`.

<span class="muted">backend/{Sdl,Console,Web,Pdf}.jl · api/{Backend,Device}.jl</span>

---

<!-- _class: lead -->

# ⚡ Lazy & incremental engine

Deep pipelines that stay fast.

---

## ⚡ Lazy & incremental engine

<span class="tag">pull-based reactive cells</span>

- One primitive — a **`Cell`** that holds either a value or a thunk —
  with **automatic dependency tracking** (just reading a cell records an edge).
- **Eager invalidation, lazy recompute**: an edit marks dependents invalid
  in O(depth); only what's actually *read* recomputes, in O(affected).
- Editing one character in a huge document reruns a *handful* of cells —
  text, layout, and most graphics are served from cache.
- `get_performance_counters()` exposes read/compute/write counts per frame.

<span class="muted">cell/CellModule.jl · every @document field is a Cell</span>

---

<!-- _class: lead -->

# 🧩 Composition

Documents and projections compose on two axes.

---

## 🧩 Document & projection composition

<span class="tag">mix domains freely</span>

- **Documents nest**: any field can hold any other domain — JSON inside XML
  inside styled prose — and selections round-trip across the boundaries
  (`NestingProjection`).
- **Projections combine**: chain them (`Sequential`), make them recursive,
  dispatch by type or location, or **transform structure non-destructively**
  with `Sorting`, `Filtering`, `Focusing`.
- A sort or filter is *a projection you add* — undo removes the view,
  never your data.

> Same data, many views; same projection, many domains.

<span class="muted">projection/higherorder/* · projection/generic/*</span>

---

<!-- _class: lead -->

# 📚 Many domains

Batteries included.

---

## 📚 Many domains, out of the box

<span class="tag">30+ structured domains</span>

<div class="cols">
<div>

- **Data** — JSON, XML, INI, SQL, Database
- **Text & prose** — Text, Book, Syntax
- **Code** — Julia, Math, Evaluator
- **UI** — Widget, Graphics, Layout, Color, Font

</div>
<div>

- **IDE** — Workbench, Conversation, FileSystem
- **Tables** — Table, Collection (vector/matrix/list)
- **Editing** — Clipboard, Dragging, Reference
- **…and more** — Image, Tooltip, Geometry, Style

</div>
</div>

Each is a real domain with structured types and operations — and any one
can be **embedded inside any other**.

<span class="muted">package/*/main/document/*.jl</span>

---

<!-- _class: lead -->

# ⌨️ Standard editor functions

The operations you expect — in every domain.

---

## ⌨️ Standard editor functions

<span class="tag">structural operations, not string edits</span>

- **Navigation & selection** — arrows, Home/End, Page Up/Down; the selection
  threads through *every* projection layer.
- **Cut / copy / paste** — a real `Clipboard` domain; you paste structured
  *meaning*, not text.
- **Mouse** — click-to-select maps pixels back to a position.
- **Search** — `search_references` / `search_documents` walk the whole tree
  (string, regex, or predicate; depth-bounded for infinite data).
- **Scroll, tabs, panels, drag-to-reorder** in the workbench.

The same `Operation` interpreted locally per domain — one mechanism, every view.

---

<!-- _class: lead -->

# ⏱️ Undo, redo & versioning

Edits as a history you can travel through.

---

## ⏱️ Undo, redo & versioning

<span class="tag">the operation model is the timeline</span>

- Every change is a **typed, invertible `Operation`** — so undo is just
  applying its inverse, and redo is replaying it forward.
- A stream of operations *is* a history: branchable, replayable,
  and inspectable — the natural substrate for full **document versioning**.
- Because operations carry **meaning** (*“insert at index 3”*), a version
  diff reads as structural intent, not a noisy line-by-line text diff.

<span class="muted">Forthcoming — built directly on the existing operation infrastructure.</span>

---

<!-- _class: lead -->

# 🤝 Built to collaborate on

Real-time multi-user editing, by construction.

---

## 🤝 Built to collaborate on

<span class="tag">the architecture does the heavy lifting</span>

- Every change is a **first-class, typed, invertible `Operation`** —
  *“insert element at index 3”*, not *“characters 41–58 changed.”*
- Because edits carry **meaning, not character offsets**, merge and conflict
  resolution can reason structurally — the natural substrate for **OT / CRDT**.
- The model already separates **operation → transport → apply**, so live
  collaboration becomes a transport-and-merge layer on top, not a rewrite.

<span class="muted">Shares the same operation foundation as undo/redo and versioning.</span>

---

<!-- _class: lead -->

## The throughline

**Structured model + bidirectional, composable projections.**

Everything else — AI, introspection, many backends, incrementality,
collaboration — falls out of that one idea.

<br>

<span class="muted">Read next: guide/concepts.md → architecture.md → reactive-cells.md</span>

---

<!-- _class: lead -->

# Thank you

### Questions?

<span class="muted">github.com/projectured/projectured-julia</span>
