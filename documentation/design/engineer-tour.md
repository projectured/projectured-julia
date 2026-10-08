# Engineer tour

> **Kind:** design · **Status:** current · **Stands on:** [concepts.md](concepts.md), [system-anatomy.md](system-anatomy.md)

This guide is for a software engineer who is new to ProjecturEd. It explains the
main concepts, how the concepts combine, and what the combinations make
possible. Read it before the architecture guide and before the code.

[Concepts](concepts.md) gives the short conceptual model. This guide is the long
form: it names every part, shows the real code of each part, and then spends
most of its length on **combination** — because almost nothing in ProjecturEd is
interesting alone. The last part gives you the rules to predict what the system
can do that this guide does not list.

You need Julia, and you need to know structs, modules, and multiple dispatch.
You do not need to know reactive systems or compiler theory.

---

## 1. One idea and one loop

### The idea

A text editor keeps your work as characters. It guesses the structure.

ProjecturEd keeps your work as **structured data** — a typed tree. What you see
on the screen is **derived** from that tree by a function. What you type is
translated **back** into a change of that tree. The characters are an output,
never the truth.

The function that derives the view is called a **projection**. A projection runs
in both directions. Forward it is the **printer**. Backward it is the
**reader**. This pair is the whole system:

```
        ┌─────────────┐    printer    ┌──────────────┐    printer    ┌────────────┐
        │   Document  │ ───────────▶  │ Intermediate │ ───────────▶  │  Graphics  │
        │  (domain A) │  ◀─────────── │  (domain B)  │  ◀─────────── │  / Display │
        └─────────────┘     reader    └──────────────┘     reader    └────────────┘
```

Two consequences follow at once, and they are the reason the system exists.

- You can not make a malformed document. The caret never stands at a place that
  the model does not have.
- One model can have many views. A view is a function, so you can add, remove,
  or swap it without a change of the data.

### The loop

The editor runs a read-evaluate-print loop. One frame does four steps.

```julia
run_read_stage!(editor)      # poll the devices, run the reader chain → an Operation
run_evaluate_stage!(editor)  # apply the Operation to the document
run_print_stage!(editor)     # run the printer chain → the output document, then render
_log_performance_counters!(editor)      # report the reactive counters of this frame
```

The loop lives in
[EditorModule.jl](../../source/kernel/editor/EditorModule.jl). Every concept in the next
part is a part of one of these four steps.

---

## 2. The vocabulary

Ten concepts. Each one has a short definition, the real code, and the rule that
matters most about it.

### 2.1 Cell — the reactive box

A `Cell` holds a value or a computation. When a computation runs, every cell it reads
becomes an upstream dependency. A write marks all downstream dependents invalid.
Nothing recomputes until somebody reads it.

```julia
c = Cell(42)                           # holds a value
c = Cell(@computation upstream[] + 1)  # holds a computation
c[]                                    # read (recomputes when invalid)
c[] = 7                                # write (invalidates the dependents)
```

Three kinds exist: `ReactiveCell` (tracks dependencies), `MutableCell` (a plain
box), and `ImmutableCell` (frozen). The reactive kind is the default.

**The rule.** Invalidation is eager, recomputation is lazy. This is why a deep
pipeline is affordable: an edit invalidates a path of cells, but only the cells
that the screen actually pulls on run again. See
[cell.md](../package/kernel/cell.md).

### 2.2 Document and domain

A **domain** is a set of document types for one problem area. A **document** is
a live instance of those types. The `@document` macro turns every field into a
cell and adds a `selection` field.

```julia
@document struct JsonString <: JsonDocument
    value::String
end
```

You read `s.value` and write `s.value = "x"` like a plain struct. The macro
generates the accessors that go through the cell. `getfield(s, :value)` is the
escape hatch that gives you the raw cell.

Domains are independent. `JsonString` has no reference to text, pixels, or
fonts. The JSON domain is a `json/` slice of the `domain` package; the visual
domains (`Text`, `Syntax`, `Graphics`, `Widget`, `Layout`) are slices of the
`visual` package.

