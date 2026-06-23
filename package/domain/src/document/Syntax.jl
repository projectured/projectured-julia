"""
    SyntaxModule

The syntax tree domain provides a generic intermediate representation between
any structured document and flat text. Nodes carry open/close delimiters and
a separator; leaves carry open/value/close spans. This layer decouples the
layout engine from any specific source domain so the same word-wrap and
indentation logic applies to JSON, XML, or any future domain.

The domain includes:
- **Core types**: `SyntaxLeaf` (leaf with delimiters and value), `SyntaxNode` (compound with delimiters and children)
- **Wrapper types**: `SyntaxDelimitation`, `SyntaxIndentation`, `SyntaxCollapsible`, `SyntaxNavigation` (intermediate document wrappers)
- **Container types**: `SyntaxConcatenation`, `SyntaxSeparation` (for combining documents)
- **Base type**: `SyntaxDocument` abstract type for all syntax documents

Selection semantics (`[i]` = 1-based item, `{k}` = 0-based cursor):
- Leaves: `.open{k}`, `.value{k}`, `.close{k}` — cursor at boundary k in a delimiter or the value
- Nodes: `.open{k}`, `.close{k}` for delimiters, `.children[i]` for the i-th child
"""
module SyntaxModule

import ..ReactiveModule: Cell, setfn!, setval!
import ..DocumentModule: Document, @document
import ..CollectionModule: CellVector
import ..TextModule: TextString
import ..ReferenceModule: Reference, ConcreteReferencePath, EmptyReferencePath,
                          FieldReference, RangeReference, ReferencePath, skip_type_checkpoints
import ..ReferenceBuilderModule: var"@reference"
import ..DocumentApiModule: document_read
import ..OperationModule: ReplaceSelectionOperation
import ..KeyboardModule: KeyDown
import ..EventCaseModule: var"@event_case"
import ..FontModule: font_ubuntu_monospace_regular_24
import ..ColorModule: color_default
export SyntaxNode, SyntaxLeaf, SyntaxDocument, SyntaxInsertion, render, setfn!,
       SyntaxDelimitation, SyntaxIndentation, SyntaxCollapsible,
       SyntaxNavigation, SyntaxConcatenation, SyntaxSeparation,
       ISyntaxNode, ISyntaxLeaf, ISyntaxInsertion, ISyntaxDelimitation, ISyntaxIndentation,
       ISyntaxCollapsible, ISyntaxNavigation, ISyntaxConcatenation, ISyntaxSeparation

"""
    SyntaxDocument

Abstract base type for all syntax document types. Every concrete syntax type
subtypes `SyntaxDocument` and must have a `selection::Reference` field as required
by the `Document` contract.
"""
abstract type SyntaxDocument <: Document end

# ── SyntaxInsertion ───────────────────────────────────────────────────────

@document struct SyntaxInsertion <: SyntaxDocument
    value::Any = nothing
    selection::Reference = nothing
end

# ── Intermediate document types ──────────────────────────────────────────

"""
    SyntaxDelimitation

Wraps a document with opening and closing delimiters. Used to add
bracket-style delimiters to any document type.

# Fields

- `content` — the wrapped document
- `opening_delimiter::TextString` — the opening delimiter text
- `closing_delimiter::TextString` — the closing delimiter text
- `selection::Reference` — a `ReferencePath` or `nothing` (stored in a Cell)

# Constructor

- `SyntaxDelimitation(content; opening_delimiter=TextString(""), closing_delimiter=TextString(""))`
"""
@document struct SyntaxDelimitation <: SyntaxDocument
    content
    opening_delimiter::TextString
    closing_delimiter::TextString
    selection::Reference
end

SyntaxDelimitation(content; opening_delimiter=TextString(""), closing_delimiter=TextString("")) =
    SyntaxDelimitation(content, opening_delimiter, closing_delimiter, nothing)

