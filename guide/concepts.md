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
sense for its data. For JSON strings that is `StringReplaceRangeOperation`
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

- **Printer** (`projection_print`) — translates the input document forward into
  an output document in the next domain. Every projection returns an *IO map*
  alongside the output: a record of the correspondence between input and output
  elements that the reader needs to invert the transformation.

- **Reader** (`projection_read`) — translates a user event or an operation in
  the output domain backward into an operation in the input domain.

Projections are composable. The standard pipeline for JSON looks like:

```
JsonObject
  ──[JsonToSyntax]──▶ SyntaxNode
  ──[SyntaxToText]──▶ TextText
  ──[TextToGraphics]──▶ GraphicsCanvas ──▶ SDL window
```

`SequentialProjection` chains them. The printer runs left to right; the reader
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

Every document node carries its own `selection` field — the *suffix* of the
full selection path that starts at that node. This distributed storage means
the projection can read a node's selection without knowing the full path to the
root, and `set_selection!` writes to each node along the path independently.

### 5. Operation

An **operation** is the description of a mutation in a domain's own terms.
The most common is `ReplaceSelectionOperation` — move the selection to a new
path. Character-level editing uses `StringReplaceRangeOperation` (insert or
delete a range of characters in a string). Structural editing adds
`CollectionInsertOperation`, `CollectionDeleteOperation`, and so on.

Operations are produced by the reader side of the projection chain. When you
press `→`, `TextToGraphics` (the outermost projection) recognises the key and
produces `ReplaceSelectionOperation({current_pos + 1})` in the text domain.
`SyntaxToText` translates that to a selection step in the syntax domain.
`JsonToSyntax` translates it further to a step in the JSON domain. The editor
applies the final operation to the document.

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
On the next frame, the editor calls `projection_print` again. Because of the
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

- **[examples-tour.md](examples-tour.md)** — see these concepts in action across
  six concrete examples, from the simplest leaf case to a full workbench.
- **[getting-started.md](getting-started.md)** — set up your environment and run
  your first example.
- **[reactive-cells.md](reactive-cells.md)** — how the `Cell` system implements
  the reactive incrementality described in Step 5–6 above.
- **[projection-system.md](projection-system.md)** — the four interface functions
  (`projection_print`, `projection_read`, `map_reference_forward`,
  `map_reference_backward`) and how compound projections use them.
