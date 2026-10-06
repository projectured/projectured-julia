# Fragment of `SyntaxModule` — the syntax document types: the abstract
# `SyntaxDocument`, the leaf that carries text, and the compound node that
# carries its delimiters, separators and children.

abstract type SyntaxDocument <: Document end

"""
    SyntaxCompound

An interior node of the syntax tree: a syntax document that has children. Comes in
two kinds — a `SyntaxSequence` (any number of children, `.children[i]`) and a
`SyntaxWrapper` (exactly one, `.content`). `SyntaxLeaf` is neither.

Everything that walks the tree — tree navigation, collapse resolution, the flat
metric, and the splice printer — is written against this type, not against
`SyntaxNode`. Otherwise `SyntaxNode` would be the only navigable interior node and
every other compound an opaque dead end in the middle of the tree.
"""
abstract type SyntaxCompound <: SyntaxDocument end

"""
    SyntaxSequence

A compound whose children are a `children::CellVector` — an arbitrary number of them,
addressed `.children[i]`. `SyntaxNode`, `SyntaxConcatenation`, `SyntaxSeparation`.
"""
abstract type SyntaxSequence <: SyntaxCompound end

"""
    SyntaxWrapper

A compound with exactly one child, held in `content` and addressed `.content` —
`SyntaxDelimitation`, `SyntaxIndentation`, `SyntaxCollapsible`, `SyntaxNavigation`.

A wrapper is a compound like any other: it has a child, it lays out its own spans
around it, and it is a level of the tree. It is not a special case for the printer,
the mappers, the readers or the flat metric — the only thing that distinguishes it is
*how it addresses its child*, which is what `build_syntax_child_path` answers.
"""
abstract type SyntaxWrapper <: SyntaxCompound end

# ── The compound contract ─────────────────────────────────────────────────
#
# What a compound answers about itself. These are *document* facts, not rendering
# choices — which spans a compound has is decided by the document; the projection
# supplies only configuration (indent size, marker glyphs). A compound that lacks
# a given span answers `nothing`, and no span — and so no caret — is emitted.
#
# An answer names the DOCUMENT FIELD the span comes from, because that is what the
# reference mappers hand back: a caret in that span is `.<field>{k}`. So a compound
# is free to call its delimiters whatever it likes (`SyntaxNode` says `open`, a
# `SyntaxDelimitation` would say `opening_delimiter`) without the printer or the
# mappers knowing the difference.

"Every compound's children. A `SyntaxDocument` that is not a compound has none."
get_syntax_children(s::SyntaxSequence) = s.children
get_syntax_children(w::SyntaxWrapper) = [w.content]      # exactly one, always
get_syntax_children(::SyntaxDocument) = nothing

# ── How a compound addresses its child ───────────────────────────────────────
#
# The one place the two kinds of compound genuinely differ. A sequence's child `i` is
# `.children[i]`; a wrapper's only child is `.content`. Everything else — the splice
# printer, both mappers, both readers, tree navigation, collapse resolution, the flat
# metric — is written against these two functions and so does not care which it has.

"""
    build_syntax_child_path(doc, i, inner) -> Reference

The path from `doc` down into its `i`-th child, with `inner` beneath it. The type
checkpoint is the compound's own — `get_reference_node_type`, never `typeof`, which on a
`@document` struct is the reactive `R`-prefixed type.

**Reads nothing from the document**, deliberately. The reference mappers call this on
every caret step; indexing `get_syntax_children(doc)[i]` here would make each call a
*reactive read* of the child's element cell, which registers a dependency on whatever
cell happens to be computing. Path construction has no business doing that. Anything
that genuinely needs the child — see `_child_step`, which runs in a reader once per
keystroke — must already have it in hand.
"""
build_syntax_child_path(doc::SyntaxSequence, i::Int, inner) =
    ConcreteReference(get_reference_node_type(doc), FieldReferenceStep("children"),
        ConcreteReference(CellVector, RangeReferenceStep(i - 1, i), inner))

build_syntax_child_path(doc::SyntaxWrapper, ::Int, inner) =
    ConcreteReference(get_reference_node_type(doc), FieldReferenceStep("content"), inner)

"""
    peel_child_step(path) -> (i, tail) | nothing

The inverse: if `path` starts by descending into a child, which child and what is left.
Structural, because the matchers that need it (`_is_tree_selection`,
`_promote_to_structural`) are handed a path with no document to ask.
"""
function peel_child_step(path)
    path isa ConcreteReference || return nothing
    h = path.head
    h isa FieldReferenceStep || return nothing
    if h.name == "children"                      # a sequence: .children[i]
        t = path.tail
        t isa ConcreteReference || return nothing
        t.head isa RangeReferenceStep || return nothing
        return (t.head.start + 1, t.tail)
    elseif h.name == "content"                   # a wrapper: .content
        return (1, path.tail)
    end
    nothing
