# Core Concepts

This guide explains what projectional editing is, why it matters, and how
ProjecturEd's five core ideas fit together. No code, no reactive-cell internals
— just a mental model you can carry into the rest of the documentation.

---

## What is projectional editing?

Open a JSON file in a traditional text editor. What you see is a string of
characters. What you *mean* is a data structure: nested objects and arrays with
typed values. The editor doesn't know the difference — it will let you break the
syntax completely and show you no indication of the structural meaning until you
save and your linter complains.

A **projectional editor** flips this around.

1. **The model is the truth.** The editor stores your data as a structured
   object — a `JsonObject` with named fields, not a string that happens to look
   like JSON. The object knows it is a JSON object. Its children know they are
   strings, numbers, arrays, or nested objects.

2. **What you see is a projection.** The on-screen text is produced by a
   *projection function* — a translation from the structured model into a
   displayable form. For JSON that might be `JsonObject → Syntax tree → Styled
   text → Pixel graphics`. The text you see is derived, not primary.

3. **What you type edits the model.** When you press a key, the editor does not
   insert a character into a buffer. It runs the key event backward through the
   same projection chain — the *reader* — to determine which structural
   operation the keystroke means in the model's own terms. Then it applies that
   operation, re-derives the display, and shows the updated view.

The result: you can never accidentally produce malformed JSON. You can switch
the projection and see the same data as a widget form, a table, or a custom
notation — without changing a single byte of the underlying model. Undo always
undoes a meaningful operation, not an accidental character.

---

## The five core ideas

### 1. Domain

A **domain** is a set of data types that belong to one problem area. The JSON
domain has `JsonObject`, `JsonArray`, `JsonString`, `JsonNumber`, `JsonBool`,
and `JsonNull`. The text domain has `TextText`, `TextString`, `TextNewline`.

Domains are completely independent of each other. A JSON domain type knows
nothing about how it will be displayed, and a text domain type knows nothing
about JSON. This independence is what makes the system composable.

Every domain also defines **operations** — the primitive mutations that make
sense for its data. For JSON strings that is `ReplaceStringRangeOperation`
(insert or delete characters). For JSON arrays it is a collection insert or
delete. Operations are structural: "insert element at index 3" rather than
"delete the `[` at line 12 column 7".

### 2. Document

A **document** is a live instance of a domain's data types. In ProjecturEd,
"live" means that every field is a *reactive cell* — a value that knows who
depends on it and can invalidate them when it changes.

You can think of a document as a reactive tree: a `JsonObject` node whose
`entries` cell holds a vector of `JsonObjectEntry` nodes, each of which holds
a `key` cell and a `value` cell pointing to a child document.

The reactive structure is invisible in normal use — the `@document` macro makes
field access look like plain Julia struct access. But under the hood, every read
of `doc.entries` registers a dependency, and every write automatically
invalidates anything that depended on it.

### 3. Projection

A **projection** is a bidirectional transformation between two domains. It has
two sides:

- **Printer** (`print_document`) — translates the input document forward into
  an output document in the next domain. Every projection returns an *IO map*
  alongside the output: a record of the correspondence between input and output
  elements that the reader needs to invert the transformation.

- **Reader** (`read_intent`) — translates a user event or an operation in
  the output domain backward into an operation in the input domain.

Projections are composable. The standard pipeline for JSON looks like:

```
JsonObject
  ──[JsonToSyntax]──▶ SyntaxNode
  ──[SyntaxToText]──▶ TextText
  ──[TextToGraphics]──▶ GraphicsCanvas ──▶ SDL window
```

`ChainingProjection` chains them. The printer runs left to right; the reader
runs right to left, translating the raw key event back through each step.

Because projections are pure functions (no side effects, no mutable state), they
can be freely combined, swapped, and layered. You can insert a sorting
projection before `JsonToSyntax` and the output automatically becomes sorted —
no special sorting-aware JSON projection needed.

### 4. Selection

The **selection** is a path through the document tree that identifies the
currently focused position. It is expressed as a sequence of *reference steps*:

| Step | Meaning |
|---|---|
| `[i]` | Descend to the i-th child (1-based) |
| `.field` | Descend into the named field |
| `{k}` | Cursor at boundary position k (0-based) within this node |

For example, `[1] + .value + {3}` means: first entry of an object → its value
field → cursor at offset 3 within that value.

A `.field` step is resolved by `getfield(document, :field)`, so **a document's
struct field names *are* its public reference vocabulary**: `.value`, `.entries`,
`.children` work because those are literally field names. This is a deliberate,
load-bearing design choice — it means renaming a field is a breaking change to
every stored selection and every projection. (See the `Document` contract in
[document/Interface.jl](../package/kernel/main/document/Interface.jl).)

Every document node carries its own `selection` field — the *suffix* of the
full selection path that starts at that node. This distributed storage means
the projection can read a node's selection without knowing the full path to the
root, and `set_selection!` writes to each node along the path independently.

### 5. Operation

An **operation** is the description of a mutation in a domain's own terms.
The most common is `ReplaceSelectionOperation` — move the selection to a new
path. Character-level editing uses `ReplaceStringRangeOperation` (insert or
delete a range of characters in a string). Most other edits — setting a field,
swapping a value, inserting or deleting sequence elements — are the single
generic `ReplaceReferencedValueOperation` (a slot write, with the slot named by a
reference), often built via `replace_document` / `insert_elements` /
`delete_elements`. See [operations.md](../package/kernel/doc/operation.md).

Operations are produced by the reader side of the projection chain. When you
press `→`, `TextToGraphics` (the outermost projection) recognises the key and
produces `ReplaceSelectionOperation({current_pos + 1})` in the text domain.
`SyntaxToText` translates that to a selection step in the syntax domain.
`JsonToSyntax` translates it further to a step in the JSON domain. The editor
applies the final operation to the document.

---

## The document editing model — one cluster spread across layers

The five ideas above are not five independent modules. They form a single
**mutually-recursive cluster** that expresses the same object — an edit into a
document — from five sides:

- A **`Document`** is what is being edited.
- A **`Reference`** is a path into a `Document` (both for the current selection
  and for expressing where an edit lands).
- An **`Operation`** is a reified edit — typically identified by the reference
  it targets.
- A **`gesture`** is a backend-agnostic input event (a keystroke, a mouse
  click) — the raw thing a user does.
- A **`projection`** turns a `Document` into an output document (the printer),
  and a `gesture` back into an `Operation` in the model's own vocabulary (the
  reader).

Reading in a straight line — Document → Reference → Operation → gesture →
projection — the *concepts* form a DAG (each stage names only earlier ones).
But the *contracts* between them close the loop: an `Operation` is applied
back to a `Document`; a `projection` reader lifts a `gesture` into an
`Operation` against a `Document`. That closure is what makes the pieces feel
tangled if you look at them as separate modules and clean if you look at them
as one editing model.

### Where each piece lives in the kernel

The code follows the concept DAG rather than the closure — each open
interface sinks to the lowest layer where every concept it mentions is
already introduced (AR-47), so a reader in load order never hits an
undefined name:

| Concept | Home in the kernel | What it defines |
|---|---|---|
| `Document` | layer 2 — `document/Interface.jl` | the abstract supertype and the "carries a selection field" obligation. The `@document` codegen and value protocol live alongside in `document/Document.jl`. |
| `Reference` | layer 3 — `reference/Reference.jl` | the reference-step and reference-path types, the value protocol on them, and the `@reference` DSL. |
| Selection generics | layer 3 — `reference/Selection.jl` | `get_selection` / `clear_selection!` / `set_selection!` / `with_selection` — the open generics that read and canonicalize a document's `selection` field. Their default implementations are the concrete edit walkers in `operation/Operations.jl` (a downward edge from layer 4 to layer 3). |
| `Operation` | layer 4 — `operation/OperationModule.jl` | the abstract supertype, `evaluate_operation`, the concrete edit types (`ReplaceSelectionOperation`, `ReplaceReferencedValueOperation`, `CompoundOperation`, …), and the `reroot_operation` seam. |
| `gesture` and `read_gesture` | layer 5 — `device/GestureBinding.jl` | the reified gesture patterns, the `@gestures` registry, the `read_gesture(document, gesture)` open seam and its `@gestures`-driven catch-all. |
| `projection` | layer 7 — `projection/Projection.jl` | the `Projection` abstract type, the four interface functions (`print_document`, `read_intent`, `map_reference_forward`, `map_reference_backward`), and the `@projection` macro. |

