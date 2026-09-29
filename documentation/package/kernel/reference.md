# References

> **Kind:** reference · **Status:** current · **Stands on:** [system-anatomy.md](../../design/system-anatomy.md)

References are path-like pointers into document trees. A reference is a
sequence of typed *steps* that descend one level at a time through a document
tree, addressing exactly one location inside it. References let the editor
represent cursor positions, selections, and navigation through structured data
across domain transformations.

This page is the single home for the **reference grammar**: the step
vocabulary, the boundary axis, the two DSLs, type checkpoints, the path
structs, per-domain path tables, and searching (`search_references`). For how a reference
is *stored, propagated, and forward-projected* as the current selection, see
the sibling [selection guide](selection.md).

## The reference layer (kernel layer 11)

References are **layer 11 of the kernel** — paths into documents. The layer lives
in [source/kernel/reference/](../../../source/kernel/reference/), inside one aggregator module
(`ReferenceModule`) split across eleven fragments that share its namespace:

```
ReferenceModule.jl       (ReferenceModule)             — the aggregator
        │ imports Cell (from CellModule), @cell_struct (from CellStructModule),
        │ and Document (from DocumentModule, for the reflection-walker traits) and exports every
        │ public name below
        ├─ ReferenceInterface.jl — the contract: the ReferenceStep and
        │                        Reference abstract types, the Reference
        │                        union, and the open generics higher packages
        │                        add methods to (get_reference_step_kind, evaluate_reference_step, and
        │                        the reference-step DSL seams)
        ├─ ReferenceStep.jl    — the kernel step types (RangeReferenceStep,
        │                        FieldReferenceStep, TypeReferenceStep) and the Position
        │                        a cursor evaluates to, each packaged with its
        │                        own show, ==, and seam methods
        ├─ ReferencePath.jl    — the path structure and its document-free
        │                        algebra (EmptyReference,
        │                        ConcreteReference, extend_reference,
        │                        concat_references, get_reference_steps, the
        │                        equality/prefix predicates)
        ├─ ReferenceEvaluation.jl — walking a path against a document
        │                        (evaluate_reference, get_valid_reference_prefix)
        │                        and the "types always present" invariant
        │                        (annotate_reference_types, …)
        ├─ ReferenceSearch.jl  — the path-producing reflection search
        │                        (search_references)
        ├─ ReferenceSyntax.jl  — the surface grammar EVERY DSL accepts, parsed
        │                        once into one step AST (ReferenceSyntaxStep). The three
        │                        fragments below are lowerings of that AST,
        │                        not parsers of their own
        ├─ ReferenceGlob.jl    — the glob language (*, ?, {a-e}, {38..47}) over
        │                        one name; independent of `Reference` itself
        ├─ ReferenceCase.jl    — the @reference_case pattern-matching DSL
        │                        (destructures a path against pattern => result
        │                        rules), plus when/prefix guards
        ├─ ReferenceRules.jl   — the @reference_rules DSL: the same block of arms
        │                        kept as a VALUE (ReferenceRules), matched by an
        │                        interpreter over the same pattern AST
        ├─ ReferencePatternString.jl — the string spelling of a pattern: ref"…" and
        │                        parse_reference_pattern, for a rule set read from
        │                        a configuration file at run time
        └─ ReferenceBuilder.jl — the @reference / @reference_step construction DSL
                                 (compact surface syntax for building paths)
```

The DSLs read the **same path grammar** — `a.b`, `xs[i]`, `xs{k}`, `x::T`,
`.name(...)`, `^(e)` — so it is parsed in one place. Each DSL then *lowers* the
resulting AST: the builder to constructor calls, the matcher to match branches, and
`@reference_rules` to pattern *data* it interprets. Seven forms deliberately mean
different things on the building and matching sides, and the lowering is where that
difference lives (`@reference_rules` reads the matching column):

| Syntax | `@reference` / `@reference_step` builds | `@reference_case` matches |
| --- | --- | --- |
| bare symbol as a **subpath argument** | a field name | **binds** the whole subpath |
| bare symbol in a **value** position (`[i]`, `.field(e)`) | a runtime expression | **binds** the value |
| `_` | a field named `"_"` | a wildcard |
| `::T` (capitalised) | a type checkpoint, folded onto the node | **narrows** — the node's recorded type must be `<: T` |
| `::t` (lowercase) | splices `t`'s runtime type value | **binds** the node's folded `type` |
| `name...` | *rejected* — matcher-only | binds the remaining tail |
| `base.^(e)` | splices a runtime path | *rejected* — builder-only |

A leading identifier is also read differently by `@reference_step` (a placeholder, dropped:
`@reference_step xs[i]` yields just `[i]`) than by `@reference` (a field name).

`ReferenceInterface.jl` comes first for a reason beyond convention: the abstract types it
declares are named in the struct field annotations below it
(`head::ReferenceStep`, `tail::Reference`), and those are evaluated at
definition time, so the contract must be loaded before the types that satisfy it.

The eleven fragments are only ever imported together, so they share one
`ReferenceModule` namespace instead of being separate modules — splitting them
would just multiply import headers. They still live in separate files for
readability, but as **fragments** (0-module files sharing the aggregator's
namespace), not separate modules.

### Downward edges

- `..CellModule: Cell, AbstractCell` and `..CellStructModule: @cell_struct` — the
  reactive box the mutable step fields live in, and the macro that builds each step/path
  struct with its cells. Steps and paths are not addressable content —
  nothing navigates into one, selects inside one, or projects one — so they
  carry no `selection` field and need none of `@document`'s document codegen;
  `@cell_struct` gives them the transparent-`Cell` fields alone.
