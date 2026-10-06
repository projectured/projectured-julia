# Examples Tour

> **Kind:** reference · **Status:** current · **Stands on:** [setup-guide.md](setup-guide.md)

This guide walks through seven ProjecturEd examples in order of complexity.
For each one: what it demonstrates, how to run it, what to try, and which
concepts it illustrates. Screenshots for each example are embedded inline below.

## Run one

```julia
using Projectured, ProjecturedExample, ProjecturedSDL

run_example()                        # the JSON example
run_example("widget")                # one example by name
print_example("syntax")              # the view as text, no window
write_example_image("json", "/tmp/snapshot.png")
write_example_pdf("json", "/tmp/snapshot.pdf")
```

`[example.name for example in ProjecturedExample.examples]` lists every name; there are 105. `catalog()` answers a longer list, one entry for each document of each domain with each projection that draws it, which is what a sweep walks.

## The groups

**Data files.** `json`, `json_sorted`, `json_insertion`, `yaml`, `xml`, `mixed`, `markdown`, `markdown_rendered`, `book`, `sql_syntax`, `sql_insert_syntax`, `sql_update_syntax`, `sql_nested_syntax`, `math`, `julia`, `formula`. Each one opens a file of its notation and edits it as a structure. `mixed` is the one to see first: JSON inside XML inside prose, in one document.

**Text and syntax.** `syntax`, `text`, `plain_text`, `text_with_image`, `line_numbering`, `word_wrapping`, `text_filtering`, `text_highlighting`, `natural`. The layer between a domain and the screen, on its own.

**Values of a program.** `object`, `object_to_widget`, `nested_object_to_widget`. A Julia value with no view of its own. `run_value_viewer(value)` is the same thing in one call.

**Widgets.** `widget` and about forty `widget_*` examples: a label, a button, a checkbox, a switch, a slider, a select, a text area, a table, a tree, a tab strip, a card, an alert, a toolbar, a menu. Each one is one widget, so a reader sees what it takes to place it.

**Layout and panes.** `layout`, `constraint_layout`, `widget_split_pane`, `widget_scroll_pane`, `widget_transform_pane`, `widget_shell`, `widget_tabbed_pane`. How a view is given its space.

**Charts and diagrams.** `chart`, `chart_line`, `chart_bar`, `chart_histogram`, `chart_scatter`, `chart_strip`, `chart_inspector`, `graph`, `sequencechart` and its four variants. A chart is a document, and a data point is selectable.

**Models that run.** `fsm`, `fsm_toggle`, `fsm_diagram` — a state machine that produces Julia code. `rotating_vector` — a document that drives itself.

**The general steps.** `collection`, `reversing`, `filtering`, `searching`, `sorting`, `focusing`, `dragging`. One step in front of any data: a filter, a sort, a search. They work for every domain, which is what makes them worth reading.

**Files.** `filesystem`, `filesystem_widget`, `files`, `table`, `math_table`. The parts the application is built from.

**The assistant.** `assistant`, `conversation_widget`, `conversation_editor`. The conversation as a document. The example answers from a canned transcript, so a test needs no model; [assistant-guide.md](assistant-guide.md) says how to talk to a real one.

The seven examples below are the ones to read in order.

---

## 1. JSON (`run_example("json")`)

<img width="396" alt="Json example" src="../asset/image/example/json.png">

**What it demonstrates:** The foundational pipeline — the one every other
domain is modelled after.

```
JsonObject ──JsonToSyntax──▶ SyntaxNode ──SyntaxToText──▶ TextBlock ──TextToGraphics──▶ GraphicsCanvas
```

The example opens a small JSON object loaded from
`example/workspace/contact-list.json`. You can navigate with the arrow keys;
the cursor moves through the JSON value characters and the structural
delimiters (`{`, `}`, `"`, `,`).

**What to try:**
- Press `←` / `→` to move the cursor.
- Run `print_example("json")` to see the full projection output as text.
- Run `write_example_image("json", "/tmp/j.png")` to capture a screenshot, or
  `write_example_pdf("json", "/tmp/j.pdf")` for a vector PDF.

**Concepts illustrated:**
- Domain-to-domain projection (`JsonToSyntax`)
- Bidirectional pipeline: printer forward, reader backward
- `ProjectionReferenceStep` — cursor positions on the `"` delimiters have no
  JSON counterpart; they are represented as `ProjectionReferenceStep(proj, .open + {k})`
- The IO map: each projection step records enough to invert itself

---

## 2. Syntax (`run_example("syntax")`)

<img width="586" alt="Syntax example" src="../asset/image/example/syntax.png">

**What it demonstrates:** The *syntax* domain is the generic intermediate
between semantic domains (JSON, XML, Math, Julia, …) and text. Using it
directly shows how a `SyntaxNode` tree looks before and after the text
rendering step.