end

# Rebuild a peeled child step over a new tail, keeping its shape and node types. Used
# where a path must be reassembled without the documents in hand.
function _rebuild_child_step(node::ConcreteReference, tail)
    h = node.head
    (h isa FieldReferenceStep && h.name == "content") &&
        return ConcreteReference(node.type, h, tail)
    idx = node.tail::ConcreteReference       # .children[i]
    ConcreteReference(node.type, h, ConcreteReference(idx.type, idx.head, tail))
end

"The compound's opening / closing delimiter and separator, as `field => span`, or `nothing`."
get_opening_delimiter(::SyntaxCompound) = nothing
get_closing_delimiter(::SyntaxCompound) = nothing
get_separator(::SyntaxCompound) = nothing

"The compound's pretty-print indentation; `0` for one that does not indent."
get_indentation(::SyntaxCompound) = 0

"Whether the compound is collapsed; `false` for one that cannot collapse."
is_syntax_collapsed(::SyntaxCompound) = false

"""
Whether the compound can collapse at all.

Only a compound that can collapse is given a fold marker, and only such a compound
can be the target of a `ToggleCollapseOperation`. A compound with no `collapsed`
field would otherwise be handed a marker glyph that does nothing when clicked.
"""
is_syntax_collapsible(::SyntaxCompound) = false

# ── SyntaxInsertion ───────────────────────────────────────────────────────

@document struct SyntaxInsertion <: SyntaxDocument
    value::Any = nothing
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

# Constructor

- `SyntaxDelimitation(content; opening_delimiter=TextString(""), closing_delimiter=TextString(""))`
"""
@document struct SyntaxDelimitation <: SyntaxWrapper
    opening_delimiter::Union{TextString,Nothing} = nothing
    closing_delimiter::Union{TextString,Nothing} = nothing
    content
end

# Each delimiter is independently optional: an opener with no closer is a real thing
# (a trailing `;`, a leading `#`). Absent means *no span and no caret* — not
# `TextString("")`, which is the empty-span bug this whole plan exists to remove.
#
# The defaulted delimiters precede the required `content` for the same reason
# `SyntaxNode` leads with its own: `@document`'s Rule Y generates a positional
# constructor per arity from `get_cell_struct_required_count` upward, and `get_cell_struct_required_count` counts the
# fields *before the trailing run of defaulted ones*. Content-first would make the
# generated arity-1 form collide with the coercing constructor below.
SyntaxDelimitation(content; opening_delimiter=nothing, closing_delimiter=nothing, kwargs...) =
    SyntaxDelimitation(; opening_delimiter=_text(opening_delimiter),
                         closing_delimiter=_text(closing_delimiter),
                         content=content, kwargs...)

get_opening_delimiter(d::SyntaxDelimitation) =
    d.opening_delimiter === nothing ? nothing : (:opening_delimiter => d.opening_delimiter)
get_closing_delimiter(d::SyntaxDelimitation) =
    d.closing_delimiter === nothing ? nothing : (:closing_delimiter => d.closing_delimiter)

"""
    SyntaxIndentation

Wraps a document with a specific indentation level. Used to control
pretty-printing indentation for structured documents.

# Fields

- `content` — the wrapped document
- `indentation::Int` — the indentation level (number of spaces/tabs)

# Constructor

- `SyntaxIndentation(content; indentation::Int=0)`
"""
@document struct SyntaxIndentation <: SyntaxWrapper
    indentation::Int = 0
    content
end

SyntaxIndentation(content; indentation::Int=0, kwargs...) =
    SyntaxIndentation(; indentation=indentation, content=content, kwargs...)

get_indentation(i::SyntaxIndentation) = i.indentation

"""
    SyntaxCollapsible

Wraps a document with a collapsible state. Used to allow the UI to
collapse/expand portions of the document tree.

# Fields

- `content` — the wrapped document
- `collapsed::Cell` — holds `Bool` indicating if collapsed

# Constructor

