# Examples Tour

This guide walks through six ProjecturEd examples in order of complexity.
For each one: what it demonstrates, how to run it, what to try, and which
concepts it illustrates. Screenshots are in [image/](../image/).

## Running examples

```julia
using Projectured, ProjecturedExample
run_example()               # opens the default (JSON) example
run_example("widget")       # opens a specific example by name
print_example("syntax")     # dump the projection output to stdout (no window)
write_image_example("json", "/tmp/snapshot.bmp")   # save a screenshot
```

Available names (see `examples` vector in `ProjecturedExample`):
`json`, `json_sorted`, `json_null`, `json_string`, `xml`, `mixed`,
`syntax`, `text`, `object`, `line_numbering`, `word_wrapping`,
`widget`, `widget_tabbed_pane`, `book`, `filesystem`,
`collection`, `reversing`, `filtering`, `sorting`, `focusing`,
`table`, `math_table`, `workbench`, `math`, `julia`, `graphics_image`.

---

## 1. JSON (`run_example("json")`)

**What it demonstrates:** The foundational pipeline — the one every other
domain is modelled after.

```
JsonObject ──JsonToSyntax──▶ SyntaxNode ──SyntaxToText──▶ TextText ──TextToGraphics──▶ GraphicsCanvas
```

The example opens a small JSON object loaded from
`example/workspace/contact-list.json`. You can navigate with the arrow keys;
the cursor moves through the JSON value characters and the structural
delimiters (`{`, `}`, `"`, `,`).

**What to try:**
- Press `←` / `→` to move the cursor.
- Run `print_example("json")` to see the full projection output as text.
- Run `write_image_example("json", "/tmp/j.bmp")` to capture a screenshot.

**Concepts illustrated:**
- Domain-to-domain projection (`JsonToSyntax`)
- Bidirectional pipeline: printer forward, reader backward
- `ProjectionReference` — cursor positions on the `"` delimiters have no
  JSON counterpart; they are represented as `ProjectionReference(proj, .open + {k})`
- The IO map: each projection step records enough to invert itself

---

## 2. Syntax (`run_example("syntax")`)

**What it demonstrates:** The *syntax* domain is the generic intermediate
between semantic domains (JSON, XML, Math, Julia, …) and text. Using it
directly shows how a `SyntaxNode` tree looks before and after the text
rendering step.

```
SyntaxNode ──SyntaxToText──▶ TextText ──TextToGraphics──▶ GraphicsCanvas
```

The example builds a hand-crafted `SyntaxNode` tree — a parenthesised
expression — and renders it as indented text.

**What to try:**
- Run `print_example("syntax")` to see the flat text output.
- Compare with `print_example("json")` — both flow through `SyntaxToText`, so
  the character-level output format is the same.

**Concepts illustrated:**
- The syntax domain as a domain-independent intermediate representation
- `SyntaxLeaf` (atomic token) vs `SyntaxNode` (bracketed subtree with children)
- How indentation and word-wrapping live in `SyntaxToText`, not in the
  domain-specific projection

---

## 3. Widget (`run_example("widget")`)

**What it demonstrates:** A higher-level domain — widgets — sits *above* the
text domain and has its own projection to graphics. The `WidgetToGraphics`
projection handles layout, focus, and event routing.

```
WidgetShell ──WidgetToGraphics──▶ GraphicsCanvas
```

The example opens a widget shell containing a scroll pane with several labelled
controls: a text box, a checkbox, and a button.

**What to try:**
- Press `Tab` to move focus between controls.
- Press `Space` on the checkbox to toggle it.
- Resize the window; the scroll pane adjusts.
- Try `run_example("widget_tabbed_pane")` for a multi-tab variant.

**Concepts illustrated:**
- Domain independence: `WidgetToGraphics` knows nothing about JSON
- `GraphicsViewport` — how scroll panes clip content to a bounding box
- Event routing through composite projections
- The workbench (`run_example("workbench")`) extends this further to a full
  IDE shell

---

## 4. Table (`run_example("table")`)

**What it demonstrates:** `TableToGraphics` is a *direct* projection — it skips
the text intermediate and renders a 2-D grid directly to graphics primitives,
using rectangle fills and positioned text.

```
TableTable ──TableToGraphics──▶ GraphicsCanvas
```

The example shows a small data table with headers and typed cells.

**What to try:**
- Use `←` / `→` / `↑` / `↓` to move between cells.
- Run `run_example("math_table")` for a table whose cells contain math
  expressions — a compound domain example.

**Concepts illustrated:**
- A projection that bypasses intermediate domains entirely
- `GraphicsRect` fills for cell borders and selection highlight
- Mixed-domain documents: `math_table` combines `TableTable` with
  `MathVariable` / `MathBinaryOperation` cells

---

## 5. Julia AST (`run_example("julia")`)

**What it demonstrates:** Editing source code as an AST, not as text. The
Julia domain provides types for identifiers, integers, binary operators,
function calls, if expressions, functions, and blocks.

```
JuliaBlock ──JuliaToSyntax──▶ SyntaxNode ──SyntaxToText──▶ TextText ──TextToGraphics──▶ GraphicsCanvas
```

The example opens a small Julia program fragment. Navigate through the AST
nodes; the cursor understands the structure of the code.

**What to try:**
- Navigate into nested function calls and if bodies.
- Run `print_example("julia")` to see the syntax-tree representation.
- Compare with `print_example("math")` — the math domain uses the same
  pipeline shape.

**Concepts illustrated:**
- Source code as a first-class domain (not just text)
- `RecursiveProjection` — `JuliaToSyntax` recurses into child expressions
  using the same projection for each node type
- How `TypeDispatchingProjection` dispatches on `typeof(input)` to pick the
  right sub-projection for each AST node kind

---

## 6. Workbench (`run_example("workbench")`)

**What it demonstrates:** The full IDE shell. The workbench is a compound
document that wraps any other document in a structured editor environment with
a navigator, console, operator, searcher, evaluator, and assistant pane.

```
WorkbenchWorkbench ──WorkbenchToWidget──▶ WidgetShell ──WidgetToGraphics──▶ GraphicsCanvas
```

The example opens a workbench containing a JSON document in the editor pane.
The navigator pane on the left shows the document tree.

**What to try:**
- Tab through the panes (navigator, editor, console, …).
- Use the evaluator pane to run Julia expressions against the document.
- Run `run_example("workbench")` with `workbench=true` on any other example:
  `run_example("json"; workbench=true)`.

**Concepts illustrated:**
- Multi-level projection pipeline (three full domain hops)
- `NestingProjection` — the workbench editor pane wraps an arbitrary inner
  projection; the nested projection's events and selections are scoped
  correctly
- `AlternativeProjection` — the workbench pane switcher routes events to the
  currently focused pane

---

## Going deeper

Once you have a feel for these examples, the natural next steps are:

- [concepts.md](concepts.md) — if you want the conceptual model before the code
- [architecture.md](architecture.md) — module inventory and layer diagram
- [projection-system.md](projection-system.md) — the four interface functions
- [tutorial-new-domain.md](tutorial-new-domain.md) — add your own domain