- `..DocumentModule: Document, is_element_collection, is_walk_opaque` — only for
  the reflection-walker traits, not for `@document`.

That is the whole import surface of the layer. No projection, no operation, no
device. This is what keeps the reference layer below the selection and operation
layers.

## Reference steps

Each step descends one level into a document tree. The full vocabulary:

| Step | Selects | Notes |
| --- | --- | --- |
| `FieldReferenceStep("foo")` | the field named `foo` | resolved by `getfield(doc, :foo)`, unwrapping a `Cell` if needed — struct field names are public API |
| `ElementReferenceStep(i)` | the *i*-th element of a sequence | constructor alias for `RangeReferenceStep(i-1, i)`; 1-based (Julia convention) |
| `PositionReferenceStep(k)` | cursor at boundary *k* of a sequence | constructor alias for `RangeReferenceStep(k, k)`; a zero-width cursor, 0-based |
| `RangeReferenceStep(s, e)` | the range `s..e` | the underlying type; `Element`/`Position` are constructor aliases |
| `ProjectionReferenceStep(p, sub)` | a projection-introduced element | kernel `projection/`; see [the opaque-payload pattern](#the-opaque-payload-pattern) below |
| `PointReferenceStep(x, y)` | a pixel coordinate | visual `graphics/`; for graphics/geometry endpoints and hit-testing |
| `TextRangeReferenceStep(s, e)` / `TextColumnReferenceStep` / `TextSpanReferenceStep` | a text selection — stream cursor / column box / bounding box | visual `text/`; text-domain endpoints, same `(start, stop)` payload, the type selects the geometry |

The first four are the kernel's own steps (`ReferenceStep.jl`). The last three are
owned by the packages that need them: each subtypes `ReferenceStep` and registers
its navigation and DSL behaviour through the seams in `ReferenceInterface.jl`, at its own
definition site, with no edit to the reference layer.

`TypeReferenceStep(T)` also exists but is **not** a navigation step in stored
paths — it survives only as an internal build-time token that is immediately
folded into per-node `type` fields (see
[Type checkpoints](#type-checkpoints-and-replay-validity)). A path node's `head`
is therefore always one of the navigation steps above.

All dynamic step fields (`ElementReferenceStep(index::Cell)`,
`FieldReferenceStep(name::Cell)`, `PointReferenceStep(x::Cell, y::Cell)`, …) are held in
reactive `Cell`s, so the same path object can be re-pointed in place.

### The boundary axis

`ElementReferenceStep` and `PositionReferenceStep` are two readings of the *same* axis.
Any sequence — array elements, object entries, child nodes, string characters —
has `n` items and `n+1` boundaries between them:

```
        {0}     {1}     {2}     {3}     {4}
         │   a   │   b   │   c   │   d   │
            [1]     [2]     [3]     [4]
```

- `{i}` is the boundary at offset `i` — a zero-width cursor.
- `[i]` is the item between boundaries `i-1` and `i` — the i-th element (1-based).

Both are encoded as the same underlying `RangeReferenceStep(start, stop)`: `[i]` is
`RangeReferenceStep(i-1, i)` (one-wide), `{i}` is `RangeReferenceStep(i, i)`
(zero-wide).

**The bracket says the numbering**, and a run of items is written either way:

- `{i:j}` — the run between boundary `i` and boundary `j`, 0-based. It is
  `RangeReferenceStep(i, j)`.
- `[i, j]` — the items `i` through `j`, 1-based and inclusive. It is
  `RangeReferenceStep(i-1, j)`, so `[i, i]` is `[i]`.

`{1:3}` and `[2, 3]` are therefore the same step. Write whichever counts what
you are thinking about: an insert counts boundaries, and a selection of items
counts items.

The same convention applies regardless of what the items are. In an array, `[1]`
is the first element and `{0}` is the cursor before it. In a string, `[1]` is
the first character and `{0}` is the cursor before it. In an object, `[1]` is
the first entry and `{0}` is the cursor before it.

### ProjectionReferenceStep

Points to elements introduced by a projection (delimiters, brackets,
separators) that have no counterpart in the underlying document.

```julia
ProjectionReferenceStep(projection,
    ConcreteReference(FieldReferenceStep("open"),
        ConcreteReference(PositionReferenceStep(0))))
```

A mapper never wraps that step by hand. `make_introduced_reference(projection, document,
output_path)` builds the whole path: the node records the type of the input node the
projection printed, and the terminal records `Position`. Both types are needed, because
`@reference` errors on an under-typed path, and an embedder — a pane tab holding a foreign
document — splices whatever a content projection returns into an `@reference` literal.

## Reference paths and their structs

A `Reference` chains steps. It is an **immutable linked list**, so
extending or sharing a path costs no copying — a new prefix reuses the existing
tail:

```julia
abstract type Reference end
struct EmptyReference <: Reference end
struct ConcreteReference <: Reference
    head::Cell   # holds a ReferenceStep
    tail::Cell   # holds the next Reference
    type         # the Julia type this node stands on (a type checkpoint)
end
```

`EmptyReference()` terminates the list at the root/leaf;
`ConcreteReference(step, tail)` is one cons cell. Both fields are `Cell`s so
the path is reactive — a computed cell can depend on a path's content. The list
*shape* is persistent, but because each `@cell_struct`-backed step/path struct is
mutable and stores its dynamic values in reactive `Cell`s, `replace_selection!`
can move a caret by writing those cells in place rather than rebuilding the chain.

**Build paths with the `@reference` macro** (see
[§ Reference DSL](#reference-dsl-reference) below) — it is the canonical, most
capable way to construct a reference:

```julia
@reference items[1].name        # ElementReferenceStep(1) then FieldReferenceStep("name")
@reference()                    # the empty path (the whole element / root)
```

For programmatic construction from a list of steps, `Reference(steps...)`
threads them into a path:

```julia
Reference(ElementReferenceStep(1), FieldReferenceStep("name"))
```

You rarely construct the cons cells by hand; prefer `@reference` or
`Reference`.

### Whole-element selection: the empty path

An **empty path** (`EmptyReference()`, written `@reference()`, matched by
the `∅` pattern) means *the whole element at this level is selected* — there is
no sub-position within it. This is a selection convention in its own right,
not an absence of selection (that is `nothing`).

Because an empty path has no steps to translate, it maps across any projection
**by identity**: the default `map_reference_forward` / `map_reference_backward`
return `@reference()` unchanged for it, so whole-element selections round-trip
through every projection with no extra mapping.

## Resolving and validating a reference

`evaluate_reference(document, path)` is the inverse of building a path: it walks
`path` from `document` and returns the node (or value) it points at — unwrapping
cells, descending fields by `FieldReferenceStep` and elements by
`ElementReferenceStep` / `PositionReferenceStep`. It is the
`(document, reference) → node` function.

```julia
ref  = @reference entries[1].value
node = evaluate_reference(document, ref)   # the JsonString at that path
```

**To find a node by content** (and get a reference to it, or select it) rather
than knowing its path up front, use `search_references` / `search_documents` — see
the [finding-and-selecting guide](finding-and-selecting.md). Do not hand-walk
the document tree to locate a node.

`is_valid_reference` checks that an object is a valid reference step or path:

```julia
is_valid_reference(PositionReferenceStep(5))    # true
is_valid_reference(FieldReferenceStep("name"))  # true
is_valid_reference("not a reference")       # false
is_valid_reference(EmptyReference())    # true
```

For a `ConcreteReference` it recursively validates that the head cell holds
a valid `ReferenceStep` and the tail cell a valid `Reference`, ensuring the
whole chain is well-formed. This one-argument form is a purely *structural*
check. The two-argument, document-aware method is described under
[Type checkpoints](#type-checkpoints-and-replay-validity).

## Type checkpoints and replay validity

A reference is often captured before an edit and replayed against the document
*after* it. If the document's structure changed underneath the stored path
(a `JsonString` swapped for a `JsonNumber`, a node retyped, …), the leftover
steps would silently mis-navigate or throw a bare `getfield` error.

Per-node **type checkpoints** guard against this. The type is **folded into
every path node**: each `ConcreteReference` carries a `type` field recording
the Julia type of the node it stands on (the type its `head` step descends
*from*), and the terminal `EmptyReference` records the type of the node the
path lands on. A node's `head` is therefore **always a navigation step** — there
is no separate interleaved `TypeReferenceStep` *step* and nothing to "skip". The
match rule is `node isa T`.

A `FieldReferenceStep` does not need two checkpoints (a start and an end): a step's
*start* type is its own node's `type`, its *end* type is its `tail` node's
`type`. The boundary type is stored once, on the downstream node, serving both
roles — so a k-step path has k+1 typed nodes (every boundary plus the terminal).

- `evaluate_reference(document, path)` throws `ReferenceTypeMismatchException(expected,
  actual)` when a node's recorded type no longer matches the document reached.
  (`evaluate_reference` is itself the document-aware validator.)
- `get_valid_reference_prefix(document, path)` walks the path and returns the
  **longest prefix that still resolves** — it stops at the first node whose type
  mismatches (or an unfollowable structural step), dropping the invalid
  remainder.
- `is_valid_reference(document, path)` (the two-argument, document-aware method)
  is `true` iff every node type holds along the whole path.

Checkpoints are created programmatically, not by hand:

- `annotate_reference_types(document, path)` returns `path` with each node's
  `type` field filled in against `document` (a `{k}` cursor lands on no child,
  so the terminal after it stays untyped).
- `strip_reference_types(path)` blanks the node types again, recovering the
  plain navigation skeleton. The two are inverses on an unchanged document.
- `fold_reference_types(path)` converts a path that still carries transitional
  `TypeReferenceStep` *steps* (e.g. the ones `@reference ::T` builds, or those the
  generic `ProjectionTemplate` helpers prepend) into the folded node-type form.
  It is applied at construction so no stored or consumed path ever holds a
  checkpoint step.

### A type in a pattern narrows the match

The same `::T` that *records* a type when building a path **selects on** it when
matching one. In `@reference_case` and `@reference_rules` alike, `::T` is
non-navigating — it consumes no step — and it determines the arm:

- where the path **records a node type**, that type must be `<: T`, or the arm
  fails and the next one gets its chance;
- where the path **records none** (`type === nothing`), `::T` says nothing and the
  match proceeds.

So `queue::PacketQueue.capacity` refers to the capacity of every `PacketQueue`,
not to every capacity at a queue-shaped place, and a selector no longer has to
fall back on the lower-case binder plus a guard (`when(queue::t, t <: PacketQueue)`)
to say the same thing three times. It also restores the tripwire the folded model
lost: before the type was folded into node fields, a leading `TypeReferenceStep`
made a cross-domain path fail to match structurally.

The silent case is not a loophole, it is what keeps the rule usable:

- a plain `@reference` skeleton and a `strip_reference_types` result are untyped
  throughout;
- `reroot_reference` prepends its nodes with the two-argument
  `ConcreteReference`, which records no type — so a container routing a gesture
  into a child keeps matching. Deeper in, the child's own nodes *are* typed, and a
  pattern naming the wrong type there is narrowed away on purpose;
- a recorded value that is not a `Type` is tolerated too, since `<:` has no answer
  for it.

Both readings of the grammar call one predicate — `_type_step_matches` in
`ReferenceCase.jl` — so the compiled matcher and the rules interpreter cannot
drift on what a type in a pattern means.

### Where checkpoints live (canonical, folded, everywhere)

Folded node types are the **canonical form references are held in** — at rest
and in projected output alike:

- **Document-domain selections are canonical.** `set_selection!(document, path)`
  fills node types against `document` (it does
  `annotate_reference_types(document, strip_reference_types(path))`), so every
  document's `selection` cell holds the folded form. `search_references`
  likewise annotates its results, so search results are self-describing too.
- **Mappers and structure-creating printers emit the folded form.** Each printer
  that builds output structure types the output path it constructs; the generic
  `ProjectionTemplate` helpers (`_typed`, `_path`, `_prepend`) fold the type
  checkpoints they assemble. Consumers read `head`/`tail` directly — no path
  they see carries an interleaved checkpoint step.

The replay/validation primitives still apply when you hold a reference across an
edit:

```julia
annotated = annotate_reference_types(document, path)   # or just read a selection cell
# … document is edited …
live     = get_valid_reference_prefix(document, annotated)  # truncate at first mismatch
```

> **Implementation note.** `TypeReferenceStep(T)` survives only as an internal
> *build-time token*: the `@reference ::T` DSL and the `ProjectionTemplate`
> helpers emit it, and `fold_reference_types` immediately folds it into node
> `type` fields. It never appears as a step in a stored or consumed path.

## A document together with its reference

`ReferencedDocument{T}` pairs a document with the reference that reached it: the
node, of type `T`, as it was when it was found, and the complete reference to it
from the root it was found from. `T` is the type of whatever the reference
reaches — a document, a collection, or any other value.

It acts like the document it holds. Reading or writing a property, indexing,
iteration, `length`, `isempty`, `keys`, `haskey`, `get`, `values`, `setindex!`,
`push!`, `insert!` and `deleteat!` all go to the document. A write stores the
document of a `ReferencedDocument` it is given, so the tree never holds one. A read
that answers a document or a collection answers a `ReferencedDocument` too, with
the reference extended by the field or the index that reached it; a read that
answers a leaf value — a string, a number, a `Bool`, `nothing` — answers that
value plain, with no reference around it:

```julia
tree = ReferencedDocument(root, EmptyReference())
first_child = tree.children[1]     # a ReferencedDocument at .children[1]
first_child.name                   # a plain string
```

Each step that a read adds records the type of the node it stands on, and the
reference ends on the type of the value, as `annotate_reference_types` records
them, so a function that takes only a fully typed reference takes it. A key that
no step can name, such as the key of a document that acts as a map, is found in
the document by its identity. A value that the document holds at more than one
place is answered plain, because no reference is better than a wrong one.

Read the two parts with `get_document` and `get_reference`; every other property
name goes to the document instead. `ReferencedDocument` is not a subtype of
`Reference` or of `Document`: as a `Reference` it would have to answer every
method written for the two concrete reference structs, in a layer whose
interface is sealed; as a `Document` the generic document machinery — a search, a
printer walk, a copy — would treat it as a node of the tree, which it is not.
Because every property goes to the document, `x isa T` is false for a
`ReferencedDocument` that references a value of type `T`; code that checks a
type asks `get_document(x)` first. `convert` to a document type converts
`get_document(x)` to it, and `convert` to `Reference` converts `get_reference(x)`
to it, so a `ReferencedDocument` fits where either is wanted.

`get_parent(root, x)` answers the document that holds `x`, read from `root` at the
call: one step up the reference of `x`, and past each collection on the way, so
the parent of an element of a vector field is the document that has the field,
not the vector. `x` is a `ReferencedDocument` or a `Reference`; it answers
`nothing` at the root. `root` is the document the reference starts at; the editor
layer adds a method that takes the editor and reads its document at the call.

`DocumentLocator(start, reference)` is the address of a document, not resolved:
`start` is where the reference is read from, and the reference is read from it
only when `find_referenced_document(locator)` is called. The editor layer adds a
method for a locator whose `start` is an editor, which reads the document the
editor holds at that time, so the locator stays right when the editor's document
is replaced. That function
answers a `ReferencedDocument`, or `nothing` when the reference no longer reaches
a node, so a `ReferencedDocument` found before an edit is brought up to date
after it: `find_referenced_document(DocumentLocator(start, get_reference(old)))`
reads the same place again.

`get_edited_document(x)` follows a chain of layers down to the document a person
edits: a tab wraps what it shows, a file wraps the document read from it, a
history wraps the document it keeps. Each such layer answers the name of its own
field through the open generic `get_edited_field`, and `get_edited_document`
reads that field, one layer at a time, for at most 16 layers, so a cycle of
layers cannot make it run forever. Given a `ReferencedDocument` it answers a
`ReferencedDocument` whose reference passes through every layer it crossed;
given a plain document it answers a plain document.

## Input and output references

References are always interpreted relative to a particular document. When a
projection is involved, every reference falls into one of two roles:

- **Input reference** — steps understood starting from the *input* document of a
  projection.
- **Output reference** — steps understood starting from the *output* document of
  a projection.

`map_reference_forward` takes an input reference and returns an output
reference. `map_reference_backward` takes an output reference and returns an
input reference. These are the only two functions that translate between the two
roles, and each projection defines its own rules for how the translation works.

**The forward map takes an input reference and returns an output reference,
independently of what is printed.** A projection answers from its input and its
own mapping, which is usually an index mapping: a container maps its own step to
the step of its child's node in the output, and delegates the rest of the
reference to the child. It gives the same reference whether the printer computed
the part or a lazy printer left it out. In graphics the answer is the reference
of the node that draws the part, not a point. A caller that needs the place of a
part on the screen reads the places of the printed nodes that the output
reference reaches; a reference that reaches no printed node has no place.

### The place of a part

The forward map answers **the most specific output reference** of a part:

- In graphics, the node that draws the part: a widget maps to its canvas, and a
  child of a container to the child's canvas inside the container's canvas.
- A part of a text maps to the text node of the segment that draws it, followed
  by the characters, `text{a:b}`; a caret is a range of no width. A range across
  segments maps to the smallest node that holds all of it, followed by a
  `RegionReferenceStep(x, y, width, height)`: a box in the frame of that node,
  as `PointReferenceStep` is a point there.
- A part that the projection does not display has no image and maps to
  `nothing`, such as the content of a tab that is not open or a node under a
  closed tree node. A part that a lazy printer did not print yet has its
  reference, such as element 40 of a lazy list, whose index counts from the
  head of the list.

**The backward map of a point answers the most specific part that is drawn at
the point.** A projection reads the point in the frame of its own output node,
as a pointer event reaches it: each container takes the place of the child off,
and at the root the window takes off the place of the root canvas. Where
children overlap, the topmost one, the one drawn last, answers. A part that
holds the drawn part, such as a row of a table around its row header, a column,
or a group around a leaf, is not reached by the point: navigation reaches it,
such as Alt and an arrow key. This holds in every domain and across nested
domains.

**How a caller finds the place of a part.** It maps the part forward with the
type of each node on its reference, as the selection does
(`annotate_reference_types`), and reads the box of the node that the answer
reaches in the printed output with `find_reference_box` of the graphics package:
`(x, y, width, height)` in the frame of the output. `visible = true` cuts the
box to what the viewports on the way show, and a box that none shows is
`nothing`. `find_part_place` of the screen package does both from a wrapper at
the screen and answers the bottom left corner of the box, where a window that a
command opens, such as a tooltip with no pointer, stands. The round trip test of
the widget examples, `test_widget_round_trip()`, ties the two maps together:
each displayed part maps forward, and a point where its node draws something
maps back to the part or to a part inside it.

A `ProjectionReferenceStep(P, output_path)` *step* embeds an output reference inside
an input reference, meaning: from this position, jump through projection `P`,
then continue with `output_path` in `P`'s output. This lets an input reference
point at structural elements (delimiters, separators, decorations) that only
exist in the output and have no direct counterpart in the input. Forward mapping
through `P` strips the `proj(P, …)` step; backward mapping through `P`, for an
output reference that has no pre-image in the input, can wrap the unmatched
suffix with a `proj(P, …)` step to round-trip cleanly.

## Reference DSL: `@reference`

The `@reference` macro turns compact source into the nested
`ConcreteReference(…)` you would otherwise write by hand:

```julia
# Field references
@reference address.city
# → FieldReferenceStep("address") then FieldReferenceStep("city")

# Element references (1-based)
@reference items[i]                 # → ElementReferenceStep(i)

# Position references (0-based)
@reference items{i}                 # → PositionReferenceStep(i)

# Range references — a run of items, in either numbering
@reference items{s:e}               # → RangeReferenceStep(s, e)      boundaries, 0-based
@reference items[i, j]              # → RangeReferenceStep(i-1, j)    items, 1-based inclusive

# Dynamic field names
@reference config.field(fname)      # → FieldReferenceStep(fname)

# Point references (2D coordinates)
@reference cursor.point(x, y)       # → PointReferenceStep(x, y)

# Projection references
@reference rendered.proj(projection, {0})
# → ProjectionReferenceStep(projection, the one-step path PositionReferenceStep(0))

# Complex paths
@reference items[1].name            # → ElementReferenceStep(1) then FieldReferenceStep("name")

# Path-tail splice
@reference value.^(tail)
# Concatenates the spliced Reference (or single ReferenceStep) onto the
# prefix; useful for rebuilding paths like
#   ConcreteReference(FieldReferenceStep("value"), tail)
# in projection mappers.

# Splice at the front
@reference ^(base).inner            # → _concat(base, @reference inner)

# Splice with a single step
let s = FieldReferenceStep("foo")
    @reference value.^(s)           # → FieldReferenceStep("value") then FieldReferenceStep("foo")
end
```

The `^()` operator accepts either a `Reference` (concatenated) or a
`ReferenceStep` (wrapped into a one-step path then concatenated). It can appear
at the front of a chain (`^(base).rest`) or at the tail (`prefix.^(tail)`).
Mid-chain splices are not supported because the surrounding Julia surface syntax
does not parse `prefix.^(x).suffix` the way the DSL would need.

### Building single steps: `@reference_step`

The `@reference_step` macro builds a single `ReferenceStep`, useful for passing to
`extend_reference` or any API that takes raw steps instead of full paths.

```julia
@reference_step value              # FieldReferenceStep("value")
@reference_step xs[i]              # ElementReferenceStep(i)
@reference_step xs{k}              # PositionReferenceStep(k)
@reference_step xs{s:e}            # RangeReferenceStep(s, e)
@reference_step xs[i, j]           # RangeReferenceStep(i-1, j)
@reference_step c.point(x, y)      # PointReferenceStep(x, y)
@reference_step config.field(name) # FieldReferenceStep(name)
```

The leading identifier (`xs`, `c`, `config`) is a placeholder — only the
trailing operator determines the step's kind. For a bare symbol like
`@reference_step value`, the symbol itself becomes the field name.

## Reference pattern matching: `@reference_case`

The `@reference_case` macro matches a path against `pattern => result` rules (à
la Julia's `match`), binding the variable parts (indices, field names, tails)
for the result expression:

```julia
@reference_case reference begin
    value{k}            => @reference value{k}   # cursor position (0-based)
    items{s:e}          => ("range", s, e)       # matches any RangeReferenceStep, binds boundaries
    items[i]            => ("item at", i)         # element access (1-based)
    items[1]            => "first item"           # literal element
    when(items[i], i>0) => ("later item", i)      # guarded pattern
    _                   => "default"              # wildcard
end
```

Pattern syntax:
- `_` — wildcard, matches anything
- `∅` — the **empty path** (`EmptyReference`), i.e. a *whole-element*
  selection
- `i` — binder, captures the value
- `"name"` or `0` — literal, matches a specific value
- `i::Int` — typed binder, captures with a type check
- `path...` — matches prefix and binds the remaining tail
- `{s:e}` — range pattern, matches any `RangeReferenceStep` and binds its two
  boundaries (positions are `RangeReferenceStep(k, k)`, so `{s:e}` will also
  match a position; list more specific `{k}` patterns first if both are
  interesting)
- `[i, j]` — the same match, binding the items instead: `i` is the 1-based first
  item and `j` the 1-based last

The `when(pattern, cond)` helper adds a guard.

### Where the input sits: the arm vocabulary

A bare pattern `P` matches a path that **is** `P`. The four other arm words say
where the input sits relative to `P` instead, and they are the same five words
[`@reference_rules`](#rules-kept-as-an-object-reference_rules) uses — one
vocabulary, two DSLs:

| arm | holds when | for `a.b.c`, answers for |
| --- | --- | --- |
| `P` / `at(P)` | the input **is** `P` | `a.b.c` |
| `below(P)` | the input is strictly deeper | `a.b.c.d`, `a.b.c.d.e` |
| `within(P)` | `P` or deeper | `a.b.c`, `a.b.c.d` |
| `above(P)` | the input is strictly shallower — it runs out *inside* `P` | `a`, `a.b` |
| `toward(P)` | `P` or shallower | `a`, `a.b`, `a.b.c` |

`above(…)` answers whether the selection is an ancestor of this place
(see `ReferenceDispatchingProjection`); `within(…)` answers the other direction:
whether this pattern names a leading segment of the input.

> There is no `prefix(…)`. It named `above(…)` while reading as though it meant
> `within(…)`, which is exactly the confusion the five words exist to remove.
> Writing it is an error that says which one to pick.

`@reference_case` is commonly used
in projection readers to translate output-domain references back to input-domain
references — for example, mapping the empty path by identity:

```julia
function map_reference_forward(::SomeProjection, iomap, reference)
    @reference_case reference begin
        ∅           => @reference()        # whole element — identity
        value{k}    => @reference value{k}
    end
end
```

### The DSLs are surface-syntax siblings

`@reference` (construction), `@reference_case` (destructuring) and
`@reference_rules` (destructuring, kept as a value) operate on the same reference
vocabulary. Domain code that both constructs and matches references (every non-trivial
`read_intent`) benefits from having them side by side — a change to one DSL's syntax is
a change to its siblings' grammar.

## Rules kept as an object: `@reference_rules`

`@reference_case` applies at the point it is written and its arms are compiled away. A
**configuration** is the same block of arms written *before* the thing it configures
exists: a set of rules held as data, applied whenever a reference turns up. That is
`@reference_rules`, which answers a `ReferenceRules` value — storable, comparable,
printable and applied with `apply_reference_rules`:

```julia
rules = @reference_rules begin
    buckets[2].capacity => 20
    buckets[i].capacity => 10 * i          # i is bound by the match
end

apply_reference_rules(rules, reference)    # what @reference_case would answer
```

That last comment is the contract, and the conformance corpus in
`ReferenceRulesTest.jl` is what holds it: the same block written both ways must answer
identically. **First match wins** and no match answers `nothing`, so concatenating two
sets makes the first one win, and prepending is the whole override mechanism.

### The arm vocabulary

The five arm words are [the ones `@reference_case` uses](#where-the-input-sits-the-arm-vocabulary)
— one vocabulary, two DSLs. What a rules object adds is the *leftover* each form
hands to a delegating answer:

| arm | holds when | leftover |
| --- | --- | --- |
| `P` / `at(P)` | the input **is** `P` | `∅` |
| `below(P)` | the input is strictly deeper | the leftover |
| `within(P)` | `P` or deeper | the leftover, possibly `∅` |
| `above(P)` | the input is strictly shallower | `∅` |
| `toward(P)` | `P` or shallower | `∅` |

### Delegation: an answer that is rules

An answer that is a rule set receives the **leftover** the arm computed, with the
bindings so far still in scope. That is what lets a set written about one place be
applied at several places:

```julia
node = @reference_rules begin
    queue.capacity => 100
    serviceRate    => 10.0
end

@reference_rules begin
    within(hosts[_]::WirelessHost) => ^(node)     # by kind, not by place
    linkDelay                           => ^(10ms)
end
```

Applied to `hosts[3].queue.capacity`, the first arm consumes `hosts[3]` and applies `node`
to `queue.capacity`. Which leftover an arm produces is read off the arm, never off
the answer, so an arm means the same thing whatever it answers.

### The object is closed

A pattern holds no expressions: every `^(…)`, every `::T` and every typed binder's type
is evaluated at the construction site and the **value** stored. An answer is an
expression, evaluated against what its own pattern bound and what the arms above it
bound — and nothing else, because it is compiled in `ReferenceModule`, where a free name
resolves rather than at the site the rules were written.

`^(…)` is the one channel from that site, and it means the same thing on both sides of
`=>`: on the left it interpolates a value to compare against, on the right it evaluates
at construction and splices the value in. A unit, a domain constructor, a local, a
nested rule set — all travel that way (`=> ^(@reference_rules begin … end)`).

The identity of an answer is its expression: that is what `==` compares, what `show`
prints, and what a serializer writes. The compiled form is a method in
`ReferenceModule`'s table under a key derived from the expression, so nothing compiled
travels with the object — a rule set written by one process is read and applied by
another, which is the point of holding a configuration as data.

### Extension steps need the interpreted seam

A `.name(…)` step in a rules pattern is matched through
`match_reference_step_value(::Val{name}, step, argpats, bindings, match_value,
match_path)`, the interpreted sibling of `@reference_case`'s codegen
`match_reference_step` (an interpreter cannot use a codegen seam). A step type that
wants to appear in a rules pattern registers both, in the package that owns it; the
seam's error names exactly what is missing.

## Mapping between document structs and reference steps

Reference paths mirror the struct field layout of documents. Every `.` in a
printed path corresponds to a `FieldReferenceStep`; every `[i]` corresponds to an
`ElementReferenceStep`; every `{i}` corresponds to a `PositionReferenceStep`. The core
rules used by `set_selection!`, `clear_selection!`, and `evaluate_reference`
are:

| Reference step | Navigation action |
|---|---|
| `FieldReferenceStep("f")` | `getfield(document, :f)` — unwrap Cell if needed |
| `ElementReferenceStep(i)` | `document[i]` — the i-th item (1-based); element in a collection or character in a string |
| `PositionReferenceStep(i)` | cursor at boundary `i` (0-based); between elements in a collection or between characters in a string |

### CellVector (used by arrays, objects, and other containers)

`CellVector` has `elements::Cell` (holding a `Vector{Cell}`) and
`selection::Cell`. As a sequence it supports both readings of the boundary axis:

| Step | Target |
|---|---|
| `ElementReferenceStep(i)` | `elements[i]` — the i-th element (1-based) |
| `PositionReferenceStep(i)` | cursor between elements (0-based); useful as an insertion point |

### JSON domain

| Document type | Field | Reference step | Reaches |
|---|---|---|---|
| **JsonObject** | `entries` | `FieldReferenceStep("entries")` | the CellVector of entries |
| **JsonArray** | `elements` | `FieldReferenceStep("elements")` | the CellVector of elements |
| **JsonObjectEntry** | `value` | `FieldReferenceStep("value")` | the value document (Cell) |
| **JsonObjectEntry** | `key` | `FieldReferenceStep("key")` | the key string |
| **JsonString** | `value` | `FieldReferenceStep("value")` | the String cell |
| **JsonNumber** | `value` | `FieldReferenceStep("value")` | the Number cell |
| **JsonBool** | `value` | `FieldReferenceStep("value")` | the Bool cell |
| *any CellVector or String* | `[i]` | `ElementReferenceStep(i)` | the i-th item (1-based) — element or character |
| *any CellVector or String* | `{k}` | `PositionReferenceStep(k)` | cursor at boundary `k` (0-based) — between elements or characters |

**Full path example** — character 3 of `"Alice"` in `{"name": "Alice"}`:

```
@reference entries[1].value.value{3}
           ───────     FieldReferenceStep("entries")
                  ───  ElementReferenceStep(1)       → JsonObjectEntry
                       ─────                         FieldReferenceStep("value")  → JsonString
                             ─────                   FieldReferenceStep("value")  → String cell
                                  ───                PositionReferenceStep(3)     → char offset
```

### XML domain

| Document type | Field | Reference step | Reaches |
|---|---|---|---|
| **XmlElement** | `attrs` | `FieldReferenceStep("attrs")` | CellVector of XmlAttribute |
| **XmlElement** | `children` | `FieldReferenceStep("children")` | CellVector of child nodes |
| **XmlText** | `content` | `FieldReferenceStep("content")` | the String cell |
| **XmlAttribute** | `value` | `FieldReferenceStep("value")` | the attribute value cell |
| *any CellVector or String* | `[i]` | `ElementReferenceStep(i)` | the i-th item (1-based) — element or character |
| *any CellVector or String* | `{k}` | `PositionReferenceStep(k)` | cursor at boundary `k` (0-based) — between elements or characters |

### Book domain

| Document type | Field | Reference step | Reaches |
|---|---|---|---|
| **BookBook** | `elements` | `FieldReferenceStep("elements")` | CellVector of chapters |
| **BookChapter** | `elements` | `FieldReferenceStep("elements")` | CellVector of children |
| **BookList** | `elements` | `FieldReferenceStep("elements")` | CellVector of items |
| **BookParagraph** | `content` | `FieldReferenceStep("content")` | the text content |
| **BookPicture** | `content` | `FieldReferenceStep("content")` | the image content |

### FileSystem domain

| Document type | Field | Reference step | Reaches |
|---|---|---|---|
| **FileSystemDirectory** | `elements` | `FieldReferenceStep("elements")` | CellVector of children |

### Selection-path forms by domain

The tables above list the fields; the forms below name the common *cursor* path
shapes those fields produce as a selection (`[i]` is the i-th item, 1-based;
`{k}` is the cursor at boundary `k`, 0-based).

| Domain | Path form | Meaning |
|---|---|---|
| `Text` | `{k}` | cursor at offset `k` in the flat span sequence |
| `SyntaxLeaf` | `.value + {k}` | cursor at offset `k` in the value span |
| `SyntaxLeaf` | `.open + {k}` / `.close + {k}` | cursor in the opening / closing delimiter |
| `SyntaxNode` | `[i] + <child path>` | into child `i` |
| `SyntaxNode` | `.open + {k}` / `.close + {k}` | cursor in delimiter span |
| `SyntaxNode` | `ProjectionReferenceStep(p, {k})` | projection-introduced whitespace |
| `JsonString` | `.value + {k}` | cursor in the string value |
| `JsonString` | `ProjectionReferenceStep(p, .open + {k})` | cursor on `"` opening quote |
| `JsonString` | `ProjectionReferenceStep(p, .close + {k})` | cursor on `"` closing quote |
| `JsonArray` | `[i] + <element path>` | into element `i` |
| `JsonObject` | `[i] + .value + <value path>` | into the value of entry `i` |
| `JsonObject` | `[i] + .key + {k}` | cursor in the key string of entry `i` |

### General pattern

The pattern is consistent across all domains:

1. **Struct fields** → `FieldReferenceStep("field_name")` — descend into a named
   field; if the field is a `Cell`, it is automatically unwrapped.
2. **i-th item** → `ElementReferenceStep(i)` — descend into the i-th item of a
   sequence (1-based); same step whether the sequence holds elements (CellVector,
   JsonArray, …) or characters (String).
3. **Boundary between items** → `PositionReferenceStep(k)` — cursor at the k-th
   boundary of a sequence (0-based); same step whether between elements
   (insertion point) or between characters (text cursor).

A reference path is always a chain of these step types (plus `ProjectionReferenceStep`
for projection-introduced elements like delimiters and brackets).

## Finding references: `search_references`

To find every path to a matching node, use `search_references(document, query)`
— it takes a predicate, a substring `String`, or a `Regex`, and returns a
`Vector{Reference}` whose results are annotated with type checkpoints (so
they are self-describing and replay-safe):

```julia
for ref in search_references(editor.document, "John")   # or r"TODO", or a predicate
    value = evaluate_reference(document, ref)
    println("Found at $ref: $value")
end
```

`search_references` lives in the **reference layer**: it *produces* reference
paths, so it belongs with the machinery that expresses them. Its object-valued
sibling `search_documents` (below) needs no reference machinery, so it lives one
layer down in the **document layer** — the two walks are structurally parallel
and kept in sync. Both stay free of higher-layer types through two Holy traits
they dispatch on but do not own, each a document-layer default: `is_element_collection`
(`CellVector` opts in, so a positional collection emits `[i]` element paths) and
`is_walk_opaque` (the agent layer's `Llm` opts in, so the walk never descends into
assistant configuration). Higher layers register their document types by adding
methods, never by the walker naming them. See the
[finding-and-selecting guide](finding-and-selecting.md).

To collect the matching **document nodes** themselves (each once) rather than their
paths, use `search_documents(document, query)` — same predicate/`String`/`Regex`
query, returning a `Vector` of the matched document nodes (scalar leaf matches are
folded up to their enclosing `Document`; pass `raw=true` to return the exact matched value).

## The opaque-payload pattern

`ProjectionReferenceStep` stores its projection as an **untyped `Any` payload**: the
reference layer defines only the step's shape and never imports `Projection`.
Only higher layers (the projection layer) construct and interpret the payload.
So the only edge between projection and reference is `projection → reference`
(for `PrinterContext`, reference mapping, and similar), and it points down. This
is the same pattern `Intent` uses (the reader's backward-flowing type), and it
is the kernel's answer to cases that look like they need a cycle: mention the
higher type opaquely, never call into it. `projection/ProjectionReferenceStep.jl`
documents this at the type declaration.

## Testing

`test/kernel/reference/` holds `ReferenceBuilderTest.jl` (the `@reference` /
`@reference_step` / `@reference_case` DSLs, against `ProjecturedKernel.ReferenceModule`
directly — no umbrella needed) and `ReferenceEvalTest.jl`, which walks `evaluate_reference`
over a test-local `@document struct EvaluationBranch`. No concrete engine document is imported;
the reference DSLs stand on their own.

`ReferenceRulesTest.jl` is mostly one **conformance corpus**: every construct of the
pattern grammar written twice — once as a `@reference_case` block, once as a
`ReferenceRules` object — applied to one corpus of paths and asserted to answer
identically. Two matchers implementing one semantics is the standing risk this feature
carries, and that corpus is what keeps them from drifting; extend it whenever either
matcher learns something new.

## Why references matter

References enable cursor navigation across domain transformations, selection
preservation through projections, bidirectional mapping between input and output
domains, and reactive updates when document structure changes. The projection
system translates references between domains, allowing the cursor to be
positioned on elements that may not exist in the underlying document (like
delimiters). How that stored selection is propagated and forward-projected is
the subject of the [selection guide](selection.md).