```
SyntaxNode ──SyntaxToText──▶ TextBlock ──TextToGraphics──▶ GraphicsCanvas
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

<img width="1024" alt="Widget example" src="../asset/image/example/widget.png">

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
- Domain independence: `WidgetToGraphics` has no reference to JSON
- `GraphicsViewport` — how scroll panes clip content to a bounding box
- Event routing through composite projections
- The pane tree (`run_example("pane")`) extends this further with tab groups
  and splits

---

## 4. Table (`run_example("table")`)

<img width="397" alt="Table example" src="../asset/image/example/table.png">

**What it demonstrates:** a `WidgetTable`, the table abstraction, with each
cell recursed through its own domain to graphics. `NaturalToGraphics`
dispatches the grid layout, the widgets, and each cell's document type (JSON,
Primitive, Math, …) the same way it dispatches any other value.

```
WidgetTable ──NaturalToGraphics──▶ GraphicsCanvas
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

<img width="336" alt="Julia example" src="../asset/image/example/julia.png">

**What it demonstrates:** Editing source code as an AST, not as text. The
Julia domain provides types for identifiers, integers, binary operators,
function calls, if expressions, functions, and blocks.

```
JuliaBlock ──JuliaToSyntax──▶ SyntaxNode ──SyntaxToText──▶ TextBlock ──TextToGraphics──▶ GraphicsCanvas
```

The example opens a small Julia program fragment. Navigate through the AST
nodes; the cursor understands the structure of the code.

**What to try:**
- Navigate into nested function calls and if bodies.
- Run `print_example("julia")` to see the syntax-tree representation.
- Compare with `print_example("math")` — the math domain uses the same
  pipeline shape.

**Concepts illustrated:**
- Source code as a domain of its own (not just text)
- `RecursiveProjection` — `JuliaToSyntax` recurses into child expressions
  using the same projection for each node type
- How `TypeDispatchingProjection` dispatches on `typeof(input)` to pick the
  right sub-projection for each AST node kind

---

## 6. Pane tree (`run_example("pane")`)

**What it demonstrates:** The generic tab-and-split layout that organizes any
documents on the screen. `PaneToWidget` renders a `PaneTree`'s `PaneSplit`s and
`PaneGroup`s into split panes and tabbed panes, and each tab's content passes
through untouched, so a plain string, a JSON file, or an assistant all draw
through the renderer that follows.

```
PaneTree ──PaneToWidget──▶ WidgetSplitPane / WidgetTabbedPane ──WidgetToGraphics──▶ GraphicsCanvas
```

The example opens a layout with two panes side by side, the right one split
again so three groups share the window: two tabs of plain text on the left, one
tab of notes and one of scratch space on the right.

**What to try:**
- Press `Ctrl+Tab` / `Ctrl+Shift+Tab` to move the focus between groups.
- Press `Ctrl+\` to split the focused group, or `Ctrl+T` to open a new tab in it.
- Run `run_example("pane_json")` for a layout whose focused tab holds a real
  JSON document instead of plain text — any domain works in a tab, because the
  tab's content passes through the pane stage untouched.

**Concepts illustrated:**
- Compound projection: the pane stage computes the layout, and the renderer
  that follows computes how each tab's content looks — the same split every
  domain projection keeps
- `PaneGroupToWidgetTabbedPane` / `PaneSplitToWidgetSplitPane` — each pane node
  projects to its matching widget container
- The tree's own `selection` names the focused tab; there is no separate
  active-tab field (see [pane.md](../package/platform/pane/pane.md))

---

## 7. A table and its detail page (a navigator in the application)

A navigator shows one part of a document at a time, as a tab of a browser shows
one page of a site, with Back, Forward, Parent and an address. This example is a
data frame of thirty rows in a navigator: the table is the first page, and a row
opens as a page of its own, a form of its columns. It runs in the application,
because the list of the choices of a name opens in a window of its own, which
the gallery of `run_example` does not draw.

```julia
using Projectured, ProjecturedSDL
run_application()
```

Then type in the Evaluator:

```julia
using ProjecturedDataFramesExample
open_pane!(make_data_frame_navigator_example(; rows = 30); title = "Products")
```

**What to try:**
- Double-click the number of a row, or select the row and press `Ctrl+Return`:
  the row opens as a page. `Ctrl+[` goes back to the table with the row still
  selected, `Ctrl+]` goes forward, and `Ctrl+Up` goes to the table.
- Click the arrow before "row 3" in the address: a list of the rows opens.
  Type `5` and press Enter to open row 5.
- Click **Names** in the bar to see the address as a path, then as a path with
  the type of each node.
- Press `Ctrl+L`, type `.rows[7]`, and press Enter to open row 7.
- Right-click a part of a page and choose **Open in a new tab**.

**Concepts illustrated:**
- The address is a path of the content and is kept in the document, so a save
  keeps it; a visit is view state, which undo does not record
- A page is drawn by the view of its type, so the navigator names no type of
  data frames; the data frame adapter gives a row a view of its own
- See [navigator.md](../package/platform/navigator/navigator.md)

---

## Going deeper

Once you have a feel for these examples, the natural next steps are:

- [Concepts](../design/concepts.md) — if you want the conceptual model before the code
- [Architecture](../design/system-anatomy.md) — module inventory and package/layer/slice structure
- [Projection system](../package/kernel/projection-system.md) — the four interface functions
- [Tutorial: new domain](new-domain-guide.md) — add your own domain
