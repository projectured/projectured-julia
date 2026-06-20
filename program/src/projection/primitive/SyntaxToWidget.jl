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

import ..ReactiveModule: Cell
import ..CollectionModule: CellVector
import ..ProjectionApiModule: projection_print, projection_printer_recurse,
                              projection_read, map_reference_forward,
                              map_reference_backward, Projection
import ..SyntaxModule: SyntaxDocument, SyntaxLeaf, SyntaxNode
import ..TextModule: TextText, TextString, TextDocument
import ..FontModule: font_ubuntu_monospace_regular_24, font_dejavu_monospace_regular_24
import ..ColorModule: color_default, color_solarized_gray
import ..WidgetModule: WidgetCard, WidgetLabel, Point2D
import ..LayoutModule: HorizontalLayout, VerticalLayout
import ..IoMapModule: SimpleIoMap, ChildrenIoMap
import ..OperationModule: ReplaceSelectionOperation, ToggleCollapseOperation
import ..PrimitiveModule: StringReplaceRangeOperation
import ..ReferenceModule: ConcreteReferencePath, FieldReference, RangeReference,
                          ProjectionReference, ReferencePath, EmptyReferencePath
import ..ReferenceCaseModule: var"@reference_case"
import ..ReferenceBuilderModule: var"@reference"
import ..KeyboardModule: KeyDown
import ..TypeDispatchingModule: TypeDispatchingProjection
import ..PrinterContextModule: child_context

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

function projection_print(p::SyntaxLeafToWidget, recursion, leaf::SyntaxLeaf, ctx)
    sel = Cell(() -> begin
        s = leaf.selection
        s isa EmptyReferencePath && return @reference()
        s === nothing && return nothing
        map_reference_forward(p, nothing, s)
    end)
    tt = TextText(CellVector(() -> TextDocument[leaf.open, leaf.value, leaf.close]), sel)
    SimpleIoMap(p, leaf, tt)
end

function projection_read(p::SyntaxLeafToWidget, iomap::SimpleIoMap, op::ReplaceSelectionOperation)
    input_path = map_reference_backward(p, iomap, op.path)
    input_path === nothing && return nothing
    return ReplaceSelectionOperation(input_path)
end

# Translate a TextText-domain StringReplaceRangeOperation (referencing
# `.elements[2].content[s:e]`, the value span) back to a `.value[s:e]` op.
function projection_read(p::SyntaxLeafToWidget, iomap::SimpleIoMap, op::StringReplaceRangeOperation)
    parsed = _parse_text_elem_range(op.reference)
    parsed === nothing && return nothing
    span_idx, char_start, char_stop = parsed
    span_idx == 2 || return nothing
    new_ref = ConcreteReferencePath(FieldReference("value"),
                  ConcreteReferencePath(RangeReference(char_start, char_stop), EmptyReferencePath()))
    StringReplaceRangeOperation(new_ref, op.replacement)
end

# Pass KeyDown through so upstream projections can react (Backspace/Delete etc.).
projection_read(::SyntaxLeafToWidget, iomap::SimpleIoMap, evt::KeyDown) = evt
projection_read(::SyntaxLeafToWidget, iomap::SimpleIoMap, evt) = nothing

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
    TextText(CellVector(() -> TextDocument[TextString(s, font_dejavu_monospace_regular_24, color_solarized_gray)]),
             Cell(nothing))

function projection_print(p::SyntaxNodeToWidget, recursion, node::SyntaxNode, ctx)
    ref = ctx.reference
    # Delegate every child through the recursion (C1): each re-enters the
    # pipeline and is dispatched by its own type. Cache the iomaps so the toggle
    # reader can match the produced widgets and the layout reads each `.output`.
    child_ioms = Cell(() -> Any[
        projection_printer_recurse(recursion, node.children[i],
                                   child_context(ctx, @reference ^(ref).children[i]))
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

# Node-level structural selection display / backward mapping is deferred to leaf
# cursors (the embedded TextTexts carry the caret); the node maps nothing.
map_reference_forward(::SyntaxNodeToWidget, iomap, reference)  = nothing
map_reference_backward(::SyntaxNodeToWidget, iomap, reference) = nothing

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
function projection_read(::SyntaxNodeToWidget, iomap, op::ToggleCollapseOperation)
    op.target === nothing && return op
    node = _find_collapse_target(iomap, op.target)
    node === nothing ? op : ToggleCollapseOperation(node)
end

# Anything else (selection moves handled by leaves, scrolls, …) passes through.
projection_read(::SyntaxNodeToWidget, iomap, op) = op

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