**The rule.** A domain never names its display. That independence is what makes
one display work for every domain.

### 2.3 Reference — the path

A **reference** is a path into a document. It is a list of typed steps.

| Step | Means |
|---|---|
| `.field` | descend into the named field, by `getfield` |
| `[i]` | the i-th item of a sequence, 1-based |
| `{k}` | the caret at boundary k of a sequence, 0-based |
| `{s:e}` | the range from boundary s to boundary e |
| `proj(P, sub)` | jump into something that only projection `P` produced |

```julia
ref = @reference entries[1].value.value{3}   # char 3 of "Alice" in {"name": "Alice"}
node = evaluate_reference(document, ref)
```

Elements and positions are two readings of one axis. A sequence of n items has n
items and n+1 boundaries. `[i]` names an item, `{k}` names a boundary. The same
convention holds for array elements, object entries, and string characters.

Each path node also records the Julia type of the node it stands on. This *type
checkpoint* makes a stored path safe to replay after an edit:
`get_valid_reference_prefix` truncates a path at the first type that no longer
matches.

**The rule.** A `.field` step is `getfield`. So a document's field names are its
public path vocabulary, and a rename of a field breaks every stored path. See
[reference.md](../package/kernel/reference.md).

### 2.4 Selection — where the caret is

The **selection** is a reference that says where the caret is. It is not stored
in one place. Every document node holds the *suffix* of the path that starts at
that node.

```julia
replace_selection!(document, @reference entries[1].value.value{3})
```

`clear_selection!` walks the old path and writes `nothing`. `set_selection!`
walks the new path and writes each suffix into the node it passes.

An **empty** path is a real selection: it means "this whole element is
selected". The absence of a selection is `nothing`, which is a different thing.
An empty path maps through any projection by identity, so whole-element
selection works everywhere for free.

**The rule.** Because the suffix lives on the node, a projection can read a
node's selection and does not need the path to the root. See
[selection.md](../package/kernel/selection.md).

### 2.5 Gesture — what the user did

A **gesture** is a backend-independent input event.

```julia
KeyPress('a'; time = t)                             # a character
KeyDown(:left, ModifierKeys(); time = t)            # an arrow key
KeyDown(:return, ModifierKeys(ctrl=true); time = t) # Ctrl+Enter
MouseClick(:left, 132, 47; time = t)                # a click at a pixel
MouseScroll(0, 1, 200, 300; time = t)
```

`t` is the time of the input, in seconds on the clock of `time()`. Every event
holds one.

A gesture carries no meaning. It says what happened, not what it means. The
meaning belongs to the reader.

A document type declares which gestures it answers, as data:

```julia
@gestures JsonObject begin
    KeyPress(',') => "Insert a new entry" => append_insertion_operation(doc, :entries, JsonObjectEntry)
    KeyDown(:tab) => "Move from key to value" => move_to_field(doc; from = :key, to = :value)
    nothing       => "Move from value to key" => move_to_field(doc; from = :value, to = :key)
end
```

A rule with a `nothing` pattern has no key. Only its name reaches it, through
the command palette. The same table that fires a key is the table that the
palette lists, so what runs is what the user sees.

**The rule.** When a gesture needs no pixels, the **document** maps it, behind
`read_gesture(document, gesture)`. When a gesture needs the layout — a click, a
visual line up or down — the projection that owns the layout maps it. This split
is why the terminal backend can edit structure with no code of its own.

### 2.6 Operation — the reified edit

An **operation** is a change described in the document's own words. It is a
value, not a call.

```julia
ReplaceSelectionOperation(path)                      # move the caret
ReplaceReferencedValueOperation(document, ref, value) # write one slot
ReplaceStringRangeOperation(ref, replacement)         # edit characters
CompoundOperation([op1, op2])                         # apply several as one step
```

