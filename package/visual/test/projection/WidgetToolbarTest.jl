# WidgetToolbar pointer routing. A toolbar lays its items out horizontally, so a
# crossing (MouseEnter/MouseLeave, synthesised by WidgetHoverTrackingProjection)
# must land on the item actually under the pointer. Regression guard: the item
# canvas used to be auto-sized (w=h=0), and since a GraphicsText has no right edge
# hit_element_at then let the leftmost item swallow every crossing — hover always
# lit the first button. Bounding the item canvas to its footprint fixes it.

using ProjecturedKernel.CellModule: Cell

function test_widget_toolbar()
@testset "WidgetToolbar pointer routing" begin

_det = (t, f) -> (length(t) * 8, 16)
proj = make_widget_projection_example(measure = _det)
_mods = ModifierKeys()
_unwrap(el) = el isa Cell ? el[] : el

# The bound item canvas: a lone menu item projects to a non-auto-sized canvas.
@testset "a menu item projects to a bounded canvas" begin
    c = print_document(proj, WidgetMenuItem("Save")).output
    @test c isa GraphicsCanvas
    @test Int(c.w[]) > 0 && Int(c.h[]) > 0
end

@testset "MouseEnter lands on the item under the pointer, not the first" begin
    labels = ["New", "Open", "Save", "Undo", "Redo"]
    tb = WidgetToolbar([WidgetMenuItem(l) for l in labels]; padding = Inset(4, 4, 4, 4))
    io = print_document(proj, tb)

    wrappers = GraphicsCanvas[]
    for el in io.output.elements
        el = _unwrap(el)
        el isa GraphicsCanvas && push!(wrappers, el)
    end
    sort!(wrappers, by = c -> Int(c.x))
    @test length(wrappers) == length(labels)

    # Route a crossing just inside each button; scan a few y offsets so the test
    # doesn't hard-code the item's vertical padding.
    hovered_at(c) = begin
        for dy in (4, 6, 8, 10, 12)
            g = MouseEnter(Int(c.x) + 6, Int(c.y) + dy, :none, _mods)
            ch = read_intent(proj, nothing, Intent(g, nothing), io)
            op = ch isa Intent ? ch.operation : ch
            op isa ReplaceReferencedValueOperation && return op.document.content
        end
        return nothing
    end
    for (i, c) in enumerate(wrappers)
        @test hovered_at(c) == labels[i]
    end
end

end # @testset
end # function
