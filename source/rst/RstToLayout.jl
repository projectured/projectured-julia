"""
    RstToLayoutModule

`RstRoot` / `RstSection` → `VerticalLayout` — the structural rewrap that
makes an RST page a **stack of blocks** instead of one syntax tree, so
each block renders in its own domain.

It exists for the same reason `MarkdownToLayoutModule` does: an embedded
document may belong to a domain that is *not* syntax-producible. A card
around an embed is a widget, and a widget squeezed through a syntax tree
would arrive as reflected text and would never see a click.

RST needs one more rule than markdown does. A markdown page is flat — its
headings are elements of the root — so rewrapping the root is enough. An
RST section **owns** its blocks, so a root rewrap alone would leave every
embed below the first title inside a syntax tree. `RstSectionToVerticalLayout`
therefore stacks a section too: its title over its blocks.

The rewrap does not transform the blocks (the subtrees are identical on
both sides, just moved), so the reference maps only relocate the head.

**The title is flat.** A section's title renders as one prose line in the
title font, with whatever inline markup it carries flattened to its text.
A selection therefore maps through a section's *blocks* but not into its
title — which is what the syntax rule offers as well, and strictly less
than the source view, where the whole section maps.
"""
module RstToLayoutModule

import ..CellModule: Cell, ComputedCell
import ..CollectionModule: CellVector, ComputedCellVector
import ..LayoutModule: VerticalLayout
import ..ProjectionApiModule: print_document, map_reference_forward, map_reference_backward,
                              read_intent, Projection
import ..ProjectionModule: var"@projection"
import ..IoMapModule: SimpleIoMap
import ..RstModule: RstRoot, RstSection, RstText, RstLiteral, RstRole, RstStrong, RstEmphasis
import ..RstToSyntaxModule: _title_font, _TITLE_COLOR
import ..TextModule: TextBlock, TextString
import ..StyleTextModule: StyleText
import ..WidgetModule: InvokeActionOperation
import ..ReferenceModule: ConcreteReference, FieldReferenceStep, RangeReferenceStep,
                          EmptyReference, is_element_reference_step

export RstRootToVerticalLayout, RstSectionToVerticalLayout

# ── RstRootToVerticalLayout ────────────────────────────────────────────────

@projection struct RstRootToVerticalLayout
    horizontal_align::Symbol = :left
    gap::Int = 8
end

function print_document(p::RstRootToVerticalLayout, recursion, root::RstRoot, ctx)
    iomap_cell = Cell(nothing)
    sel = ComputedCell(() -> begin
        iomap = iomap_cell[]
        iomap === nothing && return nothing
        map_reference_forward(p, iomap, root.selection)
    end)
    # The page's own element cells are reused, not copied: the layout's children
    # share the root's element storage, and the layout renderer recurses each one.
    elements = root.elements::CellVector
    out = VerticalLayout(CellVector(getfield(elements, :elements), Cell(nothing)),
                         Cell(p.horizontal_align), Cell(p.gap),
                         Cell(nothing), Cell(nothing), sel)
    iomap = SimpleIoMap(p, root, out)
    iomap_cell[] = iomap
    iomap
end

map_reference_forward(::RstRootToVerticalLayout, iomap, reference) =
    _relocate_head(reference, "elements", "children")
map_reference_backward(::RstRootToVerticalLayout, iomap, reference) =
    _relocate_head(reference, "children", "elements")

# ── RstSectionToVerticalLayout ─────────────────────────────────────────────

@projection struct RstSectionToVerticalLayout
    horizontal_align::Symbol = :left
    gap::Int = 8
end

function print_document(p::RstSectionToVerticalLayout, recursion, section::RstSection, ctx)
    iomap_cell = Cell(nothing)
    sel = ComputedCell(() -> begin
        iomap = iomap_cell[]
        iomap === nothing && return nothing
        map_reference_forward(p, iomap, section.selection)
    end)
    # The title line, then the section's own blocks — which keep their cells, so
    # each block renders in its own domain and an embed reaches the widget
    # renderer. The title is rebuilt reactively: editing it re-renders the line.
    children = ComputedCellVector(() -> begin
        stack = Any[_title_block(section)]
        append!(stack, collect(section.elements))
        stack
    end)
    out = VerticalLayout(children, Cell(p.horizontal_align), Cell(p.gap),
                         Cell(nothing), Cell(nothing), sel)
    iomap = SimpleIoMap(p, section, out)
    iomap_cell[] = iomap
    iomap
