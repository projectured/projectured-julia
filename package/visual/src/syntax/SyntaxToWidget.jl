"""
    SyntaxToWidgetModule

Syntax → Widget projection — the structure-as-widgets / content-as-text path
described in `plan/pending/syntax-to-widget.md`:

    Domain → Syntax → **Widget** → Graphics
             ^^^^^^   ^^^^^^^^
             …ToSyntax  SyntaxToWidget

A `SyntaxNode` projects to a widget *container* (a `WidgetCard` for an indented
node, a `HorizontalLayout` for an inline one); a `SyntaxLeaf` projects to an
embedded `TextText` rendered by `TextToGraphics` inside the widget tree, exactly
as `ConversationToWidget` embeds `TextText` in a `WidgetCard`. This keeps the
structural chrome in widgets while editable leaf content stays in the Text
domain (resolving C4/C5 of the plan).

Per the delegation principle (C1), `SyntaxNodeToWidget` projects *one* node to
*one* container and recurses every child through `recursion`, so each child is
dispatched by its own type and a domain may interpose a per-type widget
treatment via the `TypeDispatchingProjection`.

Collapse is reader-driven (no command widget): the `WidgetCard` header-click
hit-test in `WidgetCardToGraphicsCanvas` emits `ToggleCollapseOperation(card)`;
the retargeting reader here walks the stored child iomaps to turn that widget
target back into the owning `SyntaxNode`, identical to `ConversationToWidget`.
"""
module SyntaxToWidgetModule

import ..CellModule: Cell
import ..CollectionModule: CellVector
import ..ProjectionApiModule: print_document, print_child,
                              read_intent, map_reference_forward,
                              map_reference_backward, Projection
import ..SyntaxModule: SyntaxDocument, SyntaxLeaf, SyntaxNode
import ..TextModule: TextText, TextString, TextDocument
import ..FontModule: font_ubuntu_monospace_regular_20, font_dejavu_monospace_regular_20
import ..ColorModule: color_default, color_solarized_gray
import ..WidgetModule: WidgetCard, WidgetLabel, Point2D
import ..LayoutModule: HorizontalLayout, VerticalLayout
import ..IoMapModule: SimpleIoMap, ChildrenIoMap
import ..OperationModule: ReplaceSelectionOperation, ToggleCollapseOperation
import ..PrimitiveModule: ReplaceStringRangeOperation
import ..ReferenceModule: ConcreteReferencePath, FieldReference, RangeReference,
                          ProjectionReference, ReferencePath, EmptyReferencePath, strip_reference_types
import ..ReferenceCaseModule: var"@reference_case"
import ..ReferenceBuilderModule: var"@reference"
import ..KeyboardModule: KeyDown
import ..TypeDispatchingProjectionModule: TypeDispatchingProjection
import ..PrinterContextModule: make_child_context

export SyntaxLeafToWidget, SyntaxNodeToWidget, SyntaxToWidget

# ── Constants ────────────────────────────────────────────────────────────────

# Layouts are pure organizers here, not visual separators: keep lines as tight
# as plain text (no inter-line gap) and only a small gap between the fold marker
# and the open delimiter in a header.
const _CARD_WIDTH  = 480
const _LINE_GAP    = 0
const _HEADER_GAP  = 4

# Default predicate for which nodes are collapsible (carry a fold marker): any
# node with at least one child. A pipeline can pass a stricter predicate.
_default_marker_eligible(node::SyntaxNode) = length(node.children) > 0

# ── SyntaxLeafToWidget ─────────────────────────────────────────────────────
# A leaf becomes an embedded TextText with three spans (open, value, close),
# exactly mirroring SyntaxLeafToText so cursor placement / editing / multi-span
# styling are preserved. The leaf's selection is wired forward into the TextText.

struct SyntaxLeafToWidget <: Projection end

_text_elem_path(span_idx::Int, char_idx::Int) =
    @reference elements[span_idx].content{char_idx}

function map_reference_forward(::SyntaxLeafToWidget, iomap, reference)
    @reference_case reference begin
        ∅                  => @reference()
        open{s:_}          => _text_elem_path(1, s)
        value{s:_}         => _text_elem_path(2, s)
        close{s:_}         => _text_elem_path(3, s)
        proj(_, open{s:_}) => _text_elem_path(1, s)
        proj(_, close{s:_})=> _text_elem_path(3, s)
    end
