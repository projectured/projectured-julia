"""
    CollectionToLayoutModule

`CellVector → VerticalLayout` — a structural rewrap so a collection renders as a
stack of independent graphics blocks rather than collapsing to one syntax tree.

`CellVectorToVerticalLayout` relocates the collection's elements under the
layout's `children` field **without transforming them** (the element subtrees are
identical on both sides, just moved). Paired with `VerticalLayoutToGraphicsCanvas`
in a `ChainingProjection`, the layout renderer then recurses each element
through the surrounding `recursion` (the natural renderer), so every element is
rendered in its *own* domain — prose as prose, JSON as JSON, a widget as a
widget — instead of every element being forced through the to-syntax fabric.
This is what lets a `CellVector` of mixed content (including `TextBlock`) render
naturally; see the natural-projection plan.

Because the rewrap does not recurse, the reference maps only relocate the head:
`[i] + rest ↔ children[i] + rest`. The `rest` (the element subtree path) is
unchanged and is mapped later by the layout renderer's own child IO maps.
"""
module CollectionToLayoutModule

import ..CellModule: Cell
import ..CollectionModule: CellVector
import ..LayoutModule: VerticalLayout
import ..ProjectionApiModule: print_document, map_reference_forward, map_reference_backward, Projection
import ..ProjectionModule: var"@projection"
import ..IoMapModule: SimpleIoMap
import ..ReferenceModule: ConcreteReferencePath, FieldReferenceStep, RangeReferenceStep,
                          EmptyReferencePath, is_element_reference_step

export CellVectorToVerticalLayout

@projection struct CellVectorToVerticalLayout
    horizontal_align::Symbol = :left
    gap::Int = 8
end

function print_document(p::CellVectorToVerticalLayout, recursion, cv::CellVector, ctx)
    # Reuse the input's element cells (no transform here — the layout renderer
    # recurses them). The deferred-iomap trick wires the output selection.
    iomap_cell = Cell(nothing)
    sel = Cell(() -> begin
        im = iomap_cell[]
        im === nothing && return nothing
        map_reference_forward(p, im, cv.selection)
    end)
    out = VerticalLayout(CellVector(getfield(cv, :elements), Cell(nothing)),
                         Cell(p.horizontal_align), Cell(p.gap), sel)
    iomap = SimpleIoMap(p, cv, out)
    iomap_cell[] = iomap
    iomap
end

# [i] + rest  →  children[i] + rest
function map_reference_forward(::CellVectorToVerticalLayout, iomap, reference)
    reference === nothing && return nothing
    reference isa EmptyReferencePath && return EmptyReferencePath()
    reference isa ConcreteReferencePath || return nothing
    h = reference.head
    (h isa RangeReferenceStep && is_element_reference_step(h)) || return nothing
    ConcreteReferencePath(FieldReferenceStep("children"),
        ConcreteReferencePath(h, reference.tail))
end

# children[i] + rest  →  [i] + rest
function map_reference_backward(::CellVectorToVerticalLayout, iomap, reference)
    reference === nothing && return nothing
    reference isa EmptyReferencePath && return EmptyReferencePath()
    reference isa ConcreteReferencePath || return nothing
    h = reference.head
    (h isa FieldReferenceStep && h.name == "children") || return nothing
    t = reference.tail
    t isa ConcreteReferencePath || return nothing
    h2 = t.head
    (h2 isa RangeReferenceStep && is_element_reference_step(h2)) || return nothing
    ConcreteReferencePath(h2, t.tail)
end

end # module
