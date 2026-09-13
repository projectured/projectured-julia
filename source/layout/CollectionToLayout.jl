# ──────────────────────────────────────────────────────────────────────────
# Folded in from CollectionToLayout.jl.
@projection struct CellVectorToVerticalLayout
    horizontal_align::Symbol = :left
    gap::Int = 8
end

function print_document(p::CellVectorToVerticalLayout, recursion, cv::CellVector, ctx)
    # Reuse the input's element cells (no transform here — the layout renderer
    # recurses them). The deferred-iomap trick wires the output selection.
    iomap_cell = Cell(nothing)
    sel = ComputedCell(() -> begin
        im = iomap_cell[]
        im === nothing && return nothing
        map_reference_forward(p, im, cv.selection)
    end)
    out = VerticalLayout(CellVector(getfield(cv, :elements), Cell(nothing)),
                         Cell(p.horizontal_align), Cell(p.gap),
                         Cell(nothing), Cell(nothing), sel)
    iomap = SimpleIoMap(p, cv, out)
    iomap_cell[] = iomap
    iomap
end

# [i] + rest  →  children[i] + rest
function map_reference_forward(::CellVectorToVerticalLayout, iomap, reference)
    reference === nothing && return nothing
    reference isa EmptyReference && return EmptyReference()
    reference isa ConcreteReference || return nothing
    h = reference.head
    (h isa RangeReferenceStep && is_element_reference_step(h)) || return nothing
    ConcreteReference(FieldReferenceStep("children"),
        ConcreteReference(h, reference.tail))
end

# children[i] + rest  →  [i] + rest
function map_reference_backward(::CellVectorToVerticalLayout, iomap, reference)
    reference === nothing && return nothing
    reference isa EmptyReference && return EmptyReference()
    reference isa ConcreteReference || return nothing
    h = reference.head
    (h isa FieldReferenceStep && h.name == "children") || return nothing
    t = reference.tail
    t isa ConcreteReference || return nothing
    h2 = t.head
    (h2 isa RangeReferenceStep && is_element_reference_step(h2)) || return nothing
    ConcreteReference(h2, t.tail)
end