"""
    SyntaxIndentation

Wraps a document with a specific indentation level. Used to control
pretty-printing indentation for structured documents.

# Fields

- `content` — the wrapped document
- `indentation::Int` — the indentation level (number of spaces/tabs)
- `selection::Reference` — a `ReferencePath` or `nothing` (stored in a Cell)

# Constructor

- `SyntaxIndentation(content; indentation::Int=0)`
"""
@document struct SyntaxIndentation <: SyntaxDocument
    content
    indentation::Int
    selection::Reference
end

SyntaxIndentation(content; indentation::Int=0) =
    SyntaxIndentation(content, indentation, nothing)

"""
    SyntaxCollapsible

Wraps a document with a collapsible state. Used to allow the UI to
collapse/expand portions of the document tree.

# Fields

- `content` — the wrapped document
- `collapsed::Cell` — holds `Bool` indicating if collapsed
- `selection::Reference` — a `ReferencePath` or `nothing` (stored in a Cell)

# Constructor

- `SyntaxCollapsible(content; collapsed::Bool=false)`
"""
@document struct SyntaxCollapsible <: SyntaxDocument
    content
    collapsed::Bool
    selection::Reference
end

SyntaxCollapsible(content; collapsed::Bool=false) =
    SyntaxCollapsible(content, collapsed, nothing)

"""
    SyntaxNavigation

Wraps a document to mark it as a navigation point. Used to indicate
that the cursor should be positioned at this location.

# Fields

- `content` — the wrapped document
- `selection::Reference` — a `ReferencePath` or `nothing` (stored in a Cell)

# Constructor

- `SyntaxNavigation(content)`
"""
@document struct SyntaxNavigation <: SyntaxDocument
    content
    selection::Reference
end

SyntaxNavigation(content) = SyntaxNavigation(content, nothing)

"""
    SyntaxConcatenation

Concatenates multiple syntax documents without separators. Used to
join documents end-to-end.

# Fields

- `children::CellVector` — holds the child `SyntaxDocument` nodes
- `selection::Reference` — a `ReferencePath` or `nothing` (stored in a Cell)

# Constructors

- `SyntaxConcatenation(children::Vector{<:SyntaxDocument})`
- `SyntaxConcatenation()` — empty concatenation
"""
@document struct SyntaxConcatenation <: SyntaxDocument
    children::CellVector
    selection::Reference
end

SyntaxConcatenation(children::Vector{<:SyntaxDocument}) =
    SyntaxConcatenation(CellVector(Cell[Cell(c) for c in children]), nothing)

SyntaxConcatenation() = SyntaxConcatenation(CellVector(), nothing)

"""
    SyntaxSeparation

Concatenates multiple syntax documents with a separator between each.
Used to join documents with a specific separator string.

# Fields

- `children::CellVector` — holds the child `SyntaxDocument` nodes
- `separator::TextString` — the separator text string
- `selection::Reference` — a `ReferencePath` or `nothing` (stored in a Cell)

# Constructors

- `SyntaxSeparation(children::Vector{<:SyntaxDocument}, separator::TextString)`
- `SyntaxSeparation(separator::TextString)` — empty separation with separator
"""
@document struct SyntaxSeparation <: SyntaxDocument
    children::CellVector
    separator::TextString
    selection::Reference
end

SyntaxSeparation(children::Vector{<:SyntaxDocument}, separator::TextString) =
    SyntaxSeparation(CellVector(Cell[Cell(c) for c in children]), separator, nothing)

SyntaxSeparation(separator::TextString) =
    SyntaxSeparation(CellVector(), separator, nothing)

# ── Constructor helpers ────────────────────────────────────────────────────
#
# Shared by the `SyntaxLeaf`/`SyntaxNode` keyword constructors below.

# Auto-wrap a bare string delimiter so callers can write `open="<"` etc.
_text(t::TextString) = t
_text(s::AbstractString) = TextString(s)