`ReplaceReferencedValueOperation` is the generic write. Its last step decides
what "write" means: a field step sets a field, a range step with one value
overwrites an element, and a range step with a vector splices — so an insert is
a zero-width splice and a delete is a splice with an empty vector. The builders
`make_replace_document_operation`, `make_insert_elements_operation`, and `make_delete_elements_operation` package the common
shapes.

`evaluate_operation(editor, op)` applies an operation. It is the **one** way to
change a document, and you can call it yourself:

```julia
ref = first(search_references(editor.document, v -> v isa JsonString && v.value == "Alice"))
evaluate_operation(editor, ReplaceSelectionOperation(ref))
```

**The rule.** Before you write a new operation type, ask whether the change is a
slot write. Most changes are. See
[operation.md](../package/kernel/operation.md).

### 2.7 Projection — the bidirectional map

A **projection** transforms one domain into another, in both directions. It has
exactly four entry points.

```julia
print_document(projection, recursion, input, context) → iomap
read_intent(projection, recursion, change::Intent, iomap) → Intent
map_reference_forward(projection, iomap, reference)  → output reference or nothing
map_reference_backward(projection, iomap, reference) → input reference or nothing
```

The four are two symmetric pairs. The printer uses `map_reference_forward` to
wire the output caret. The default reader uses `map_reference_backward` to move
the operation that arrives into the input domain. So you write the path map once
and both directions work.

Most projections need no reader at all. Write one only when the projection must
do more than re-target a reference.

The modern way to write a printer is `@projection_template`. You build the real
output document with its real constructor, and drop a **marker** where the
engine must wire something:

```julia
@projection_template JsonArrayToSyntaxNode JsonArray (prj, doc) ->
    SyntaxNode(collection(:elements);
               open=TextString("[", prj.delimiter_style),
               close=TextString("]", prj.delimiter_style),
               sep=TextString(", ", prj.separator_style),
               indentation=1)
```

Three markers cover the cases: `bound(:field, T, render)` binds an editable
value, `project(:field)` delegates a child to its own projection, and
`collection(:field)` delegates a whole children vector. The engine walks the
built value by reflection, records what each marker wired, and derives the
reference map from that record. Nothing is generated per type.

**The rule.** A projection transforms **one level** and delegates every child
back through the same four functions. It never walks the subtree itself. This is
the recursion contract, and part 4 explains why everything depends on it. See
[projection-system.md](../package/kernel/projection-system.md).

### 2.8 IO map — the record of the print

`print_document` does not return the output. It returns an **IO map**: the
projection, the input, the output, and whatever else the reverse direction
needs.

| Kind | Use |
|---|---|
| `SimpleIoMap` | the structure alone is enough to invert the print |
| `ChildrenIoMap` | the output has projected children; `child_iomaps` holds one map per child |
| `ContentIoMap` | the projection wraps one inner projection |
| `{Name}IoMap` | a projection that carries extra data, for example a character-to-pixel table |

The IO map is what makes the inversion possible. A reader that must descend into
a child does not guess which projection printed that child — it reads the child
IO map and delegates to the projection that is recorded there.

**The rule.** An IO map keeps its identity for the life of the projection
instance. What varies — the output, the caret, the child maps — is a computed
cell inside it. An edit writes a cell; it does not rebuild the map.

### 2.9 Backend and device

A **device** is a logical channel: `Display`, `Keyboard`, `Mouse`. A **backend**
is the platform that drives the devices: `SdlBackend`, `ConsoleBackend`,
`WebBackend`. The backend translates platform events into the gesture vocabulary
and renders the output document.

```julia
run_editor!(document, projection; backend = SdlBackend())   # a native window
run_editor!(document, projection; backend = WebBackend())   # the same editor in a browser
run_console_example(interactive=true)             # the terminal
```

The SDL and Web backends consume the `Graphics` domain, so the two calls above
take the same projection and the same document. The console backend consumes the
**`Text`** domain directly, with no graphics step at all — so it runs a shorter
pipeline and its own device list, a keyboard alone. That is the proof that the
pipeline is backend-independent: a backend may tap the chain at whatever stage it
can render.

