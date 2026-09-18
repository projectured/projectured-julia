# Syntax Domain

> **Kind:** reference · **Status:** current · **Stands on:** [system-anatomy.md](../../design/system-anatomy.md)

<img width="586" alt="Syntax example" src="../../../asset/image/example/syntax.png">

The syntax domain provides a generic intermediate representation between semantic domains (JSON, XML) and text. It represents structured data as a tree of nodes with delimiters.

**Indexing conventions**: paths use `[i]` for the i-th item (1-based) and `{k}` for the cursor at boundary `k` (0-based). The two are readings of the same axis — see [the boundary axis](../kernel/reference.md#the-boundary-axis). In Syntax the axis appears as child nodes *and* as characters within delimiters or leaf values; the same `[i]` / `{k}` syntax addresses both.

## Types

`SyntaxDocument` is the abstract root. `SyntaxLeaf` (a primitive value with
optional open/close delimiters) is the only leaf type; every other type is a
`SyntaxCompound` — an interior node, declared in
[SyntaxDocument.jl](../../../source/syntax/SyntaxDocument.jl):

| Type | Kind | Holds |
|---|---|---|
| `SyntaxNode` | `SyntaxSequence` | `children` (`CellVector`), plus `open`/`close`/`sep` delimiters, `indentation`, `collapsed` |
| `SyntaxConcatenation` | `SyntaxSequence` | `children` only — no delimiters, no separator, no indentation, no collapse |
| `SyntaxSeparation` | `SyntaxSequence` | `children` and a `separator` between each pair — nothing else |
| `SyntaxDelimitation` | `SyntaxWrapper` | one `content`, plus `opening_delimiter`/`closing_delimiter` |
| `SyntaxIndentation` | `SyntaxWrapper` | one `content`, plus an `indentation` level |
| `SyntaxCollapsible` | `SyntaxWrapper` | one `content`, plus a `collapsed` flag |
| `SyntaxNavigation` | `SyntaxWrapper` | one `content`; marks a caret landing point, no fields of its own |
| `SyntaxInsertion` | (leaf-shaped) | the domain-neutral insertion-kit placeholder |

A `SyntaxSequence` addresses any number of children as `.children[i]`; a
`SyntaxWrapper` addresses its exactly-one child as `.content`. Every function
that walks the tree — navigation, collapse resolution, printing — is written
against `SyntaxCompound`, not against `SyntaxNode`, so a wrapper is a real
level of the tree and not a special case: a domain adds delimiters,
indentation, a fold state, or a navigation marker to *any* document by
wrapping it, without `SyntaxNode`'s five combined fields.

`SyntaxNode` and `SyntaxSeparation` are what a domain reaches for the same
node with only some of those five: `SyntaxConcatenation` when it needs none
of them (a pure sequence), `SyntaxSeparation` when it needs only a separator.
Both render the same as a `SyntaxNode` with the other fields left `nothing` —
the distinction is precision: a type that can only sequence cannot later
acquire a delimiter by accident.

The **compound contract** — what a compound answers about itself, independent
of which type it is — is five generic functions, each with a default of
`nothing`/`0`/`false`:

| Function | Answers |
|---|---|
| `get_opening_delimiter(compound)` / `get_closing_delimiter(compound)` | `field => span`, or `nothing` |
| `get_separator(compound)` | `field => span`, or `nothing` |
| `get_indentation(compound)` | the pretty-print indentation, `0` if it does not indent |
| `is_syntax_collapsed(compound)` | whether it is currently collapsed |
| `is_syntax_collapsible(compound)` | whether it *can* collapse at all — only such a compound gets a fold marker |

`SyntaxLeaf` and `SyntaxNode` answer all the delimiter/indentation/collapse
ones directly, from their own fields of the same shape; a `SyntaxDelimitation`/
`SyntaxIndentation`/`SyntaxCollapsible` wrapper answers only the one function
its name says. Code that reads `node.indentation`/`node.collapsed` directly
works for the two combined types but not for a wrapper stack — read through
the contract functions instead of the field when the input might be any
`SyntaxCompound`.

## Examples

```julia
# Create a syntax leaf (e.g., for a JSON string)
leaf = SyntaxLeaf(
    TextString("\""),           # open delimiter
    TextString("\""),           # close delimiter
    TextString("hello")         # value
)

# Create a syntax node (e.g., for a JSON array)
node = SyntaxNode(
    TextString("["),            # open delimiter
    TextString("]"),            # close delimiter
    TextString(", "),           # separator
    [child1, child2];           # children (Vector{<:SyntaxDocument})
    indentation = 0             # indentation depth (Int keyword, default 0)
)
```

## Selection

Selection paths can reference:
- Delimiters: `.open[i]` / `.open{k}`, `.close[i]` / `.close{k}` — i-th character or cursor between characters (on both `SyntaxLeaf` and `SyntaxNode`)
- Separator: `.sep[i]` / `.sep{k}` — **`SyntaxNode` only** (`SyntaxLeaf` has no `sep` field)
- Children: `.children[i]` for the i-th child, `.children{k}` for the cursor between children (`SyntaxNode`)
- Leaf values: `.value[i]` for the i-th character, `.value{k}` for the cursor between characters (`SyntaxLeaf`)

## TextString

Each delimiter or value is a `TextString` containing:
- Text content
- Font style
- Font color
- Background fill

## Collapsed and indentation fields

`SyntaxLeaf` and `SyntaxNode` both carry `indentation::Int` (pretty-print
nesting depth, set by the upstream projection; consumers typically leave it
at `0`) and `collapsed::Bool` (when `true`, the node renders on one line;
children or value are not expanded) as plain fields. A `SyntaxCollapsible` /
`SyntaxIndentation` wrapper carries the same state for any other compound —
read it through the [compound contract](#types) (`is_syntax_collapsed`,
`get_indentation`), not the field, when the input might be either shape:

```julia
node.collapsed = true    # collapse this node to one line (SyntaxLeaf/SyntaxNode)
node.indentation = 2     # override indentation depth (SyntaxLeaf/SyntaxNode)
```

## One field of one object

`ObjectFieldToSyntax` projects an `ObjectField` — one field of one object — to
the field node `ObjectNodeToSyntaxNode` builds inline for each field of a struct:
the name leaf, then the projected value.

```julia
ObjectField(server, "name")      →   name "gateway"
ObjectField(server, "capacity")  →   capacity 4
ObjectField(server, "enabled")   →   enabled true
```

The name comes from the last `FieldReferenceStep` of the path. A step that names
no field — an element step, for example — leaves the value alone, because an
index makes a poor label and the caller can put one beside it.

Put its entry in front of `ObjectToSyntax`'s own table. Without it the `Any` row
dispatches to `ObjectNodeToSyntaxNode`, which dumps the whole object and its
reference path:

```julia
RecursiveProjection(TypeDispatchingProjection(vcat(
    Pair{Type,Any}[ObjectField => ObjectFieldToSyntax()],
    ObjectToSyntax().dispatch)))
```

`ObjectNodeToSyntaxNode` keeps its private version. It projects each field's
**`Cell`** through `CellToSyntax`, which is how a field repaints when its cell is
written. An `ObjectField` names a value reached by `evaluate_reference` and has no
cell to hand on, so the two are reactive by different means.

## Key Features

- Generic representation for multiple domains
- Delimiters are valid cursor positions, not decoration
- Supports indentation for pretty-printing
- Selection mechanism works on delimiters and content

## Gesture mapping (`read_gesture`)

The syntax tree's keyboard navigation is entirely geometry-free — it walks the
compound tree and its selection paths, with no reference to pixels — so it
lives on the document as a reified gesture table:
`@gestures SyntaxCompound begin … end`
([SyntaxDocument.jl](../../../source/syntax/SyntaxDocument.jl)) maps an input
gesture to a `ReplaceSelectionOperation` on the tree. It is registered on
`SyntaxCompound`, the abstract supertype every interior node shares — not on
`SyntaxNode` — so every wrapper type gets tree navigation for free, with no
table of its own. A separate `@gestures SyntaxLeaf begin … end` table covers
the character-cursor rules a leaf needs instead. The generic `read_gesture`
interpreter fires whichever table matches the node's type, so this is also
exactly the table the gesture-help overlay enumerates.

- `Ctrl+Alt+Home` → select the root node (`∅`)
- `Ctrl+Space` → toggle structural ⇄ text (character-cursor) selection
- `Alt` + arrow → tree-navigate from any selection (enters structural mode)
- a plain arrow → tree-navigate, but only once a whole element is selected
  (parent / first child / previous / next sibling)

`SyntaxCompoundToText` delegates to this and keeps only the geometry/output-driven
mouse hit-testing (collapse glyph, Alt+click). See
[projection-system.md](../kernel/projection-system.md) for the full reader split.