end

# Parse a `.elements[i].content{k}` TextText path → (span_idx, char_idx) or
# (nothing, nothing) on mismatch.
function _parse_text_elem_path(path)
    path = strip_reference_types(path)
    path isa ConcreteReferencePath || return (nothing, nothing)
    h1 = path.head
    h1 isa FieldReference && h1.name == "elements" || return (nothing, nothing)
    t1 = path.tail
    t1 isa ConcreteReferencePath || return (nothing, nothing)
    h2 = t1.head
    h2 isa RangeReference || return (nothing, nothing)
    span_idx = h2.start + 1
    t2 = t1.tail
    t2 isa ConcreteReferencePath || return (nothing, nothing)
    h3 = t2.head
    h3 isa FieldReference && h3.name == "content" || return (nothing, nothing)
    t3 = t2.tail
    t3 isa ConcreteReferencePath || return (nothing, nothing)
    h4 = t3.head
    h4 isa RangeReference || return (nothing, nothing)
    return (span_idx, h4.start::Int)
end

function _parse_text_elem_range(path)
    path = strip_reference_types(path)
    path isa ConcreteReferencePath || return nothing
    h1 = path.head
    (h1 isa FieldReference && h1.name == "elements") || return nothing
    t1 = path.tail
    t1 isa ConcreteReferencePath || return nothing
    h2 = t1.head
    h2 isa RangeReference || return nothing
    span_idx = h2.start + 1
    t2 = t1.tail
    t2 isa ConcreteReferencePath || return nothing
    h3 = t2.head
    (h3 isa FieldReference && h3.name == "content") || return nothing
    t3 = t2.tail
    t3 isa ConcreteReferencePath || return nothing
    h4 = t3.head
    h4 isa RangeReference || return nothing
    return (span_idx, h4.start::Int, h4.stop::Int)
end

function map_reference_backward(::SyntaxLeafToWidget, iomap, reference)
    reference isa EmptyReferencePath && return @reference()
    span_idx, char_idx = _parse_text_elem_path(reference)
    span_idx === nothing && return nothing
    span_idx == 1 && return @reference open{char_idx}
    span_idx == 2 && return @reference value{char_idx}
    span_idx == 3 && return @reference close{char_idx}
    return nothing
end

function print_document(p::SyntaxLeafToWidget, recursion, leaf::SyntaxLeaf, ctx)
    sel = Cell(() -> begin
        s = leaf.selection
        s isa EmptyReferencePath && return @reference()
        s === nothing && return nothing
        map_reference_forward(p, nothing, s)
    end)
    tt = TextText(CellVector(() -> TextDocument[leaf.open, leaf.value, leaf.close]), sel)
    SimpleIoMap(p, leaf, tt)
end

function read_intent(p::SyntaxLeafToWidget, iomap::SimpleIoMap, op::ReplaceSelectionOperation)
    input_path = map_reference_backward(p, iomap, op.path)
    input_path === nothing && return nothing
    return ReplaceSelectionOperation(input_path)
end

# Translate a TextText-domain ReplaceStringRangeOperation (referencing
# `.elements[2].content[s:e]`, the value span) back to a `.value[s:e]` op.
function read_intent(p::SyntaxLeafToWidget, iomap::SimpleIoMap, op::ReplaceStringRangeOperation)
    parsed = _parse_text_elem_range(op.reference)
    parsed === nothing && return nothing
    span_idx, char_start, char_stop = parsed
    span_idx == 2 || return nothing
    new_ref = ConcreteReferencePath(FieldReference("value"),
                  ConcreteReferencePath(RangeReference(char_start, char_stop), EmptyReferencePath()))
    ReplaceStringRangeOperation(new_ref, op.replacement)
end

# Pass KeyDown through so upstream projections can react (Backspace/Delete etc.).
read_intent(::SyntaxLeafToWidget, iomap::SimpleIoMap, evt::KeyDown) = evt
read_intent(::SyntaxLeafToWidget, iomap::SimpleIoMap, evt) = nothing

# ── SyntaxNodeToWidget ──────────────────────────────────────────────────────
# An indented node → WidgetCard (collapsible: header = open delimiter, content =
# the children stacked vertically + the close delimiter). An inline node
# (indentation == 0) → a single HorizontalLayout holding open, the children
# interleaved with separators, and close — one line, no fold.