- `SyntaxCollapsible(content; collapsed::Bool=false)`
"""
@document struct SyntaxCollapsible <: SyntaxWrapper
    collapsed::Bool = false
    content
end

SyntaxCollapsible(content; collapsed::Bool=false, kwargs...) =
    SyntaxCollapsible(; collapsed=collapsed, content=content, kwargs...)

is_syntax_collapsed(c::SyntaxCollapsible)   = c.collapsed
is_syntax_collapsible(::SyntaxCollapsible)  = true

"""
    SyntaxNavigation

Wraps a document to mark it as a navigation point. Used to indicate
that the cursor should be positioned at this location.

# Fields

- `content` — the wrapped document

# Constructor

- `SyntaxNavigation(content)` / `SyntaxNavigation(content, selection)` — positional only.

Unlike the other wrappers, `SyntaxNavigation` has **no coercing keyword constructor**: it
declares no default of its own, so `@document` generates no keyword form, and the string /
`Function` content ergonomics the others get do not apply. A caller passes `content`
positionally (a `Function` is wrapped as a computed cell, so lazily-projected content still
works) and, if needed, `selection` as the second positional argument. If a domain ever needs
the keyword form, give it a coercing constructor like `SyntaxDelimitation`'s.
"""
@document struct SyntaxNavigation <: SyntaxWrapper
    content
end

"""
    SyntaxConcatenation

Sequences its children and nothing else: no delimiters, no separator, no
indentation, no collapse. It renders as its children, end to end.

This is the same *rendering* a bare `SyntaxNode` produces, and deliberately so —
what `SyntaxConcatenation` adds is precision. A node that only sequences a fixed
child list says exactly that, and cannot later acquire a delimiter by accident,
where a `SyntaxNode` carrying five unused fields leaves the reader to work out
that none of them is set.

# Fields

- `children::CellVector` — holds the child `SyntaxDocument` nodes

# Constructors

- `SyntaxConcatenation(children::Vector{<:SyntaxDocument})`
- `SyntaxConcatenation()` — empty concatenation
"""
@document struct SyntaxConcatenation <: SyntaxSequence
    children::CellVector = CellVector()
end

SyntaxConcatenation(children::Vector{<:SyntaxDocument}) =
    SyntaxConcatenation(CellVector(Cell[Cell(c) for c in children]), nothing)

# A `Function` becomes the children field's own derivation: it is a
# `@projection_template` children *thunk* (a conditional-children node: `return` vs
# `return <value>`), and the markers in the vector it returns are resolved from that
# field directly. Coercing it into a `CellVector` would interpose a per-element
# cell-wrapping thunk, and those markers would never be resolved. A hand-written
# projection that wants reactive children says so explicitly:
# `SyntaxConcatenation(CellVector(Computation(f)))`.
SyntaxConcatenation(computation::Function) =
    SyntaxConcatenation(Cell(Computation(computation)), nothing)

# A concatenation answers the compound contract with the defaults throughout: it
# has children, and nothing else. Every `nothing` here is a span the printer does
# not emit and a caret the mappers decline.

"""
    SyntaxSeparation(children; separator, selection)

Sequences its children with a separator between each, and nothing else: no
delimiters, no indentation, no collapse. It renders as its children, joined.