The umbrella package (`Projectured`) re-exports every name from every home, so
downstream code that writes `using Projectured` sees the cluster flat and does
not need to know which layer any given generic sits in. Only kernel-internal
imports and the per-package `…ApiModule` aliases in `visual/` and `domain/`
reach for each generic in its home module.

### Why the split matters

The cluster's mutual recursion is real at the *contract* level, but only real
at the *code* level for those files that name several of these concepts (the
`Operation` fragment that implements `set_selection!`; the projection reader
that lifts a `gesture` to an `Operation`). Every other file names only its own
piece. Splitting the interfaces into their concept-level homes is what lets
the layer guard stay a topological sort — each file's imports look downward
in load order — and lets a reader introduce concepts in a fixed dependency
order rather than in the mutually-recursive form the runtime uses them.

---

## Design principles: primitives, combinations, abstractions

The expressive power of any compositional system depends on three things: its
**primitive elements**, its **means of combination**, and its **means of
abstraction**. ProjecturEd applies this triad twice — once to documents, once
to projections — and the symmetry between the two is what makes the editor
general rather than tied to any one domain or any one display.

### Documents

- **Primitive documents** are the atomic data types of a domain — `JsonString`,
  `JsonNumber`, `TextString`, `SyntaxLeaf`, `GraphicsRect`. Each is small,
  typed, and has a clear meaning inside its own domain.
- **Combination** happens by nesting. A `JsonObject` holds entries that hold
  strings and child documents; a `TextText` holds a vector of strings and
  newlines; a `GraphicsCanvas` holds shapes. The recursive structure lets a
  primitive grow into an arbitrarily large document without changing how its
  parts behave.
- **Abstraction** is ordinary Julia code. Any function that builds and returns
  a document — a constructor for a settings object, a fixture builder for a
  test, a generator that turns tabular data into a graph — is a domain-level
  abstraction. There is no special template language; if you can write a
  function, you can abstract a structural pattern.

### Projections

- **Primitive projections** transform one document type into one document type.
  `JsonToSyntax`, `SyntaxToText`, `TextToGraphics`. Each is a printer/reader
  pair with a single focused job.