struct SyntaxNodeToWidget <: Projection
    expanded_marker::String
    collapsed_marker::String
    marker_eligible::Any
    ellipsis::String
    card_width::Int
end

SyntaxNodeToWidget(; expanded_marker::AbstractString = "▾",
                     collapsed_marker::AbstractString = "▸",
                     marker_eligible = _default_marker_eligible,
                     ellipsis::AbstractString = "…",
                     card_width::Integer = _CARD_WIDTH) =
    SyntaxNodeToWidget(String(expanded_marker), String(collapsed_marker),
                       marker_eligible, String(ellipsis), Int(card_width))

# A delimiter / separator TextString → a one-span TextText so it renders through
# TextToGraphics carrying its own font/color.
_delim_text(ts::TextString) = TextText(CellVector(() -> TextDocument[ts]), Cell(nothing))

# A projection-introduced chrome glyph (marker / ellipsis) in the muted DejaVu
# mono font that carries ▾ ▸ … glyphs.
_chrome_text(s::AbstractString) =
    TextText(CellVector(() -> TextDocument[TextString(s, font_dejavu_monospace_regular_20, color_solarized_gray)]),
             Cell(nothing))

function print_document(p::SyntaxNodeToWidget, recursion, node::SyntaxNode, ctx)
    ref = ctx.reference
    # Delegate every child through the recursion (C1): each re-enters the
    # pipeline and is dispatched by its own type. Cache the iomaps so the toggle
    # reader can match the produced widgets and the layout reads each `.output`.
    child_ioms = Cell(() -> Any[
        print_child(recursion, node.children[i],
                                   make_child_context(ctx, @reference ^(ref).children[i]))
        for i in eachindex(node.children)
    ])

    if node.indentation == 0
        # Inline: one horizontal line — open, children interleaved with sep, close.
        # Top-aligned and gap-free so it reads like a single line of plain text
        # (a tall nested value lines up at the top, not vertically centred).
        line = HorizontalLayout(CellVector(() -> begin
            pieces = Any[]
            isempty(node.open.content) || push!(pieces, _delim_text(node.open))
            ioms = child_ioms[]
            for (i, im) in enumerate(ioms)
                i > 1 && push!(pieces, _delim_text(node.sep))
                push!(pieces, im.output)
            end
            isempty(node.close.content) || push!(pieces, _delim_text(node.close))
            pieces
        end), Cell(:top), Cell(_LINE_GAP), Cell(nothing))
        return ChildrenIoMap(p, node, line, child_ioms)
    end

    # Indented: a collapsible card. Header = fold marker + open delimiter; when
    # collapsed the ellipsis (and close delimiter) are appended to the **header**
    # so the fold reads inline with its parent ("▸ city …") rather than on a
    # separate body line, and the body is emptied. When expanded the body holds
    # the children stacked vertically followed by the close delimiter. Both the
    # header and the body read `node.collapsed`, so toggling re-renders reactively.
    header = HorizontalLayout(CellVector(() -> begin
        pieces = Any[]
        if p.marker_eligible(node)
            m = node.collapsed ? p.collapsed_marker : p.expanded_marker
            isempty(m) || push!(pieces, _chrome_text(m))
        end
        isempty(node.open.content) || push!(pieces, _delim_text(node.open))
        if node.collapsed
            push!(pieces, _chrome_text(p.ellipsis))
            isempty(node.close.content) || push!(pieces, _delim_text(node.close))
        end
        pieces
    end), Cell(:top), Cell(_HEADER_GAP), Cell(nothing))

    # Children stacked top-to-bottom, left-aligned, tight as plain text; empty
    # while collapsed (the ellipsis lives in the header above).
    body = VerticalLayout(CellVector(() -> begin
        node.collapsed && return Any[]
        out = Any[]
        for im in child_ioms[]
            push!(out, im.output)
        end
        isempty(node.close.content) || push!(out, _delim_text(node.close))
        out
    end), Cell(:left), Cell(_LINE_GAP), Cell(nothing))

    card = WidgetCard(Point2D(0, 0); title = header, content = body, width = p.card_width)
    ChildrenIoMap(p, node, card, child_ioms)
end

