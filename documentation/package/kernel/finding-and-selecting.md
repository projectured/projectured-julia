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
traversal — `walk_document` in the document layer — run under two `DocumentWalk`s that differ
in exactly one thing: **what a visited node's *location* is.** `search_documents` uses the
default, so the location is the node itself; `search_references` (which lives in the reference
layer, because the document layer cannot name a `Reference`) passes in location functions
that build the path to the node. Everything else — how to descend a collection, a dict, a
struct; where to stop; how to fold a scalar match up to its enclosing document — is written
once, and those location functions are its only parameters.

That difference has one consequence worth knowing, and it is not a quirk:

> **A node reachable by two paths is reported once by `search_documents` and twice by
> `search_references`.**

It is *one object* but *two places*, and a place is what a selection names — so both places
must be reported if you intend to put a cursor in one of them. Conversely, reporting the same
object twice would tell you nothing new. This is the `policy` each search sets on its
`DocumentWalk` (`:once_per_object` vs `:once_per_path`), and it is why the two cannot be
collapsed into one.

Struct and collection nodes have no string form, so they never match a string/regex query.
Reach for a predicate when you need to match by type or shape, or to match a leaf
*exactly* (`v -> v == "Alice"`) rather than as a substring. A predicate that matches a
`Document` directly is returned as-is (no folding needed).

## Searching for references — `search_references`

```julia
search_references(obj, predicate; include_selection=false, maxdepth=64, raw=false) -> Vector{Reference}
search_references(obj, query::Union{AbstractString,Regex}; …)                       -> Vector{Reference}
```

Walks `obj` and returns a document-rooted `Reference` for **every** node whose
(cell-unwrapped) value satisfies the query. With a predicate, a predicate that
throws on some node is treated as "no match" there, not an error.

By default, when a string/regex query matches a raw scalar leaf (e.g. a `JsonString`'s
`.value` field, which is a plain `String`), the path is **folded up to the nearest enclosing
`Document`** — so the returned path points to the selectable `JsonString` node, not to its
internal string field. Pass `raw=true` to return the path to the exact matched node instead.

- A node reachable by **several paths** yields **one result per path** — each path
  is a distinct *location*, hence a distinct selection.
- Paths that **loop back** through an object already on the current path are
  dropped, so cyclic structures (e.g. a doubly-linked list's `prev`/`next`) stay
  finite.
- `maxdepth` bounds recursion for structures whose nodes are never the *same*
  object — e.g. an infinite lazy list, which the cycle guard alone cannot stop.
- `include_selection=true` also walks `selection` fields (off by default).
- `descend(parent, child)` returns whether the walk enters `child` from `parent`;
  a child that it does not enter is neither matched nor walked. The default
  enters every child.

Because the returned paths are document-rooted, they resolve with
`evaluate_reference` and can be handed straight to `set_selection!` /
`replace_selection!`.

## Searching for documents — `search_documents`

```julia
search_documents(obj, predicate; include_selection=false, maxdepth=64, raw=false) -> Vector
search_documents(obj, query::Union{AbstractString,Regex}; …)                       -> Vector
```

Same walk (and the same string/regex shorthand), but returns the matching
**nodes themselves, each one once** even when a node is shared / reachable by
several paths. Use it when you want the values, not where they live
(`search_references` is the one to use when you intend to select).

`descend(parent, child)` returns whether the walk enters `child` from `parent`; a
child that it does not enter is neither matched nor walked. The default enters
every child.

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