- **Combination** happens through higher-order projections.
  `ChainingProjection` chains projections end-to-end; `NestingProjection`
  embeds one domain inside another; sorting, filtering, and focusing
  projections wrap an inner projection and modify its behaviour. The
  combinators are themselves projections, so they compose freely with each
  other. See [higher-order projections](../package/kernel/doc/higher-order-projections.md) for the
  full catalogue. What makes this composition work is that each projection is a
  **single-level transform**: it renders one level and delegates every child back
  through the four core functions (via the `recursion` parameter and the stored
  child IO maps), never walking the subtree itself. That is the
  [recursion contract](../package/kernel/doc/projection-system.md#the-recursion-contract), and it is why
  any domain immediately works under any higher-order projection.
- **Abstraction** is again ordinary Julia code. A function that returns a
  fully wired `ChainingProjection(...)` configured for a particular display
  — a JSON viewer, a syntax-highlighted Lisp editor, a workbench pane — is a
  projection-level abstraction. Whole families of editors are just functions
  over projections.

### Why the symmetry matters

Most structured editors expose only one of these axes. A JSON-aware editor
gives you primitive types and nesting but no abstraction over views. A
templating engine gives you abstraction over output but only one fixed display
of one fixed model. By treating documents and projections as values built from
the same primitive/combine/abstract pattern, ProjecturEd lets you grow either
dimension independently and combine them freely: a new domain immediately
benefits from every existing higher-order projection, and a new higher-order
projection immediately applies to every existing domain.

### Lazy, incremental evaluation makes it tractable

A compositional system pays a cost for its expressiveness: deep projection
pipelines would re-derive a great deal of structure on every change if
evaluated eagerly. ProjecturEd's reactive cell system makes this cost
incremental — a cell recomputes only when one of its inputs has actually
changed, and only when its value is next read. This guarantees two properties
that the compositional design alone could not:

- **Consistency.** Any view of the document is exactly what the current model
  projects to. There is no manual cache to invalidate and no derived state
  that can fall out of sync with its inputs.
- **Performance.** Editing a single character in a large document reruns a
  handful of cell computations, not the full projection chain. Pipelines can
  be arbitrarily deep without the user paying for unchanged subtrees.

The two ideas are mutually reinforcing: the compositional design would be
unusable without incrementality, and the incrementality would be wasted on a
non-compositional design. Together they are what let the editor stay both
general and fast. See [reactive cells](../package/kernel/doc/cell.md) for the underlying
mechanism.

---

## A step-by-step walkthrough: what happens when you press →

You are editing a JSON string `"hello"` and the cursor is between `l` and `l`
(position 2). You press the right arrow key.

**Step 1 — SDL delivers a key event.**
The SDL backend translates the raw SDL keycode into a `KeyDown(:right, Modifiers(...))` event.

**Step 2 — `TextToGraphics` reader receives the event.**
It looks at the current flat cursor offset (2) and produces:
```
ReplaceSelectionOperation({3})    # move to offset 3 in Text domain
```

**Step 3 — `SyntaxToText` reader receives that operation.**
It translates cursor position 3 in the text representation (accounting for
the `"` opening delimiter being 1 character) into a position reference within
the `SyntaxLeaf` node's value span:
```
ReplaceSelectionOperation(.value + {2})   # offset 2 in the string value
```

**Step 4 — `JsonToSyntax` reader receives that operation.**
The value span corresponds directly to the JSON string's content. Position 2
within the value is position 2 in the `JsonString`:
```
ReplaceSelectionOperation({2})    # cursor at offset 2 in JsonString domain
```

**Step 5 — The editor applies the operation.**
`evaluate_operation` calls `set_selection!(document, {2})`.
- Writes `{2}` into `JsonString.selection[]`.
- Since `SyntaxLeaf.selection` is a *computed cell* that reads
  `JsonString.selection`, it is now automatically stale.
- Since `TextText.selection` is a computed cell that reads `SyntaxLeaf.selection`,
  it too is stale.
- Since `GraphicsCanvas` contains a cursor `GraphicsRect` whose position depends
  on `TextText.selection`, it is stale.

**Step 6 — The printer re-renders.**
On the next frame, the editor calls `print_document` again. Because of the
reactive cell system, only the stale cells actually recompute — in this case,
just the cursor position computation. The text content, layout, and most of the
graphics are unchanged and served from cache.

**Step 7 — The new cursor is drawn.**
The `GraphicsCanvas` now contains a cursor rect at the new position. SDL renders
the frame, and you see the cursor one character to the right.

The entire round-trip — key → reader chain → operation → document update →
printer chain → screen — takes milliseconds and recomputes only the minimum
necessary subset of the document tree.

---

## What to read next

- **[Examples tour](examples-tour.md)** — see these concepts in action across
  six concrete examples, from the simplest leaf case to a full workbench.
- **[Getting started](getting-started.md)** — set up your environment and run
  your first example.
- **[Reactive cells](../package/kernel/doc/cell.md)** — how the `Cell` system implements
  the reactive incrementality described in Step 5–6 above.
- **[Projection system](../package/kernel/doc/projection-system.md)** — the four interface functions
  (`print_document`, `read_intent`, `map_reference_forward`,
  `map_reference_backward`) and how compound projections use them.