**The rule.** Nothing above the backend names a platform. A projection sees
`KeyDown(:left)`, never an SDL keycode.

### 2.10 Editor — the loop that owns them

```julia
mutable struct Editor
    backend::Backend
    document::Document
    projection::Projection
    devices::Vector{Device}
    iomap::Union{IoMap, Nothing}
    operation::Union{Operation, Nothing}
end
```

The editor owns one document, one projection, one backend, and the IO map of the
last print. It is the only stateful part of the system. Documents are reactive
but passive; projections are pure values.

---

## 3. One keystroke, from the key to the pixel

Put a caret inside the JSON string `"hello"`, at offset 2. Press the right
arrow. Here is the whole round trip.

**1. The backend delivers a gesture.** SDL gives a raw keycode; the backend
turns it into `KeyDown(:right, ModifierKeys())`, wrapped in a `WindowInput`.

**2. The reader chain starts at the end.** The editor calls `read_intent` on the
top projection with `Intent(gesture, nothing)`. A `ChainingProjection` walks its
steps from last to first. The last step is `TextToGraphics`.

**3. `TextToGraphics` answers.** Right motion needs no pixels, so the projection
delegates to `read_gesture` on its input `TextBlock`. The text document answers
in its own words:

```
ReplaceSelectionOperation({3})     # boundary 3 in the Text domain
```

(A click would take the other branch. Then `TextToGraphics` would use its own
character-to-pixel table, because that branch does need the layout.)

**4. `SyntaxToText` maps it inward.** Text offset 3 sits inside the value span
of a `SyntaxLeaf`, one character after the `"` that opens the string:

```
ReplaceSelectionOperation(.value + {2})
```

**5. `JsonToSyntax` maps it inward again.** The leaf value is the JSON string
value:

```
ReplaceSelectionOperation({2})     # in the JsonString domain
```

Steps 4 and 5 need no hand-written reader. The default reader re-targets the
reference with `map_reference_backward`, which the two projections already
define for the printer.

**6. The editor applies the operation.** `evaluate_operation` calls
`clear_selection!` and then `set_selection!`. That writes a cell.

**7. The write invalidates a path of cells.** The `SyntaxLeaf` caret cell reads
the `JsonString` caret cell, so it becomes invalid. The `TextBlock` caret cell
reads that one, so it becomes invalid. The caret rectangle of the
`GraphicsCanvas` reads that one, so it becomes invalid. Nothing runs yet.

**8. The printer pulls.** On the next frame the renderer reads the canvas. Only
the invalid cells run again — the caret position. The glyphs, the layout, and
the rest of the graphics come from the cache.

**9. The backend draws the frame.** The caret is one character to the right.

Read the trace twice. The first read shows how an edit reaches the model. The
second read shows the thing that matters more: **the number of cells that ran is
a function of the change, not of the size of the document**.

---

## 4. How the concepts combine

The parts above are ordinary. The combination is not. ProjecturEd applies the
same three-part pattern — primitives, means of combination, means of abstraction
— to **two** layers, and then lets the two layers multiply.

### 4.1 Documents compose

- **Primitives** are the atomic types of a domain: `JsonString`, `TextString`,
  `SyntaxLeaf`, `GraphicsRect`, `WidgetButton`.
- **Combination** puts one document inside another. A field holds a document. A
  `CellVector` holds many. There is no privileged root type.
- **Abstraction** is a Julia function. Any function that returns a document is a
  document abstraction. There is no template language.

The important part is that a field may hold a document of **any** domain. A
`JsonObjectEntry.value` is declared `::Document`, not `::JsonDocument`. So a
book chapter can hold a JSON value, a table cell can hold a math expression, and
a chat message can hold Julia code. All three exist in the repository today.

### 4.2 Projections compose

- **Primitives** are the one-domain-to-one-domain pairs: `JsonToSyntax`,
  `SyntaxToText`, `TextToGraphics`, `WidgetToGraphics`, `PaneToWidget`.
- **Combination** is the higher-order projections. Each one takes other
  projections as arguments and is itself a projection, so they nest freely.
