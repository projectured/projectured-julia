# Finding and Selecting Nodes

> **Kind:** reference · **Status:** current · **Stands on:** [system-anatomy.md](../../design/system-anatomy.md)

How to locate a node in a document by *content* (not by a path you already know),
turn that into a reference, resolve a reference back to a node, and move the
selection there. This is the practical workflow for tasks like "select the string
'Alice'" or "highlight every number".

**Do not hand-walk the document tree** (`doc.windows[1].content.editing_page…`) to
find something — that is brittle and verbose. Search for it.

The three primitives, and how they compose:

| You have… | You want… | Use |
|-----------|-----------|-----|
| a document + a predicate **or string/regex** | the **paths** to matching nodes | `search_references(doc, query)` |
| a document + a predicate **or string/regex** | the **matching nodes** themselves | `search_documents(doc, query)` |
| a document + a path | the **node** at that path | `evaluate_reference(doc, path)` |
| a document + a path | the cursor moved there | `replace_selection!(doc, path)` |

## Two ways to write a query

Both search functions take a `query` that is *either*:

- a **predicate** `node -> Bool` — full control; match on type, field values, or
  structure (`v -> v isa JsonString && v.value == "Alice"`); or
- a **`String`** (substring) or **`Regex`** — a shorthand that matches any *leaf*
  node (string / symbol / number / char) by its string form.

```julia
search_references(editor.document, "Alice")           # JsonString whose value contains "Alice"
search_references(editor.document, r"TODO|FIXME")     # regex over leaf text, folds to enclosing document
search_documents(editor.document, r"^\d+$")           # every JsonNumber whose text is all digits
search_references(editor.document, v -> v isa JsonNumber)   # predicate: by type
```