# Normalize the `children` argument of `SyntaxNode` to the `CellVector` the inner
# constructor stores. A `@projection_template` marker (e.g. `collection(:field)`)
# or any other object is passed through untouched, for the `@document` inner ctor
# to wrap in a `Cell` (the same shape the positional 7-arg form produces).
_children(c::CellVector) = c
_children(c::Vector{Cell}) = CellVector(c)
_children(c::AbstractVector) = CellVector(Cell[Cell(x) for x in c])
_children(f::Function) = CellVector(f)
_children(c) = c

# ── Leaf ─────────────────────────────────────────────────────────────────

"""
    SyntaxLeaf(value; open, close, indentation, collapsed, selection)

A leaf node with a content `value` and optional opening/closing delimiters.
`value` is the sole positional argument (so the meaningful content leads); it is
a `TextString`, a bare `String`/`Function` (auto-wrapped), or a
`@projection_template` marker such as `bound(:value, …)`. Every delimiter /
layout / selection field is an optional keyword:

  - `open`, `close` — delimiter `TextString`s (a bare `String` is auto-wrapped);
    default empty `TextString("")`.
  - `indentation::Int` — pretty-print indentation; default `0`.
  - `collapsed::Bool` — collapsed state; default `false`.
  - `selection` — a `ReferencePath`/`Cell`/`nothing`; default `nothing`.

Renders as: open.content * value.content * close.content

The `selection` cell holds a path into the leaf's rendered span, or `nothing`:
  `.open{k}`   — cursor at boundary k of the open delimiter (0-based)
  `.value{k}`  — cursor at boundary k of the value content
  `.close{k}`  — cursor at boundary k of the close delimiter
"""
@document struct SyntaxLeaf <: SyntaxDocument
    open::TextString
    close::TextString
    value::TextString
    indentation::Int
    collapsed::Bool
    selection::Reference
end

# Canonical keyword constructor: `value` leads positionally and is left untyped
# so it also accepts a `bound(…)`/marker object from `@projection_template`
# builders. open/close auto-wrap a bare string via `_text`.
SyntaxLeaf(value; open=TextString(""), close=TextString(""),
           indentation::Int=0, collapsed=false, selection=nothing) =
    SyntaxLeaf(_text(open), _text(close), value, indentation, collapsed, selection)

# Bare-string / function content ergonomics route through the keyword form so
# they inherit the same defaults.
SyntaxLeaf(value::AbstractString; kwargs...) = SyntaxLeaf(TextString(value); kwargs...)
SyntaxLeaf(f::Function; kwargs...) =
    SyntaxLeaf(TextString(f, font_ubuntu_monospace_regular_24, color_default); kwargs...)

# Positional delimiter forms retained for callers not yet migrated to keywords.
SyntaxLeaf(open::TextString, close::TextString, value::TextString) =
    SyntaxLeaf(open, close, value, 0, false, nothing)

SyntaxLeaf(open::TextString, close::TextString, value::TextString, selection) =
    SyntaxLeaf(open, close, value, 0, false, selection)

SyntaxLeaf(open::AbstractString, close::AbstractString, value::AbstractString) =
    SyntaxLeaf(TextString(open), TextString(close), TextString(value), 0, false, nothing)

SyntaxLeaf(open::AbstractString, close::AbstractString, f::Function) =
    SyntaxLeaf(TextString(open), TextString(close), TextString(f, font_ubuntu_monospace_regular_24, color_default), 0, false, nothing)

# ── Node ─────────────────────────────────────────────────────────────────