- **Abstraction** is again a Julia function. A function that returns a wired
  `ChainingProjection` is an editor.

The combinators:

| Combinator | Chooses by |
|---|---|
| `ChainingProjection` | position in a list — printer left to right, reader right to left |
| `TypeDispatchingProjection` | `typeof(input)` |
| `PredicateDispatchingProjection` | a predicate over the input |
| `ReferenceDispatchingProjection` | where the input sits in the document |
| `SwitchingProjection` | a reactive index cell, so the view can change at run time |
| `RecursiveProjection` | nothing — it passes *itself* as the `recursion` argument |
| `NestingProjection` | the element list, so one domain can host another |
| `ApplyAtProjection` | a reference — do X exactly there, preserve everything else |

And the domain-independent transforms, which work on **any** input by structure
rather than by type: `IdentityProjection`, `ConstantProjection`,
`CopyingProjection`, `ReversingProjection`, `SortingProjection`,
`FilteringProjection`, `SearchingProjection`, `FocusingProjection`,
`ObjectToWidget`.

A whole JSON editor is then five lines:

```julia
ChainingProjection(
    RecursiveProjection(JsonToSyntax()),
    RecursiveProjection(SyntaxToText()),
    TextToGraphics(measure = measure),
)
```

And a sorted JSON editor is the same five lines with one more:

```julia
ChainingProjection(
    ApplyAtProjection(@reference(entries), SortingProjection(by = e -> e.key)),
    RecursiveProjection(JsonToSyntax()),
    RecursiveProjection(SyntaxToText()),
    TextToGraphics(measure = measure),
)
```

The document is untouched. The sort is a view. To remove the sort, remove the
projection.

### 4.3 The contract that makes the composition work

Composition of this kind is not free. It works because of one rule. The rule is
important enough that this guide states it twice.

> A projection transforms **its own single level** and hands every child to the
> **child projection's own** version of the same four functions. The printer
> does this through the `recursion` argument. The reader and the two mappers do
> it through the stored child IO maps.

Two prohibitions follow.

- **Do not add a fifth recursive function.** Every projection implements the
  four. Some projections would implement a fifth and others would not. The first
  pipeline that mixes the two kinds breaks at that seam — which is the opposite
  of composition.
- **Do not walk a subtree yourself.** If a printer flattens its children into
  its own output, it hard-codes which projection renders each descendant. A
  child could be another domain, or the same domain under a substituted
  projection. Only single-level delegation lets the recursion follow whatever
  projection actually runs.

This is the reason a new domain works under every higher-order projection that
exists on the day you write it, and a new higher-order projection works over
every domain that exists on the day you write it. It is the most important rule
in the system.

### 4.4 The multiplication

Because both layers compose, and because neither layer names the other, the
capability is a **product**, not a sum.

```
    domains (json, xml, yaml, julia, math, sql, book, markdown, rst, graph,
             filesystem, fsm, chart, table, widget, pane, conversation, …)
  ×
    projection combinators (chain, dispatch by type / predicate / reference,
             recurse, switch, nest, apply-at, decorate)
  ×
    domain-independent transforms (sort, filter, focus, reverse, copy, search,
             reflect to a form)
  ×
    backends (SDL window, browser, terminal, image file, vector PDF, video)
```

Nobody wrote "a sorted, filtered view of the XML inside a book chapter, in the
terminal". It is a coordinate in that product, and it works because no cell of
the product has a reference to any other.

### 4.5 Incrementality pays for the composition

A deep pipeline of pure functions would be slow if it ran eagerly. The cell
system removes that cost, and it gives two properties that the compositional
design alone can not:

- **Consistency.** A view is always exactly what the current model projects to.
  There is no cache to invalidate by hand, and no derived state that can drift.
- **Performance.** One character of an edit runs a handful of cell computations,
  not the whole chain. Depth costs almost nothing.

The two ideas need each other. The composition would be unusable without the
incrementality, and the incrementality would be wasted on a design that did not
compose.

