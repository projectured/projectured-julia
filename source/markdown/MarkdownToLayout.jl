"""
    MarkdownToLayoutModule

`MarkdownRoot → VerticalLayout` — the structural rewrap that makes a
markdown page a **stack of blocks** instead of one syntax tree, so each
block renders in its own domain.

That distinction only matters because of embeds. A page's elements are
mostly markdown, which renders through the to-syntax fabric either way;
but an embedded document may belong to a domain that is *not*
syntax-producible — a live simulation card is a widget, and a widget
squeezed through a syntax tree would arrive as reflected text, and (the
part that matters) would never see a click. Stacking the page's elements
as layout children lets the surrounding renderer recurse each one by
type: prose to prose, JSON to JSON, a widget to the widget renderer.

The rewrap does not transform its children (the element subtrees are
identical on both sides, just moved), so the reference maps only
relocate the head: `elements[i] + rest ↔ children[i] + rest`. This
mirrors `CellVectorToVerticalLayout`, which does the same for a bare
collection.
"""
module MarkdownToLayoutModule

import ..CellModule: Cell, ComputedCell
import ..CollectionModule: CellVector
import ..LayoutModule: VerticalLayout
import ..ProjectionApiModule: print_document, map_reference_forward, map_reference_backward,
                              read_intent, Projection
import ..ProjectionModule: var"@projection"
import ..IoMapModule: SimpleIoMap
import ..MarkdownModule: MarkdownRoot
import ..WidgetModule: InvokeActionOperation
import ..OperationModule: ReplaceSelectionOperation
import ..ReferenceModule: ConcreteReference, FieldReferenceStep, RangeReferenceStep,
                          EmptyReference, is_element_reference_step

export MarkdownRootToVerticalLayout

@projection struct MarkdownRootToVerticalLayout
    horizontal_align::Symbol = :left
    gap::Int = 8
end

function print_document(p::MarkdownRootToVerticalLayout, recursion, root::MarkdownRoot, ctx)
    iomap_cell = Cell(nothing)
    sel = ComputedCell(() -> begin
        iomap = iomap_cell[]
        iomap === nothing && return nothing
        map_reference_forward(p, iomap, root.selection)
    end)
    # The page's own element cells are reused, not copied: the layout's
    # children share the root's element storage (only the selection cell is
    # the layout's own), and the layout renderer recurses each element.
    elements = root.elements::CellVector
    out = VerticalLayout(CellVector(getfield(elements, :elements), Cell(nothing)),
                         Cell(p.horizontal_align), Cell(p.gap),
                         Cell(nothing), Cell(nothing), sel)
    iomap = SimpleIoMap(p, root, out)
    iomap_cell[] = iomap
    iomap
end

# elements[i] + rest  →  children[i] + rest
function map_reference_forward(::MarkdownRootToVerticalLayout, iomap, reference)
    reference === nothing && return nothing
    reference isa EmptyReference && return EmptyReference()
    reference isa ConcreteReference || return nothing
    h = reference.head
    (h isa FieldReferenceStep && h.name == "elements") || return nothing
    t = reference.tail
    t isa ConcreteReference || return nothing
    (t.head isa RangeReferenceStep && is_element_reference_step(t.head)) || return nothing
    ConcreteReference(FieldReferenceStep("children"), t)
end

# children[i] + rest  →  elements[i] + rest
function map_reference_backward(::MarkdownRootToVerticalLayout, iomap, reference)
    reference === nothing && return nothing
    reference isa EmptyReference && return EmptyReference()
    reference isa ConcreteReference || return nothing
    h = reference.head
    (h isa FieldReferenceStep && h.name == "children") || return nothing
    t = reference.tail
    t isa ConcreteReference || return nothing
    (t.head isa RangeReferenceStep && is_element_reference_step(t.head)) || return nothing
    ConcreteReference(FieldReferenceStep("elements"), t)
end

# The whole point of the rewrap is that a page's embedded card is a real widget
# whose controls can be clicked — so this projection is the one that has to pass
# their activations on. An `InvokeActionOperation` names its own `Action` and
# needs no re-rooting, but the generic reader returns `nothing` for every
# operation type it does not recognise, which is where a card's Run button used
# to die: it rendered, took the press, answered, and the answer stopped here.
read_intent(::MarkdownRootToVerticalLayout, iomap, op::InvokeActionOperation) = op

# And the same for a click that lands IN an embedded card rather than on one of
# its buttons. A card that takes the keyboard — a conversation, a form — needs
# the caret to arrive, and the caret arrives as a selection naming a child of
# this layout. Re-rooted here into the page's own elements, exactly as
# `map_reference_backward` does for any other reference; without this the click
# died where the Run button used to, and every key went to the prose above.
function read_intent(p::MarkdownRootToVerticalLayout, iomap, op::ReplaceSelectionOperation)
    inner = map_reference_backward(p, iomap, op.path)
    inner === nothing ? nothing : ReplaceSelectionOperation(inner)
end

# ── Natural-projection registration ─────────────────────────────────────────
# A markdown page is a stack of blocks, not one syntax tree, so each element
# re-enters the natural renderer in its own domain. Prose still goes to the
# syntax fabric; an embed whose document is a widget (a live simulation card)
# reaches the widget renderer and can be clicked, which a syntax tree could
# never offer it.
import ..ChainingProjectionModule: ChainingProjection
import ..LayoutToGraphicsModule: VerticalLayoutToGraphicsCanvas
import ..NaturalRegistryModule: register_natural_graphics!

function __init__()
    register_natural_graphics!(:markdown_page, (; measure) -> Pair{Type,Any}[
        MarkdownRoot => ChainingProjection(MarkdownRootToVerticalLayout(),
                                           VerticalLayoutToGraphicsCanvas()),
    ])
end

end # module MarkdownToLayoutModule