The string/regex form matches the rendered text of leaf values (e.g. a `JsonString`'s
`.value`, a `JsonNumber`'s `.value`) and then **folds the match up to the nearest enclosing
`Document`** — so `search_documents(doc, "Alice")` returns the `JsonString` document
(not the bare `String` `"Alice"`), and `search_references(doc, "Alice")` returns the path to
that `JsonString`. A scalar match with no enclosing document is dropped. Pass `raw=true` to
opt out: `search_documents(doc, "Alice"; raw=true)` returns `["Alice"]` (the bare string).

### One walk, two searches

`search_documents` and `search_references` are not two implementations. They are the same
traversal — `walk_document` in the document layer — along the same `DocumentWalk`. The walk
holds the rules of the route: which nodes it opens, which fields it enters, which children it
enters, in what order, and how often it visits a node that two places share. The search
decides only how a match is named. `search_documents` answers the node itself, or with
`places = true` the node with its place, a `ReferencedDocument`; `search_references` answers
the place alone, a `Reference`. Both live in the reference layer, because the document layer
cannot name a `Reference`: the walk names a match by a chain of steps (`paths = true`), and the
search turns the chain into a reference.

By default the walk visits each node once, at the first path that reaches it, so a node that
two places share is reported once by both searches, at its first place. A caller that must
know every place of a node, as the check whether a value stands at one place does, passes
`walk = DocumentWalk(; policy = :once_per_path)`. That walk visits a shared part once for
each path, so it costs more as the sharing grows: in a window with a 300-row JSON file and 20
edits, the old versions that undo keeps share their rows, and a walk that enters them finds
one row at 441 paths.

The default walk does not enter the mouse target, the selection, or a field that a document
keeps out with `is_field_walked`: the node that a link names, and the old versions of an
undo buffer. To search old versions, search the list of an undo buffer itself.

Struct and collection nodes have no string form, so they never match a string/regex query.
Reach for a predicate when you need to match by type or shape, or to match a leaf
*exactly* (`v -> v == "Alice"`) rather than as a substring. A predicate that matches a
`Document` directly is returned as-is (no folding needed).

## Searching for references — `search_references`

```julia
search_references(obj, predicate; walk=DocumentWalk(), maxdepth=64, limit=100, maxvisits=100_000,
                  raw=false, background=false) -> DocumentMatches{Reference}
search_references(obj, query::Union{AbstractString,Regex}; …)  -> DocumentMatches{Reference}
```

Walks `obj` and returns a document-rooted `Reference` for each node whose
(cell-unwrapped) value satisfies the query. With a predicate, a predicate that
throws on some node is treated as "no match" there, not an error.

By default, when a string/regex query matches a raw scalar leaf (e.g. a `JsonString`'s
`.value` field, which is a plain `String`), the path is **folded up to the nearest enclosing
`Document`** — so the returned path points to the selectable `JsonString` node, not to its
internal string field. Pass `raw=true` to return the path to the exact matched node instead.

- A node reachable by **several paths** yields one result, at the first path; with
  `walk = DocumentWalk(; policy = :once_per_path)` it yields **one result per path**.
- Paths that **loop back** through an object already on the current path are
  dropped, so cyclic structures (e.g. a doubly-linked list's `prev`/`next`) stay
  finite.
- `maxdepth` bounds recursion for structures whose nodes are never the *same*
  object — e.g. an infinite lazy list, which the cycle guard alone cannot stop.
- `maxvisits` bounds the nodes that the walk visits, so a search of a large table
  stops.
- A match whose path does not read back to it, such as a match in a dict whose keys
  are types, is left out and counted.
- The walk decides the route. `DocumentWalk(; descend = (parent, child) -> …)`
  enters only the children that it accepts, and
  `DocumentWalk(; enter_field = (node, name) -> name === :selection || is_field_entered(node, name))`
  also walks the `selection` fields.

Because the returned paths are document-rooted, they resolve with
`evaluate_reference` and can be handed straight to `set_selection!` /
`replace_selection!`. A search of a part returns paths from the root of the part.

## Searching for documents — `search_documents`

```julia
search_documents(obj, predicate; walk=DocumentWalk(), places=obj isa ReferencedDocument,
                 maxdepth=64, limit=100, maxvisits=100_000, raw=false, background=false) -> DocumentMatches
search_documents(obj, query::Union{AbstractString,Regex}; …)  -> DocumentMatches
```

Same walk (and the same string/regex shorthand), but returns the matching
**nodes themselves**. With `places = true` it returns each node with its place, a
`ReferencedDocument`, which reads like the node and which a verb that needs a place
takes as it is; a search of a part returns places by default, after the place of the
part. A search of the editor's document with `places = true` returns places in the
window.

By default, a string/regex match on a raw scalar leaf **folds up to the nearest enclosing
`Document`** — so `search_documents(doc, "Alice")` returns the `JsonString` node (whose
`.value == "Alice"`), not the bare `String` `"Alice"`. A predicate that matches a `Document`
directly is returned unchanged. A scalar match with no enclosing document is dropped, so every
result is an addressable, selectable document node.

Pass `raw=true` to opt out of folding and return the exact matched value:

```julia
search_documents(doc, "Alice")          # [<JsonString value="Alice">]  (the enclosing document)
search_documents(doc, "Alice"; raw=true)  # ["Alice"]                   (the bare string)
search_documents(doc, r"^\d+$")           # [<JsonNumber …>, …]         (enclosing JsonNumber documents)
search_documents(doc, r"^\d+$"; raw=true) # [10, 20, …]                 (the raw numbers)
```

## The limits of a search

A search has three limits. Each has a default that keeps a search of a large
document small, and the caller can lift each one:

| Keyword | Default | What it limits |
| --- | --- | --- |
| `limit` | `100` | the count of matches; `limit = nothing` finds every match |
| `maxdepth` | `64` | how deep the walk goes |
| `background` | `false` | whether the walk waits for a value that a task still computes; by default it takes such a value as it is |

The answer is a `DocumentMatches`: a vector of the matches, so a caller indexes,
iterates and counts it as a vector, which also holds the limits and what each one
left out (`found.limits`). Its summary, the first line of its display, names each
limit that stopped the search and the keyword that lifts it. A person in the REPL
and the assistant both see it:

```julia
search_documents(editor.document, "temperature")
# 100 matches. The search stopped at its limit of 100 matches, and more exist: pass `limit = nothing` to find all:
#  <JsonString value="temperature">
#  ⋮
is_search_complete(search_documents(editor.document, "temperature"; limit = nothing))   # true
```

`is_search_complete(found)` answers whether no limit left a match out. Code that
must visit every match of a kind, such as a save that writes every node with a
pointer path, passes `limit = nothing`. A search for one object, or for whether any
node matches, keeps the default.

The walk counts a value still to come where it reads a cell: in a field of a
document. An element of a collection is read through the collection, which answers
its value and not its cell, so the walk neither counts nor waits for an element
still to come.

## Resolving a reference — `evaluate_reference`

```julia
evaluate_reference(document, path) -> node
```

The inverse of searching: walk `path` from `document` and return the node it
points at (unwrapping cells, descending fields and elements). This is the
`(document, reference) → node` direction. See the
[reference guide](reference.md#resolving-and-validating-a-reference) for details and
the type-checkpoint validity rules.

## The round trip

```julia
# 1. Find: paths to every JSON string containing "TODO".
refs = search_references(editor.document, v -> v isa JsonString && occursin("TODO", v.value))

# 2. Resolve (optional): a path back into its node.
node = evaluate_reference(editor.document, first(refs))   # the JsonString

# 3. Select: move the cursor to a match.
replace_selection!(editor.document, first(refs))
```

`search_references` → paths, `evaluate_reference` → node from a path,
`replace_selection!` → cursor at a path. See the
[selection guide](selection.md) for how the selection then propagates through the
projections and renders.

## Acting on what you found: build an operation, evaluate it

Selecting is one case of the general way to change the document: build an
`Operation` and apply it with `evaluate_operation(editor, op)` — the same step the
editor loop runs after a gesture. The full pattern is **find → build operation →
evaluate**:

```julia
# Select (ReplaceSelectionOperation is what replace_selection! wraps):
ref = first(search_references(editor.document, v -> v isa JsonString && v.value == "Alice"))
evaluate_operation(editor, ReplaceSelectionOperation(ref))

# Any other action: find the target, build the op carrying it, evaluate.
tree = get_window_tree(; editor)
group = first(search_documents(editor.document, x -> x isa PaneGroup && !isempty(x.tabs)))
evaluate_operation(editor, make_pane_close_tab_operation(tree, group, 1))
```

Because operations carry their own target and `evaluate_operation` is
wrapper-agnostic, this works regardless of how the document is nested
(`ScreenDocument` → `WindowDocument` → …). Reach for this instead of bespoke
imperative helpers. See the [operations guide](operation.md) for the full
operation catalogue and `evaluate_operation`.

## Worked example: select "Alice"

```julia
# Find the JSON string whose value is exactly "Alice", anywhere in the document,
# and select it. No need to know its path in advance.
refs = search_references(editor.document, v -> v isa JsonString && v.value == "Alice")
isempty(refs) || replace_selection!(editor.document, first(refs))

# The same, using the string shorthand — matches any leaf containing "Alice":
refs = search_references(editor.document, "Alice")
isempty(refs) || replace_selection!(editor.document, first(refs))
```

To select just the character range rather than the whole value, extend the found
path with the cursor/range step the domain uses (for a JSON string value, a
`RangeReferenceStep` over the text — see the [reference guide](reference.md) and the
JSON section of the [reference guide](reference.md#json-domain)).

## Scoping a search to one domain

A pane tree can mirror one document into two tabs at once — the tree's own
selection tracks one caret shared between them (see
[pane.md](../platform/pane/pane.md#a-duplicate-is-a-pane-of-its-own)) — so a bare value
query returns **one hit per tab** and cannot tell them apart:

```julia
search_references(editor.document, "Alice")                       # ← matches in every tab that mirrors it
search_references(editor.document, n -> n isa AbstractString && n == "Alice")  # same problem
```

Match the **domain node type** instead — that confines the result to the domain
you mean:

```julia
search_references(editor.document, v -> v isa JsonString && v.value == "Alice")
```

If several editors of the same domain are open, first locate the document you want
and search the editor that holds it:

```julia
jsondoc = first(search_documents(editor.document, x -> x isa JsonDocument))
# …then search editor.document with a predicate keyed to that doc's nodes.
```

Searching `jsondoc` directly returns paths rooted at `jsondoc`, **not** at
`editor.document`, so those paths are not directly selectable on the screen.
Search `editor.document` with a domain-typed predicate when you intend to select.

## Searching more than the document (iomaps)

Both search functions walk **any** object graph, not only documents — so you can
point them at an **iomap** to search the *whole projection pipeline* at once:
every intermediate document and every projected output tree, at every stage.

```julia
iomap = print_document(proj, doc)             # links input → output, holds every stage
search_references(iomap, "Wonderland")        # every location across the pipeline
search_documents(iomap, x -> x isa JsonNumber) # every number, source through output
```

This is a **debugging / inspection** tool: the returned paths are rooted at the
iomap (`::…IoMap.input…` / `.output…`), so — like searching `jsondoc` above —
they are **not** selectable on the screen. It is the tool to reach for when a
value is in the document but not on screen, to find which stage dropped it,
and for diagnosing reactivity. The [debugging guide](../../guide/debugging-guide.md#searching-the-pipeline-state-iomaps)
covers the workflow (reading iomap paths, `search_references` vs `search_documents`
counts as a reactivity signal).

## Notes

- All three primitives unwrap reactive `Cell`s transparently — you do **not**
  write `node.field[]`; property access already gives the value (see
  [macros guide](macros.md)).
- The predicate runs in the **document (input) domain** — match on
  `JsonString` / `JsonNumber` / … document nodes, not on projected text/graphics.
- A `String`/`Regex` query is a leaf-text shorthand; it cannot distinguish
  domains (see "Scoping a search to one domain"). Use a typed predicate to scope.
- In the running editor `editor.document` is a `ScreenDocument`; searching it
  walks through the window(s) into the pane tree automatically, so a content-based
  search does not care about the screen/window wrapping.
- `execute_julia_code` keeps top-level bindings between calls (a persistent
  scratch module), so you can assign `paths = …` in one step and use it the next.