# ── Selection / reference mapping ──────────────────────────────────────────
# A widget-domain selection path reaches the node already rooted at one of its
# laid-out layouts as `children[piece]…` (the layout/card graphics readers
# prepend `children[i]`; `WidgetCardToGraphicsCanvas` is transparent and routes a
# body click into the body `VerticalLayout` without adding a step). To re-root it
# back to the syntax domain we de-interleave that piece index — skipping the
# projection-introduced open/close/sep pieces — to the syntax child it came from,
# then delegate the tail through that child's stored iomap (School A, as in
# `JsonArrayToSyntaxNode`). The helpers below mirror the piece layout built by
# `print_document`:
#
#   inline node (HorizontalLayout): [ open?  child₁  sep  child₂ … childₙ  close? ]
#   indented node body (VerticalLayout): [ child₁  child₂ … childₙ  close? ]
#
# The indented header (marker/open, plus ellipsis/close when collapsed) is never a
# selection path — the card hit-tests it and emits ToggleCollapseOperation — so
# only the inline-HL and indented-body shapes are mapped.

# Piece index (1-based) of inline child `i`.
function _inline_child_piece(node::SyntaxNode, i::Int)
    open_off = isempty(node.open.content) ? 0 : 1
    open_off + 1 + 2 * (i - 1)
end

# Piece index (1-based) of the inline close delimiter (valid only when present).
function _inline_close_piece(node::SyntaxNode)
    open_off = isempty(node.open.content) ? 0 : 1
    n = length(node.children)
    open_off + (n == 0 ? 0 : 2n - 1) + 1
end

# Kind of the inline HorizontalLayout piece at `piece` (1-based):
# (:child, i) | (:open,) | (:close,) | (:sep,) | nothing.
function _inline_piece_kind(node::SyntaxNode, piece::Int)
    piece < 1 && return nothing
    open_off = isempty(node.open.content) ? 0 : 1
    n = length(node.children)
    has_close = !isempty(node.close.content)
    open_off == 1 && piece == 1 && return (:open,)
    has_close && piece == _inline_close_piece(node) && return (:close,)
    rel = piece - open_off                 # 1-based within [child sep child … child]
    rel < 1 && return nothing
    if isodd(rel)
        i = (rel + 1) ÷ 2
        1 <= i <= n ? (:child, i) : nothing
    else
        (:sep,)
    end
end

# Kind of the indented body VerticalLayout piece at `piece` (1-based):
# (:child, i) | (:close,) | nothing.
function _body_piece_kind(node::SyntaxNode, piece::Int)
    n = length(node.children)
    1 <= piece <= n && return (:child, piece)
    !isempty(node.close.content) && piece == n + 1 && return (:close,)
    nothing
end

# Peel a leading `children[piece]` step → (piece::Int, rest) or nothing.
function _peel_children_step(reference)
    reference isa ConcreteReferencePath || return nothing
    h = reference.head
    (h isa FieldReference && h.name == "children") || return nothing
    t = reference.tail
    t isa ConcreteReferencePath || return nothing
    h2 = t.head
    h2 isa RangeReference || return nothing
    (h2.start + 1, t.tail)
end

function map_reference_backward(p::SyntaxNodeToWidget, iomap::ChildrenIoMap, reference)
    reference isa EmptyReferencePath && return @reference()
    peeled = _peel_children_step(reference)
    peeled === nothing && return nothing
    piece, rest = peeled
    node = iomap.input::SyntaxNode
    kind = node.indentation == 0 ? _inline_piece_kind(node, piece) :
                                   _body_piece_kind(node, piece)
    kind === nothing && return nothing
    if kind[1] === :child
        i = kind[2]
        iomaps = iomap.child_iomaps[]
        1 <= i <= length(iomaps) || return nothing
        child = iomaps[i]
        inner = map_reference_backward(child.projection, child, rest)
        inner === nothing && return nothing
        return @reference children[i].^(inner)
    elseif kind[1] === :open
        _, char_idx = _parse_text_elem_path(rest)
        char_idx === nothing && return nothing
        return @reference open{char_idx}
    elseif kind[1] === :close
        _, char_idx = _parse_text_elem_path(rest)
        char_idx === nothing && return nothing
        return @reference close{char_idx}
    end
    return nothing
end

