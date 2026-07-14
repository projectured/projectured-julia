# Syntax Domain

<img width="586" alt="Syntax example" src="../../../asset/image/example/syntax.png">

The syntax domain provides a generic intermediate representation between semantic domains (JSON, XML) and text. It represents structured data as a tree of nodes with delimiters.

**Indexing conventions**: paths use `[i]` for the i-th item (1-based) and `{k}` for the cursor at boundary `k` (0-based). The two are readings of the same axis — see [the boundary axis](../../../package/kernel/doc/reference.md#the-boundary-axis). In Syntax the axis appears as child nodes *and* as characters within delimiters or leaf values; the same `[i]` / `{k}` syntax addresses both.

## Types

- **SyntaxLeaf**: Represents a primitive value with open, value, and close delimiters
- **SyntaxNode**: Represents a compound structure with children and delimiters

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

Both `SyntaxLeaf` and `SyntaxNode` carry:

- `indentation::Int` — the nesting depth used for pretty-printing (set by the upstream projection; consumers typically leave this at `0`)
- `collapsed::Bool` — when `true`, the node is rendered on a single line; children or value are not expanded

```julia
node.collapsed = true    # collapse this node to one line
node.indentation = 2     # override indentation depth
```

## Key Features

- Generic representation for multiple domains
- Delimiters are first-class for cursor positioning
- Supports indentation for pretty-printing
- Selection mechanism works on delimiters and content

## Gesture mapping (`read_gesture`)

The syntax tree's keyboard navigation is entirely geometry-free — it walks the
`SyntaxNode` tree and its selection paths — so it lives on the document:
`read_gesture(::SyntaxNode, gesture)` ([syntax/Syntax.jl](../../../package/visual/main/syntax/Syntax.jl))
maps an input gesture to a `ReplaceSelectionOperation` on the tree:

- `Ctrl+Alt+Home` → select the root node (`∅`)
- `Ctrl+Space` → toggle structural ⇄ text (character-cursor) selection
- `Up` / `Down` / `Left` / `Right` → step the whole-element selection
  (parent / first child / previous / next sibling); arrows require `Alt` only to
  *enter* structural mode from a character cursor

`SyntaxCompoundToText` delegates to this and keeps only the geometry/output-driven
mouse hit-testing (collapse glyph, Alt+click). See
[projection-system.md](../../../package/kernel/doc/projection-system.md) for the full reader split.