"""
    SyntaxNode(children; open, close, sep, indentation, collapsed, selection)

A compound node with `children` and optional opening/closing delimiters and a
separator. `children` is the sole positional argument; it is a
`Vector{<:SyntaxDocument}`, a `CellVector`, a `Function` builder, or a
`@projection_template` marker such as `collection(:field)`. Every delimiter /
layout / selection field is an optional keyword:

  - `open`, `close`, `sep` — `TextString`s (a bare `String` is auto-wrapped);
    default empty `TextString("")`.
  - `indentation::Int` — pretty-print indentation; default `0`.
  - `collapsed::Bool` — collapsed state; default `false`.
  - `selection` — a `ReferencePath`/`Cell`/`nothing`; default `nothing`.

Renders as: open.content * join(children, sep.content) * close.content

The `selection` cell routes a cursor into the rendered node, or `nothing`:
  `.open{k}`          — cursor at boundary k of the open delimiter (0-based)
  `.close{k}`         — cursor at boundary k of the close delimiter
  `.children[i]`      — descend into the i-th child (1-based); set_selection!
                        clears all other children and propagates the rest into child i
"""
@document struct SyntaxNode <: SyntaxDocument
    open::TextString
    close::TextString
    sep::TextString
    children::CellVector
    indentation::Int
    collapsed::Bool
    selection::Reference
end

# Canonical keyword constructor: `children` leads positionally; `_children`
# normalizes a Vector/CellVector/Function builder and passes a marker through
# untouched. open/close/sep auto-wrap a bare string via `_text`.
SyntaxNode(children; open=TextString(""), close=TextString(""), sep=TextString(""),
           indentation::Int=0, collapsed=false, selection=nothing) =
    SyntaxNode(_text(open), _text(close), _text(sep), _children(children),
               indentation, collapsed, selection)

# Positional delimiter forms retained for callers not yet migrated to keywords.
SyntaxNode(open::TextString, close::TextString, sep::TextString,
      children::Vector{<:SyntaxDocument}; indentation::Int = 0) =
    SyntaxNode(open, close, sep, CellVector(Cell[Cell(c) for c in children]), indentation, false, nothing)

SyntaxNode(open::TextString, close::TextString, sep::TextString;
      indentation::Int = 0) =
    SyntaxNode(open, close, sep, CellVector(), indentation, false, nothing)

SyntaxNode(open::TextString, close::TextString, sep::TextString,
      f::Function; indentation::Int = 0) =
    SyntaxNode(open, close, sep, CellVector(f), indentation, false, nothing)

SyntaxNode(open::AbstractString, close::AbstractString, sep::AbstractString,
      children::Vector{<:SyntaxDocument}; indentation::Int = 0) =
    SyntaxNode(TextString(open), TextString(close), TextString(sep),
               CellVector(Cell[Cell(c) for c in children]), indentation, false, nothing)

SyntaxNode(open::AbstractString, close::AbstractString, sep::AbstractString;
      indentation::Int = 0) =
    SyntaxNode(TextString(open), TextString(close), TextString(sep), CellVector(), indentation, false, nothing)

SyntaxNode(open::AbstractString, close::AbstractString, sep::AbstractString,
      f::Function; indentation::Int = 0) =
    SyntaxNode(TextString(open), TextString(close), TextString(sep), CellVector(f), indentation, false, nothing)

# Text-replace edits on a SyntaxLeaf (`open`/`value`/`close`) or SyntaxNode
# (`open`/`close`/`sep`) are handled generically by `splice_value!`: each of
# those fields holds a TextString, so the TextString representation (defined in
# TextModule) splices the span's content. No per-type method is needed.

# ── Unparse (render to string) ──────────────────────────────────────────

"""
    render(tree::SyntaxDocument) -> String

Recursively render the tree into a string. Reading cells during rendering
registers reactive dependencies automatically.
"""
function render(leaf::SyntaxLeaf)
    string(leaf.open.content, leaf.value.content, leaf.close.content)
end

function render(node::SyntaxNode)
    parts = [render(child) for child in node.children]
    string(node.open.content, join(parts, node.sep.content), node.close.content)
end

# ── setfn! delegation ───────────────────────────────────────────────────

setfn!(t::SyntaxLeaf, f::Function) = (setfn!(getfield(t.value, :content), f); t)
setfn!(n::SyntaxNode, f::Function) = (setfn!(getfield(n.children, :elements), () -> Cell[Cell(x) for x in f()]); n)