function map_reference_forward(p::SyntaxNodeToWidget, iomap::ChildrenIoMap, reference)
    reference isa EmptyReferencePath && return @reference()
    reference isa ConcreteReferencePath || return nothing
    node = iomap.input::SyntaxNode
    h = reference.head
    if h isa FieldReference && h.name == "children"
        t = reference.tail
        t isa ConcreteReferencePath || return nothing
        h2 = t.head
        h2 isa RangeReference || return nothing
        i = h2.start + 1
        iomaps = iomap.child_iomaps[]
        1 <= i <= length(iomaps) || return nothing
        child = iomaps[i]
        inner = map_reference_forward(child.projection, child, t.tail)
        inner === nothing && return nothing
        piece = node.indentation == 0 ? _inline_child_piece(node, i) : i
        return @reference children[piece].^(inner)
    elseif h isa FieldReference && (h.name == "open" || h.name == "close")
        # A delimiter cursor maps into its one-span TextText piece. The inline
        # layout holds both delimiters; the indented header is not selectable, so
        # only the inline case has a widget pre-image.
        node.indentation == 0 || return nothing
        t = reference.tail
        t isa ConcreteReferencePath || return nothing
        h2 = t.head
        h2 isa RangeReference || return nothing
        k = h2.start
        if h.name == "open"
            isempty(node.open.content) && return nothing
            piece = 1
        else
            isempty(node.close.content) && return nothing
            piece = _inline_close_piece(node)
        end
        inner = @reference elements[1].content{k}
        return @reference children[piece].^(inner)
    end
    return nothing
end

# Walk the stored child iomaps to translate a widget target (a produced
# WidgetCard) back to the SyntaxNode whose projection produced it.
function _find_collapse_target(iomap, target)
    iomap.output === target && return iomap.input
    if iomap isa ChildrenIoMap
        children = iomap.child_iomaps[]
        for entry in children
            cim = entry isa Tuple ? entry[end] : entry
            node = _find_collapse_target(cim, target)
            node !== nothing && return node
        end
    end
    nothing
end

# The WidgetCard header-click reader emits ToggleCollapseOperation(card); retarget
# it to the owning SyntaxNode so `evaluate_operation` flips `node.collapsed`.
function read_intent(::SyntaxNodeToWidget, iomap, op::ToggleCollapseOperation)
    op.target === nothing && return op
    node = _find_collapse_target(iomap, op.target)
    node === nothing ? op : ToggleCollapseOperation(node)
end

# Re-root a path-bearing op from the widget output domain back to the syntax
# domain via the backward mapper (which recurses through the stored child iomaps).
# A reference with no syntax pre-image (a sep/chrome piece) drops the op.
function read_intent(p::SyntaxNodeToWidget, iomap::ChildrenIoMap, op::ReplaceSelectionOperation)
    new = map_reference_backward(p, iomap, op.path)
    new === nothing ? nothing : ReplaceSelectionOperation(new)
end

function read_intent(p::SyntaxNodeToWidget, iomap::ChildrenIoMap, op::ReplaceStringRangeOperation)
    new = map_reference_backward(p, iomap, op.reference)
    new === nothing ? nothing : ReplaceStringRangeOperation(new, op.replacement)
end

# Anything else (scrolls, non-path ops, …) passes through.
read_intent(::SyntaxNodeToWidget, iomap, op) = op

# ── Factory ──────────────────────────────────────────────────────────────────

"""
    SyntaxToWidget(; expanded_marker, collapsed_marker, marker_eligible,
                     ellipsis, card_width)

Type-dispatching projection over the syntax document types. Wrap in a
`RecursiveProjection` at the call site so children re-enter the pipeline.
"""
function SyntaxToWidget(; expanded_marker::AbstractString = "▾",
                          collapsed_marker::AbstractString = "▸",
                          marker_eligible = _default_marker_eligible,
                          ellipsis::AbstractString = "…",
                          card_width::Integer = _CARD_WIDTH)
    TypeDispatchingProjection(
        SyntaxLeaf => SyntaxLeafToWidget(),
        SyntaxNode => SyntaxNodeToWidget(; expanded_marker = expanded_marker,
                                          collapsed_marker = collapsed_marker,
                                          marker_eligible = marker_eligible,
                                          ellipsis = ellipsis,
                                          card_width = card_width),
    )
end

end # module