A `SyntaxConcatenation` that also puts something between the children — which is
what a domain means when it writes a node with only a `sep` set (SQL's `_comma_node`,
Markdown's inline runs). An absent separator makes it a concatenation, so `separator`
is what distinguishes the two; a bare `String` is auto-wrapped and an empty one
normalizes to absence, like every other delimiter.

# Fields

- `separator::Union{TextString,Nothing}` — what goes between the children
- `children::CellVector` — the child `SyntaxDocument`s

The separator renders between every *pair* of children — n−1 spans for one field —
so a cursor may be placed in it (`.separator{k}` maps onto the first occurrence) but
an edit cannot be mapped back onto it: no single span *is* "the" separator. It maps
back as projection-introduced chrome, exactly as `SyntaxNode`'s `sep` does.

The field order is not cosmetic: the defaulted `separator` must precede the required
`children`, exactly as `SyntaxNode`'s delimiters do. `@document`'s Rule Y generates a
positional constructor per arity from `get_cell_struct_required_count` upward, where `get_cell_struct_required_count`
counts the fields *before the trailing run of defaulted ones*. With `children` first,
that run is `separator, selection`, `get_cell_struct_required_count` is 1, and the generated arity-1
`SyntaxSeparation(Any)` collides head-on with the coercing keyword constructor below —
a fatal method overwrite during precompilation. Leading with `separator` puts the
required field last, so generation starts at arity 2 and the arity-1 form is ours.
"""
@document struct SyntaxSeparation <: SyntaxSequence
    separator::Union{TextString,Nothing} = nothing
    children::CellVector
end

# Same shape as `SyntaxNode`'s: `children` leads positionally, everything else is a
# keyword, and the constructor only *coerces* before delegating — so every default is
# declared once, on the field.
SyntaxSeparation(children; separator=nothing, kwargs...) =
    SyntaxSeparation(; children=_children(children), separator=_text(separator), kwargs...)

get_separator(s::SyntaxSeparation) =
    s.separator === nothing ? nothing : (:separator => s.separator)

# ── Constructor helpers ────────────────────────────────────────────────────
#
# Shared by the `SyntaxLeaf`/`SyntaxNode` keyword constructors below.

# Auto-wrap a bare string delimiter so callers can write `open="<"` etc. An
# absent delimiter stays absent: `nothing` means the document has no such
# delimiter, and the printer emits no span for it — as opposed to `TextString("")`,
# which would emit an empty span carrying a caret that renders nowhere.
#
# An *empty* string delimiter means the same thing as no delimiter — it renders
# nothing — so it normalizes to absence. This is what lets a projection whose
# delimiter is configuration (`open::String = ""` for YAML's block style, say)
# stay written as it is and still emit no span.
#
# A `TextString` is passed through untouched, never inspected: its content is a
# reactive cell, and one that is empty *now* may not be later (XmlElement's tag
# close alternates between `" "` and `""` as attributes come and go). Dropping its
# span on the strength of a momentary emptiness would mean it could never come
# back — so an emptiable delimiter must be a `TextString`, and a statically absent
# one must be `nothing`.
_text(t::TextString) = t
_text(s::AbstractString) = isempty(s) ? nothing : TextString(s)
_text(::Nothing) = nothing

# Normalize the `children` argument of `SyntaxNode` to the `CellVector` the inner
# constructor stores. A `@projection_template` marker (e.g. `collection(:field)`)
# or any other object is passed through untouched, for the `@document` inner ctor
# to wrap in a `Cell` (the same shape the positional 7-arg form produces).
#
# NOTE: the container type is load-bearing in two conflicting ways, so do not
# "simplify" this without reading both:
#
#   * a hand-written projection's *output* node needs a `CellVector`, because the
#     reference machinery navigates `.children[i]` through its element cells;
#   * a `@projection_template` *blueprint* needs a raw `Vector`, because the engine
#     detects a fixed-children node by `getfield(out, f)[] isa Vector`
#     (ProjectionTemplate.jl `_has_fixed_children`) and walks it to resolve the
#     `bound`/`project` markers nested in each child. A `CellVector` there is not
#     recognised as a blueprint at all and the markers reach the printer unresolved.
#
# That is why a fixed-children template node is written in the positional 7-arg
# form (which stores the vector raw) rather than the keyword form, and why
# `SyntaxNode([...])` does not work inside a template today.
_children(c::CellVector) = c
_children(c::Vector{Cell}) = CellVector(c)
_children(c::AbstractVector) = CellVector(Cell[Cell(x) for x in c])
_children(f::Function) = CellVector(Computation(f))
_children(c) = c

# ── Leaf ─────────────────────────────────────────────────────────────────

"""
    SyntaxLeaf(value; open, close, indentation, collapsed, selection)

A leaf node with a content `value` and optional opening/closing delimiters.
`value` is the sole positional argument (so the meaningful content leads); it is
a `TextString`, a bare `String`/`Function` (auto-wrapped), or a
`@projection_template` marker such as `bound(:value, …)`. Every delimiter /
layout / selection field is an optional keyword:

  - `open`, `close` — delimiter `TextString`s (a bare `String` is auto-wrapped),
    or `nothing` for a leaf that has no such delimiter; default `nothing`. Each
    is independently optional: an opening delimiter may be present while the
    closing one is absent, and vice versa.
  - `indentation::Int` — pretty-print indentation; default `0`.
  - `collapsed::Bool` — collapsed state; default `false`.
  - `selection` — a `Reference`/`Cell`/`nothing`; default `nothing`.

Renders as: open.content * value.content * close.content, skipping absent delimiters.

An absent delimiter emits **no span**, and so offers no cursor position: a bare
leaf renders exactly one span, and `.open{k}` / `.close{k}` do not address
anything. (An *empty* delimiter — `TextString("")` — would emit a span that
renders nothing yet still carries a caret; that is what `nothing` avoids.)

The `selection` cell holds a path into the leaf's rendered span, or `nothing`:
  `.open{k}`   — cursor at boundary k of the open delimiter (0-based), if present
  `.value{k}`  — cursor at boundary k of the value content
  `.close{k}`  — cursor at boundary k of the close delimiter, if present
"""
@document struct SyntaxLeaf <: SyntaxDocument
    open::Union{TextString,Nothing} = nothing
    close::Union{TextString,Nothing} = nothing
    value::Union{TextString, TextGraphics}
    indentation::Int = 0
    collapsed::Bool = false
end

# Canonical keyword constructor: `value` leads positionally and is left untyped
# so it also accepts a `bound(…)`/marker object from `@projection_template`
# builders. Its only job is to coerce the delimiters through `_text` (auto-wrap a
# bare string, normalize an empty one to absence) and hand the rest to the
# `@document` keyword constructor, so every default is declared once — on the
# field — and never restated here.
SyntaxLeaf(value; open=nothing, close=nothing, kwargs...) =
    SyntaxLeaf(; open=_text(open), close=_text(close), value=value, kwargs...)

# Bare-string / function content ergonomics route through the keyword form so
# they inherit the same defaults.
SyntaxLeaf(value::AbstractString; kwargs...) = SyntaxLeaf(TextString(value); kwargs...)
SyntaxLeaf(f::Function; kwargs...) =
    SyntaxLeaf(TextString(f, UNSTYLED_TEXT_FONT, color_default); kwargs...)

# ── Node ─────────────────────────────────────────────────────────────────

"""
    SyntaxNode(children; open, close, sep, indentation, collapsed, selection)

A compound node with `children` and optional opening/closing delimiters and a
separator. `children` is the sole positional argument; it is a
`Vector{<:SyntaxDocument}`, a `CellVector`, a `Function` builder, or a
`@projection_template` marker such as `collection(:field)`. Every delimiter /
layout / selection field is an optional keyword:

  - `open`, `close`, `sep` — `TextString`s (a bare `String` is auto-wrapped), or
    `nothing` for a node that has no such delimiter/separator; default `nothing`.
    Each is independently optional.
  - `indentation::Int` — pretty-print indentation; default `0`.
  - `collapsed::Bool` — collapsed state; default `false`.
  - `selection` — a `Reference`/`Cell`/`nothing`; default `nothing`.

Renders as: open.content * join(children, sep.content) * close.content, skipping
absent delimiters (an absent `sep` joins the children with nothing between them).

An absent delimiter emits **no span**, and so offers no cursor position — see
`SyntaxLeaf`. A node with no delimiters and no separator is a plain concatenation
of its children.

The `selection` cell routes a cursor into the rendered node, or `nothing`:
  `.open{k}`          — cursor at boundary k of the open delimiter (0-based), if present
  `.close{k}`         — cursor at boundary k of the close delimiter, if present
  `.children[i]`      — descend into the i-th child (1-based); set_selection!
                        clears all other children and propagates the rest into child i
"""
@document struct SyntaxNode <: SyntaxSequence
    open::Union{TextString,Nothing} = nothing
    close::Union{TextString,Nothing} = nothing
    sep::Union{TextString,Nothing} = nothing
    children::CellVector
    indentation::Int = 0
    collapsed::Bool = false
end

# `SyntaxNode` is the compound that carries every span at once — the combined type
# a domain reaches for when its node really is delimited, separated, indented and
# collapsible. It answers the whole contract.
get_opening_delimiter(n::SyntaxNode)     = n.open === nothing ? nothing : (:open  => n.open)
get_closing_delimiter(n::SyntaxNode)     = n.close === nothing ? nothing : (:close => n.close)
get_separator(n::SyntaxNode)   = n.sep === nothing ? nothing : (:sep   => n.sep)
get_indentation(n::SyntaxNode) = n.indentation
is_syntax_collapsed(n::SyntaxNode)   = n.collapsed
is_syntax_collapsible(::SyntaxNode)  = true

# The fields that hold a closing delimiter: `close` of a `SyntaxNode` and of a
# `SyntaxLeaf`, `closing_delimiter` of a `SyntaxDelimitation`.
const _CLOSING_DELIMITER_FIELDS = ("close", "closing_delimiter")

"""
    is_on_closing_delimiter(selection) -> Bool

Whether `selection`, the selection that a document holds, is a caret on the closing
delimiter that the projection of that document to syntax printed, such as the `}`
of an object. A container rule that leaves a key to its parent there asks this.
"""
function is_on_closing_delimiter(selection)
    is_introduced_reference(selection) || return false
    output = strip_reference_types(selection.head.output_path)
    return output isa ConcreteReference && output.head isa FieldReferenceStep &&
           output.head.name in _CLOSING_DELIMITER_FIELDS
end

# Canonical keyword constructor: `children` leads positionally. Its only job is to
# coerce — the delimiters through `_text`, the children through `_children` — and
# hand the rest to the `@document` keyword constructor, so every default is
# declared once, on the field, and never restated here.
SyntaxNode(children; open=nothing, close=nothing, sep=nothing, kwargs...) =
    SyntaxNode(; open=_text(open), close=_text(close), sep=_text(sep),
                 children=_children(children), kwargs...)

# Text-replace edits on a SyntaxLeaf (`open`/`value`/`close`) or SyntaxNode
# (`open`/`close`/`sep`) are handled generically by `splice_value!`: each of
# those fields holds a TextString, so the TextString representation (defined in
# TextModule) splices the span's content. No per-type method is needed.

# ── Unparse (render to string) ──────────────────────────────────────────

# An absent delimiter contributes nothing to the rendered string.
_delimiter_content(::Nothing) = ""
_delimiter_content(t::TextString) = t.content

"""
    render(tree::SyntaxDocument) -> String

Recursively render the tree into a string. Reading cells during rendering
registers reactive dependencies automatically.
"""
function render(leaf::SyntaxLeaf)
    string(_delimiter_content(leaf.open), leaf.value.content, _delimiter_content(leaf.close))
end

# Every compound renders the same way — its children, joined by whatever separator
# it has, between whatever delimiters it has. A concatenation simply answers
# `nothing` to all three and so renders as its children, end to end.
_span_of(::Nothing) = nothing
_span_of(pair::Pair) = pair.second

function render(c::SyntaxCompound)
    parts = [render(child) for child in get_syntax_children(c)]
    string(_delimiter_content(_span_of(get_opening_delimiter(c))),
           join(parts, _delimiter_content(_span_of(get_separator(c)))),
           _delimiter_content(_span_of(get_closing_delimiter(c))))
end

# ── set_cell_computation! delegation ────────────────────────────────────────────────

set_cell_computation!(t::SyntaxLeaf, f::Function) = (set_cell_computation!(getfield(t.value, :content), f); t)
set_cell_computation!(n::SyntaxSequence, f::Function) = (set_cell_computation!(getfield(n.children, :elements), () -> Cell[Cell(x) for x in f()]); n)

# ── read_gesture via reified @gestures: geometry-free tree navigation ─────
#
# The projection-independent half of the Syntax domain's reader: a reified
# `@gestures` table. The generic `read_gesture` interpreter (`read_document_gesture`)
# fires it, so the table that *fires* is exactly the one gesture-help enumerates.
# Any projection whose input is a compound (e.g. `SyntaxToText`) reaches it through
# that interpreter; the geometry/output-driven mouse hit-testing for collapse glyphs
# and Alt+click stays in `SyntaxToText`'s 4-arg reader.
#
# The table is registered on `SyntaxCompound`, not on `SyntaxNode`: the registry
# collects a type's own bindings plus every supertype's, so one declaration covers
# every interior node there is or will be. Tree navigation is a property of *being*
# an interior node, not of being a `SyntaxNode` — a table per compound type would
# be the same twenty lines copied out once per wrapper. A `SyntaxLeaf` is not a
# compound and so is untouched by this.
#
# The entire mapping is geometry-free — it walks the compound tree and its
# selection *paths* (e.g. `.children[i].children[j]…∅`):
# - Ctrl+Alt+Home → select the root node (∅)
# - Ctrl+Space    → toggle structural ⇄ text (character-cursor) mode
# - Alt+arrow     → tree-navigate from any selection (enter structural)
# - plain arrow   → tree-navigate, but only once a whole element is selected
#
# Gestures match modifiers *exactly*: each rule names its exact modifier set, so a
# bare arrow (`KeyDown(k;)` — note the `;`: no modifiers held) and an `Alt+arrow`
# are *distinct* gestures. The old `@gesture_case` reader matched arrows loosely (any
# modifiers); exact matching is equivalent for every tested/real input (none
# carries an extra incidental modifier) and is the cleaner model — an unbound combo
# (e.g. Shift+arrow) simply declines instead of being filtered out by an explicit
# arm. The selection-dependent rules live in the operation, which reads
# `doc.selection` and returns `nothing` to decline so the gesture keeps propagating
# inward, exactly as the old `return nothing` arms did. The Alt-arrow and
# plain-arrow rules are disjoint (exact Alt vs. exact none); if Alt-arrow's
# operation declines, the plain-arrow rule does not match it, so it declines too —
# same result as the old reader.
@gestures SyntaxCompound begin
    KeyDown(:home; ctrl, alt) => "Select the root node" =>
        ReplaceSelectionOperation(EmptyReference())
    KeyDown(:space; ctrl) => "Toggle structural / text cursor" => begin
        sel = doc.selection
        new_path = _is_tree_selection(sel) ? _descend_to_text_cursor(doc, sel) :
                                             _promote_to_structural(sel)
        new_path === nothing ? nothing : ReplaceSelectionOperation(new_path)
    end
    when(KeyDown(k; alt), k in (:up, :down, :left, :right)) => "Navigate the tree" => begin
        new_path = _tree_navigate(doc, doc.selection, k)
        new_path === nothing ? nothing : ReplaceSelectionOperation(new_path)
    end
    when(KeyDown(k;), k in (:up, :down, :left, :right)) => "Navigate the tree" => begin
        sel = doc.selection
        _is_tree_selection(sel) || return nothing
        new_path = _tree_navigate(doc, sel, k)
        new_path === nothing ? nothing : ReplaceSelectionOperation(new_path)
    end
end

# A whole-element selection of a projection-introduced sub-node (e.g. Julia's
# `function name(params)` header) is carried as `ProjectionReferenceStep(_, .children[i]…)`
# so it round-trips through the projection above. For tree navigation it *is* a
# `.children[i]…` selection: unwrap to the inner output path and navigate that. The
# result re-wraps downstream — the projection's own backward mapper / reader
# fallback re-introduces the wrapper when the move lands on introduced structure
# again. A native SyntaxNode selection never carries this head, so it is a no-op there.
_unwrap_projection_ref(sel) =
    is_introduced_reference(sel) ? sel.head.output_path : sel

# A bare `∅` handed back by a child's own navigation means "the child node itself".
# Spliced under a child step it has to carry that child's type, because selections are
# compared with `==`, types included, and every other way of naming that same element
# (`@reference(doc, children[i])`, a click, a backward map) produces the typed form.
# Without this, walking `:up` out of a nested node yields a path that *is* the child but
# does not compare equal to it.
_typed_terminal(t::EmptyReference, child) =
    t.type === nothing ? EmptyReference(get_reference_node_type(child)) : t
_typed_terminal(t, _child) = t

# The navigation-side child step: `build_syntax_child_path` plus the child's type on a bare
# `∅`. This one DOES read the child, so it belongs here and not in `build_syntax_child_path`
# — tree navigation runs in a reader, once per keystroke, where a reactive read is
# harmless. The mappers, which run per caret step, must keep using the pure form.
_child_step(doc, i::Int, inner) =
    build_syntax_child_path(doc, i, _typed_terminal(inner, get_syntax_children(doc)[i]))

# The whole element: `doc`'s `i`-th child, selected entirely.
_child_element(doc, i::Int) = _child_step(doc, i, EmptyReference())

function _tree_navigate(doc::SyntaxCompound, sel, direction::Symbol)
    # sel must be a tree selection: child steps ending in ∅.
    sel === nothing && return nothing
    sel = _unwrap_projection_ref(sel)
    children = get_syntax_children(doc)

    # ∅ on this node: it is wholly selected.
    if sel isa EmptyReference
        if direction === :down
            length(children) > 0 || return EmptyReference()
            return _child_element(doc, 1)
        end
        # up has no parent at this level; left/right need one — propagate up.
        return nothing
    end

    step = peel_child_step(sel)
    step === nothing && return nothing
    child_idx, child_rest = step
    (1 <= child_idx <= length(children)) || return nothing
    child = children[child_idx]

    if child_rest isa EmptyReference
        # The selected node is this child.
        if direction === :up
            return EmptyReference()  # select the current node
        elseif direction === :down
            # Descend into the child, if it is an interior node with children of
            # its own; otherwise stay where we are.
            grandchildren = get_syntax_children(child)
            (grandchildren !== nothing && length(grandchildren) > 0) || return _child_element(doc, child_idx)
            return _child_step(doc, child_idx, _child_element(child, 1))
        elseif direction === :left
            child_idx > 1 || return _child_element(doc, child_idx)   # already first
            return _child_element(doc, child_idx - 1)
        elseif direction === :right
            child_idx < length(children) || return _child_element(doc, child_idx)  # already last
            return _child_element(doc, child_idx + 1)
        end
    else
        # Recurse into the child — any compound, sequence or wrapper.
        child isa SyntaxCompound || return _child_element(doc, child_idx)
        inner = _tree_navigate(child, child_rest, direction)
        inner === nothing && return nothing
        return _child_step(doc, child_idx, inner)
    end
    return nothing
end

# A selection is "structural" (a whole-element / tree selection) when it is `∅`
# on the root, or a chain of `.children[i]` steps ending in `∅`. A character
# cursor differs by terminating in a leaf field step (`.value{k}` / `.open{k}`
# / `.close{k}`), which breaks the all-`children` requirement here.
_is_tree_selection(::EmptyReference) = true
function _is_tree_selection(sel)
    sel = _unwrap_projection_ref(sel)
    sel isa EmptyReference && return true
    step = peel_child_step(sel)
    step === nothing && return false
    _is_tree_selection(step[2])
end

# Text → structural (Ctrl+Space): promote a character cursor to the whole element that
# contains it. Keep every leading child step and drop the trailing leaf-field cursor
# (`.value{k}` …), appending `∅`. A cursor on the root node's own delimiter (no child
# prefix) promotes to the root (`∅`).
#
# The steps are rebuilt from the nodes they were peeled from, so each keeps whatever
# shape it had — `.children[i]` or `.content` — without this function having to know
# which kind of compound produced it.
function _promote_to_structural(sel)
    steps = ConcreteReference[]
    cur = sel
    while true
        step = peel_child_step(cur)
        step === nothing && break
        push!(steps, cur::ConcreteReference)
        cur = step[2]
    end
    path = EmptyReference()
    for node in Iterators.reverse(steps)
        path = _rebuild_child_step(node, path)
    end
    return path
end

# Structural → text (Ctrl+Space): from a whole-element tree selection, walk down to the
# selected element, then descend to its first leaf and place a character cursor at the
# start of that leaf's value (`…value{0}`). Returns nothing if a node along the way has
# no children (no leaf to land on).
#
# The compound at each level is remembered on the way down, so the path can be rebuilt
# on the way back up by asking each one how it addresses its child.
function _descend_to_text_cursor(node::SyntaxCompound, sel)
    docs = SyntaxCompound[]
    indices = Int[]
    cur = node
    p = sel
    while !(p isa EmptyReference)
        step = peel_child_step(p)
        step === nothing && return nothing
        i, tail = step
        children = get_syntax_children(cur)
        children === nothing && return nothing
        (1 <= i <= length(children)) || return nothing
        push!(docs, cur)
        push!(indices, i)
        cur = children[i]
        p = tail
    end
    # Descend through any interior node — the first leaf is where a text cursor can
    # actually land.
    while cur isa SyntaxCompound
        isempty(get_syntax_children(cur)) && return nothing
        push!(docs, cur)
        push!(indices, 1)
        cur = get_syntax_children(cur)[1]
    end
    cur isa SyntaxLeaf || return nothing
    path = ConcreteReference(FieldReferenceStep("value"),
               ConcreteReference(RangeReferenceStep(0, 0), EmptyReference()))
    for k in length(indices):-1:1
        path = build_syntax_child_path(docs[k], indices[k], path)
    end
    return path
end

# A leaf IS its own first leaf: structural→text lands the cursor at the start of its
# value. This lets the leaf gesture table below share the compound's Ctrl+Space arm.
_descend_to_text_cursor(::SyntaxLeaf, _sel) =
    ConcreteReference(FieldReferenceStep("value"),
        ConcreteReference(RangeReferenceStep(0, 0), EmptyReference()))

# The leaf half of the Syntax reader. A `SyntaxLeaf` is not a `SyntaxCompound`, so the
# table above does not reach it — yet a leaf has the same two selection modes: the whole
# element (`∅`) and a character cursor in its value (`.value{k}`). Ctrl+Space toggles
# between them and Ctrl+Alt+Home selects the whole leaf, exactly as on a compound. There
# is no tree to navigate inside a leaf, so the arrow arms are omitted. Every projection
# whose input is a leaf (`SyntaxLeafToText`) fires this through the generic `read_gesture`
# interpreter, so the toggle backward-maps into every domain for free.
@gestures SyntaxLeaf begin
    KeyDown(:home; ctrl, alt) => "Select the whole leaf" =>
        ReplaceSelectionOperation(EmptyReference())
    KeyDown(:space; ctrl) => "Toggle structural / text cursor" => begin
        sel = doc.selection
        new_path = _is_tree_selection(sel) ? _descend_to_text_cursor(doc, sel) :
                                             _promote_to_structural(sel)
        new_path === nothing ? nothing : ReplaceSelectionOperation(new_path)
    end
end