---

## 5. What this makes possible

### 5.1 A catalogue of combinations

Every row below is a combination of parts that already exist. Most are one or
two lines.

| You want | Combine |
|---|---|
| A sorted view, model untouched | `ApplyAtProjection(path, SortingProjection(by=…))` before the domain printer |
| A filtered view | `FilteringProjection` in the same place |
| A zoom into one subtree | `FocusingProjection` plus `ReplaceFocusPartOperation` to retarget it |
| Two live views of one document | two pipelines over the same document; they share the cells, so both update |
| A view that switches at run time | `SwitchingProjection` with a reactive index cell |
| One document that holds another domain | put the other document in a field; the type dispatcher finds its projection |
| A different display | change one argument of `run_editor!` |
| A picture, a PDF, or a video of a document | `write_image`, `write_pdf`, `record_video` |
| A new key in a domain | one `@gestures` rule beside the document type |
| A command with no key | a `@gestures` rule with a `nothing` pattern; the palette reaches it by name |
| Drag and drop for any list | wrap the subtree in `DraggingState`, add `DraggingProjection` |
| A tooltip on anything | `TooltipDecoratorProjection` |
| An editable form for any Julia object | `ObjectToWidget`, which reflects over the fields |
| A find bar: a form of the fields of a `HighlightedText` or a `FilteredText` | `FindBarView` |
| A conceptually infinite document | `ListNode` with a lazy `next` cell; the editor builds only what you look at |
| A database table as an editable document | `SqlToCellTable` → `CellTableToTable`, with the ODBC adapter behind it |
| Snapshots of the document over time | the versioning overlay |
| An AI that edits the model | the `execute_julia_code` tool or the MCP server; operations are the unit |
| A scripted, replayable session | a timeline of events and operations, fed to `play_live!` or `record_video` |

### 5.2 Read these three combinations closely

**The pane tree.** `PaneToWidget` prints a layout of tab groups and splits —
`PaneGroup` → `WidgetTabbedPane`, `PaneSplit` → `WidgetSplitPane` — as widgets. A
tab's content passes through this stage untouched, so the renderer that follows
holds an arbitrary projection over an arbitrary document. So the pane tree is not
a program that hosts documents; it is a document that hosts documents. Every
pane and every tab is selectable and editable by the same machinery as its
content.

**The AI assistant.** The chat is a `Conversation` document: messages, response
blocks, and code runs are structured nodes. The assistant changes the document
when it runs Julia against the live editor, so its edits are operations, not
keystrokes and not text patches. The editor edits its own AI session with the
machinery it uses for your data.

**The console backend.** It renders the `Text` domain straight to the terminal.
It never loads SDL and never sees the `Graphics` domain. You can still edit the
structure there, because the half of the gesture map that needs no geometry lives
on the **document**, behind `read_gesture`, and not in the graphics projection.
This one example proves three separate claims: the pipeline is
backend-independent, a backend may tap any stage, and the split between document
and projection sits in the right place.

### 5.3 How to extrapolate

Use these six rules to predict what the system can do.

1. **If the change is about what you see, it is a projection. If it is about
   what is true, it is an operation.** A sort of the display is a projection. A
   sort of the data is an operation. Undo of the first removes a view; undo of
   the second restores data.
2. **What one projection can do at one level, a higher-order projection can do
   at every level.** `ApplyAtProjection` is the general form: do X exactly at
   this reference, preserve the rest.
3. **A new domain gets every combinator free. A new combinator gets every domain
   free.** This holds only while the recursion contract holds.
4. **Cost follows attention, not size.** Off-screen subtrees cost nothing
   because nothing pulls on them. This is why an unbounded document is a normal
   case and not a special one.
5. **If you can name a place with a reference, you can act there.**
   `search_references` finds the path, `evaluate_operation` acts on it. That
   pattern works through any wrapper and in any domain.
6. **If a target can draw a `GraphicsCanvas` — or any earlier document in the
   chain — it can host the whole system.** An IDE plugin backend is the same
   shape of work as the browser backend.