# ── document_read: geometry-free tree-navigation gesture mapping ──────────
#
# The projection-independent half of the Syntax domain's reader. The entire
# keyboard mapping for a syntax tree is already geometry-free — it walks the
# `SyntaxNode` tree and its selection *paths* — so all of it lives here on the
# document. Any projection whose input is a `SyntaxNode` (e.g. `SyntaxToText`)
# delegates here; the (geometry/output-driven) mouse hit-testing for collapse
# glyphs and Alt+click stays in `SyntaxToText`'s 4-arg reader.
#
# Relocated verbatim from `SyntaxNodeToText`'s `evt::KeyDown` reader and helpers.
# The selection on the root node is a path like `.children[i].children[j]…∅`.
# - Ctrl+Alt+Home → select the root node (∅)
# - Ctrl+Space    → toggle structural ⇄ text (character-cursor) mode
# - :up    → drop the last `.children[k]` step (select parent)
# - :down  → append `.children[1]` (select first child)
# - :left  → decrement the last child index
# - :right → increment the last child index
# Arrows require Alt only to *enter* structural mode from a character cursor;
# once a whole element is selected, plain arrows continue node-to-node movement.
function document_read(node::SyntaxNode, evt)
    evt isa KeyDown || return nothing
    sel = node.selection
    # Loose modifier guards (via when) preserve the pre-migration behaviour:
    # the chords ignore unlisted modifiers, and an arrow navigates whenever it
    # is alt-modified or the selection is already structural.
    @event_case evt begin
        # Ctrl+Alt+Home → select the root node (∅).
        when(KeyDown(:home), evt.modifiers.ctrl && evt.modifiers.alt) =>
            return ReplaceSelectionOperation(EmptyReferencePath())
        # Ctrl+Space → toggle structural ⇄ text (character-cursor) mode.
        when(KeyDown(:space), evt.modifiers.ctrl) => begin
            new_path = _is_tree_selection(sel) ? _descend_to_text_cursor(node, sel) :
                                                 _promote_to_structural(sel)
            new_path === nothing && return nothing
            return ReplaceSelectionOperation(new_path)
        end
        # Arrows move node-to-node, but only to *enter* structural mode from a
        # character cursor (Alt held) or once a whole element is already selected.
        when(KeyDown(k), k in (:up, :down, :left, :right) &&
                         (evt.modifiers.alt || _is_tree_selection(sel))) => begin
            new_path = _tree_navigate(node, sel, k)
            new_path === nothing && return nothing
            return ReplaceSelectionOperation(new_path)
        end
    end
    return nothing
end

function _tree_navigate(node::SyntaxNode, sel, direction::Symbol)
    # sel must be a tree selection (path of .children[i] steps ending in ∅)
    sel === nothing && return nothing
    sel = skip_type_checkpoints(sel)

    # ∅ on the root node: this node is wholly selected
    if sel isa EmptyReferencePath
        if direction === :up
            return nothing  # no parent at this level; propagate up
        elseif direction === :down
            children = node.children
            length(children) > 0 || return EmptyReferencePath()
            return @reference children[1]
        else
            return nothing  # left/right need a parent; propagate up
        end
    end

    sel isa ConcreteReferencePath || return nothing
    h = sel.head
    h isa FieldReference && h.name == "children" || return nothing
    rest = skip_type_checkpoints(sel.tail)
    rest isa ConcreteReferencePath || return nothing
    h2 = rest.head
    h2 isa RangeReference || return nothing
    child_idx = h2.start + 1  # 1-based
    children = node.children
    (1 <= child_idx <= length(children)) || return nothing
    child_rest = skip_type_checkpoints(rest.tail)

    if child_rest isa EmptyReferencePath
        # The selected node is children[child_idx]
        if direction === :up
            return EmptyReferencePath()  # select the current node
        elseif direction === :down
            child = children[child_idx]
            if child isa SyntaxNode && length(child.children) > 0
                return @reference children[child_idx].children[1]
            end
            return @reference children[child_idx]  # leaf or no children — stay
        elseif direction === :left
            child_idx > 1 || return @reference children[child_idx]  # already first
            return @reference children[child_idx - 1]
        elseif direction === :right
            child_idx < length(children) || return @reference children[child_idx]  # already last
            return @reference children[child_idx + 1]
        end
    else
        # Recurse into the child
        child = children[child_idx]
        child isa SyntaxNode || return @reference children[child_idx]
        inner = _tree_navigate(child, child_rest, direction)
        inner === nothing && return nothing
        return ConcreteReferencePath(FieldReference("children"),
                   ConcreteReferencePath(RangeReference(child_idx - 1, child_idx), inner))
    end
    return nothing