end

# The title as one prose line in the level's font.
_title_block(section::RstSection) =
    TextBlock([TextString(_title_text(section),
                          StyleText(_title_font(section.level), _TITLE_COLOR))])

function _title_text(section::RstSection)
    buffer = IOBuffer()
    _title_runs!(buffer, section.title)
    String(take!(buffer))
end

_title_runs!(buffer::IO, nodes) = (foreach(n -> _title_run!(buffer, n), nodes); nothing)
_title_run!(buffer::IO, node::RstText)     = (print(buffer, node.content); nothing)
_title_run!(buffer::IO, node::RstLiteral)  = (print(buffer, node.content); nothing)
_title_run!(buffer::IO, node::RstRole)     = (print(buffer, node.content); nothing)
_title_run!(buffer::IO, node::RstStrong)   = _title_runs!(buffer, node.content)
_title_run!(buffer::IO, node::RstEmphasis) = _title_runs!(buffer, node.content)
_title_run!(::IO, ::Any) = nothing

# The title takes the first slot, so a block sits one further along than it does
# in the section. A path into the title itself has no image: the line is flat.
map_reference_forward(::RstSectionToVerticalLayout, iomap, reference) =
    _relocate_head(reference, "elements", "children"; shift = 1)
map_reference_backward(::RstSectionToVerticalLayout, iomap, reference) =
    _relocate_head(reference, "children", "elements"; shift = -1)

# ── The shared head relocation ─────────────────────────────────────────────

# `from[i] + rest` → `to[i + shift] + rest`. Everything below the head is
# carried unchanged, because the rewrap moves the blocks without touching them.
function _relocate_head(reference, from::String, to::String; shift::Int = 0)
    reference === nothing && return nothing
    reference isa EmptyReference && return EmptyReference()
    reference isa ConcreteReference || return nothing
    head = reference.head
    (head isa FieldReferenceStep && head.name == from) || return nothing
    tail = reference.tail
    tail isa ConcreteReference || return nothing
    step = tail.head
    (step isa RangeReferenceStep && is_element_reference_step(step)) || return nothing
    index = step.start + shift
    index >= 0 || return nothing
    ConcreteReference(FieldReferenceStep(to),
                      ConcreteReference(RangeReferenceStep(index, index + 1), tail.tail))
end

# A card inside a page is a real widget whose header and controls can be pressed,
# so these two rules have to pass an activation on. An `InvokeActionOperation`
# names its own `Action` and needs no re-rooting, but the generic reader answers
# nothing for an operation type it does not recognise, which is where a card's
# button would die.
read_intent(::RstRootToVerticalLayout, iomap, op::InvokeActionOperation) = op
read_intent(::RstSectionToVerticalLayout, iomap, op::InvokeActionOperation) = op

# ── Natural-projection registration ─────────────────────────────────────────
# An RST page is a stack of blocks, for the reason a markdown page is. It takes
# two rows where markdown takes one: an RST section OWNS its blocks, so a root
# rewrap alone would leave every embed below the first title inside a syntax
# tree, where a card could not go.
import ..ChainingProjectionModule: ChainingProjection
import ..LayoutToGraphicsModule: VerticalLayoutToGraphicsCanvas
import ..NaturalModule: register_natural_graphics!

function __init__()
    register_natural_graphics!(:rst_page, (; measure) -> Pair{Type,Any}[
        RstRoot    => ChainingProjection(RstRootToVerticalLayout(),
                                         VerticalLayoutToGraphicsCanvas()),
        RstSection => ChainingProjection(RstSectionToVerticalLayout(),
                                         VerticalLayoutToGraphicsCanvas()),
    ])
end

end # module RstToLayoutModule