### 5.4 The current frontiers

An honest introduction states the limits. These are open, and they tell you as
much about the design as the finished parts.

- **Undo and redo are opt-in.** An operation answers its own inverse
  (`make_inverse_operation`), and an `UndoBuffer` is a document that holds
  another document and the steps that take it back. The application puts one
  around each file and one around the window; a program that installs none has
  no history. The operation model is the reason this was a feature and not a
  rewrite. See [undo.md](../package/platform/undo/undo.md).
- **Character edits are not uniform.** They work end to end for the
  field-addressed domains — JSON, XML, YAML, text, prose, and the type-in path.
  The goal is every leaf in every domain.
- **Click-to-select is not everywhere.** It works where a projection records the
  coordinate map that the hit test needs.
- **Left caret motion stalls on projection-introduced text** in the
  syntax-backed pipelines. Right motion is complete.
- **The plan holds live collaboration and staged edits; the code does not yet.**
  Both are a transport layer and a buffer layer over the operation model.
- **Self-hosting is the long-term goal.** Edit ProjecturEd's own source inside
  ProjecturEd. It is the strongest test of the generality claim.

---

## 6. Build something small

### 6.1 Add a domain

1. Declare the types with `@document`, and the domain kit with `@domain`.
2. Write one `@projection_template` rule per type, usually to the `Syntax`
   domain.
3. Declare the domain gestures with `@gestures`.
4. Add an example document and an example pipeline.
5. Add a test.

You write no reader and no reference mapper for the normal case. The template
engine derives both from the markers. A simple domain is 50 to 150 lines. The
worked walkthrough is [new-domain-guide.md](../guide/new-domain-guide.md).

### 6.2 Add a projection

1. Declare the struct with `@projection`.
2. Implement `print_document`, and return one IO map that lives as long as the
   projection. Wire whatever varies as a computed cell.
3. Implement `map_reference_forward` and `map_reference_backward`, usually with
   `@reference_case`.
4. Add a `read_intent` method **only** if the projection must do more than
   re-target a reference.

### 6.3 Add a backend

Implement `initialize_backend!`, `quit_backend!`,
`take_from_devices!`, and `write_to_devices!`. Translate your platform events into
the gesture vocabulary. Choose which document your renderer consumes. Nothing
above the backend changes.

### 6.4 Test what you built

Run the **smallest** test that covers the change. Do not run `test_all` — it is
slow.

```julia
test_printer(json_example)              # the forward direction
test_reader(json_example)               # the backward direction
test_position_navigation(json_example)  # caret motion
test_example(json_example)              # all three
test_json()                             # one domain
```

The full table is in [testing-guide.md](../guide/testing-guide.md). For work in the REPL —
`run_example`, `print_example`, `write_example_image`, and how to drive the
printer and reader by hand — see [debugging-guide.md](../guide/debugging-guide.md).

---

## 7. Read next

| Goal | Guide |
|---|---|
| See the concepts at work | [Examples tour](../guide/examples-tour.md) |
| Set up and run something | [Getting started](../guide/setup-guide.md) |
| Understand the incrementality | [Reactive cells](../package/kernel/cell.md) |
| Understand the four functions in depth | [Projection system](../package/kernel/projection-system.md) |
| Understand the combinators in depth | [Higher-order projections](../package/platform/projection/higher-order-projections.md) · [Generic projections](../package/platform/projection/generic-projections.md) |
| Understand paths and the caret | [References](../package/kernel/reference.md) · [Selection](../package/kernel/selection.md) |
| Understand the macros | [Macros](../package/kernel/macros.md) |
| Find the code | [Architecture](system-anatomy.md) · [Terminology](../rule/division-terminology.md) · [Orientation](../guide/orientation.md) |
| Add your own domain | [Tutorial: new domain](../guide/new-domain-guide.md) |
| Know the direction of the project | [Vision](../requirement/product-vision.md) · [Roadmap](../requirement/delivery-roadmap.md) |