end

# A selection is "structural" (a whole-element / tree selection) when it is `∅`
# on the root, or a chain of `.children[i]` steps ending in `∅`. A character
# cursor differs by terminating in a leaf field step (`.value{k}` / `.open{k}`
# / `.close{k}`), which breaks the all-`children` requirement here.
_is_tree_selection(::EmptyReferencePath) = true
function _is_tree_selection(sel)
    sel = skip_type_checkpoints(sel)
    sel isa EmptyReferencePath && return true
    sel isa ConcreteReferencePath || return false
    h = sel.head
    h isa FieldReference && h.name == "children" || return false
    t = skip_type_checkpoints(sel.tail)
    t isa ConcreteReferencePath || return false
    t.head isa RangeReference || return false
    _is_tree_selection(skip_type_checkpoints(t.tail))
end

# Text → structural (Ctrl+Space): promote a character cursor to the whole
# element that contains it. Keep every leading `.children[i]` step and drop the
# trailing leaf-field cursor (`.value{k}` …), appending `∅`. A cursor on the
# root node's own delimiter (no `.children` prefix) promotes to the root (`∅`).
function _promote_to_structural(sel)
    pairs = RangeReference[]
    cur = skip_type_checkpoints(sel)
    while cur isa ConcreteReferencePath
        h = cur.head
        (h isa FieldReference && h.name == "children") || break
        t = skip_type_checkpoints(cur.tail)
        t isa ConcreteReferencePath || break
        h2 = t.head
        h2 isa RangeReference || break
        push!(pairs, h2)
        cur = skip_type_checkpoints(t.tail)
    end
    path = EmptyReferencePath()
    for h2 in Iterators.reverse(pairs)
        path = ConcreteReferencePath(FieldReference("children"),
                   ConcreteReferencePath(h2, path))
    end
    return path
end

# Structural → text (Ctrl+Space): from a whole-element tree selection, walk the
# `.children[i]` path to the selected element, then descend to its first leaf
# and place a character cursor at the start of that leaf's value (`…value{0}`).
# Returns nothing if a node along the way has no children (no leaf to land on).
function _descend_to_text_cursor(node::SyntaxNode, sel)
    indices = Int[]
    cur = node
    p = skip_type_checkpoints(sel)
    while p isa ConcreteReferencePath
        h = p.head
        (h isa FieldReference && h.name == "children") || return nothing
        t = skip_type_checkpoints(p.tail)
        t isa ConcreteReferencePath || return nothing
        h2 = t.head
        h2 isa RangeReference || return nothing
        i = h2.start + 1
        children = cur.children
        (1 <= i <= length(children)) || return nothing
        push!(indices, i)
        cur = children[i]
        p = skip_type_checkpoints(t.tail)
    end
    while cur isa SyntaxNode
        isempty(cur.children) && return nothing
        push!(indices, 1)
        cur = cur.children[1]
    end
    cur isa SyntaxLeaf || return nothing
    path = ConcreteReferencePath(FieldReference("value"),
               ConcreteReferencePath(RangeReference(0, 0), EmptyReferencePath()))
    for i in Iterators.reverse(indices)
        path = ConcreteReferencePath(FieldReference("children"),
                   ConcreteReferencePath(RangeReference(i - 1, i), path))
    end
    return path
end

end # module
