# A split pane must follow its slot list. Every per-slot cell, child IoMap and
# canvas child is built for a count, so a slot added or removed only reaches the
# screen if the printer re-derives — and a test that asserts on the widget alone
# would never notice that it did not. These compare the **standing** render, read
# back through the IoMap the print returned, against a fresh print of the same
# widget: the two must agree, whatever the slot list has done since.
function test_widget_split_pane()
@testset "WidgetSplitPane reflow" begin

_stub(t, f) = (max(1, length(t)) * 10, 24)
_proj() = make_widget_projection_example(measure = _stub)
# The renderer without the chain around it, so a test can read the split pane's
# own IoMap rather than the chain's.
_direct() = RecursiveProjection(TypeDispatchingProjection(vcat(
    LayoutToGraphics().dispatch,
    WidgetToGraphics(font_ubuntu_regular_20; measure = _stub).dispatch)))
_label(text) = WidgetLabel(text)

# The whole drawn tree as a string, viewports included.
function shape(node, depth = 0)
    depth > 8 && return "…"
    if node isa GraphicsCanvas
        return "C[" * join([shape(e, depth + 1) for e in node.elements], ",") * "]"
    elseif node isa GraphicsViewport
        return "V(" * shape(node.content, depth + 1) * ")"
    end
    string(nameof(typeof(node)))
end

# Print once, then assert the standing render keeps up with whatever `edit!` does.
function _follows(pane, edit!)
    projection = _proj()
    standing = print_document(projection, pane)
    edit!(pane)
    shape(standing.output) == shape(print_document(projection, pane).output)
end

@testset "a slot added reaches the standing render" begin
    pane = WidgetSplitPane(:horizontal, Any[_label("one"), _label("two")])
    @test _follows(pane, p -> push!(p.elements, _label("three")))
end

@testset "a slot removed reaches it too" begin
    pane = WidgetSplitPane(:horizontal, Any[_label("one"), _label("two"), _label("three")])
    @test _follows(pane, p -> deleteat!(p.elements, 2))
end

@testset "a stacked split follows the same way" begin
    pane = WidgetSplitPane(:vertical, Any[_label("top"), _label("bottom")])
    @test _follows(pane, p -> push!(p.elements, _label("third")))
end

@testset "the last slot leaving empties the pane" begin
    pane = WidgetSplitPane(:horizontal, Any[_label("only"), _label("other")])
    @test _follows(pane, p -> (deleteat!(p.elements, 2); deleteat!(p.elements, 1)))
end

@testset "the reader routes to the slots that are there now" begin
    # The child IoMaps the reader routes through come from the same build, so a
    # click must reach a slot that was added after the print.
    pane = WidgetSplitPane(:horizontal, Any[_label("one"), _label("two")])
    standing = print_document(_direct(), pane)
    push!(pane.elements, WidgetButton("press"; size = Point2D(60, 24)))

    entries = getfield(standing, :child_iomaps)[]
    @test length(entries) == 3
    # The third slot sits past the first two, which is only true if the positions
    # were re-derived as well.
    @test Int(entries[3][1][]) > Int(entries[2][1][]) > Int(entries[1][1][])
end

@testset "a slot change keeps the same IoMap" begin
    # The IoMap object survives — it is the standing one the editor holds. Only
    # what it answers changes.
    pane = WidgetSplitPane(:horizontal, Any[_label("one"), _label("two")])
    standing = print_document(_direct(), pane)
    before = objectid(standing)
    push!(pane.elements, _label("three"))
    @test length(getfield(standing, :child_iomaps)[]) == 3
    @test objectid(standing) == before
end

# Every rectangle a print produced. The splitter is the only one a split of two
# labels draws, so this reads it back.
function _rects(node, acc = Tuple{Int,Int,Int,Int}[])
    if node isa GraphicsRect
        push!(acc, (Int(node.x[]), Int(node.y[]), Int(node.w[]), Int(node.h[])))
    elseif node isa GraphicsCanvas
        for e in node.elements; _rects(e, acc); end
    elseif node isa GraphicsViewport
        _rects(node.content, acc)
    end
    acc
end

# Print into a stated offer, which is the extent a split has to divide.
function _offered(pane, width, height)
    ctx = PrinterContext(EmptyReference(), Cell(width), Cell(height), Dict{Symbol,Any}())
    print_document(_proj(), nothing, pane, ctx)
end

_pair() = Any[_label("one"), _label("two")]
_INSET = Inset(8, 8, 8, 8)

@testset "a bordered split stays inside the size it reports" begin
    # A split divides the space inside its own box model. It used to lay its
    # children out from the content offset and still divide the whole offer, so
    # the last slot and the splitter ran past the far edge by the inset, and the
    # canvas claimed a size smaller than it drew.
    plain = _offered(WidgetSplitPane(:horizontal, _pair()), 400, 300)
    inset = _offered(WidgetSplitPane(:horizontal, _pair(); border = _INSET), 400, 300)

    px, py, pw, ph = only(_rects(plain.output))
    ix, iy, iw, ih = only(_rects(inset.output))
    @test (px, py) == (0, 0)
    @test ph == 300                          # the whole offer, with nothing taken
    @test (ix, iy) == (8, 8)                 # the splitter starts inside the inset
    @test ih == ph - 16                      # and it ends inside it
    @test iw == pw

    # The size the parent sees is the content plus the box model, so the cross
    # axis still fills the offer.
    @test Int(inset.output.w[]) == Int(plain.output.w[]) + 16
    @test Int(inset.output.h[]) == Int(plain.output.h[])
end

@testset "a stacked bordered split does the same on its own axis" begin
    plain = _offered(WidgetSplitPane(:vertical, _pair()), 400, 300)
    inset = _offered(WidgetSplitPane(:vertical, _pair(); border = _INSET), 400, 300)

    px, py, pw, ph = only(_rects(plain.output))
    ix, iy, iw, ih = only(_rects(inset.output))
    @test (px, py) == (0, 0)
    @test pw == 400
    @test (ix, iy) == (8, 8)
    @test iw == pw - 16
    @test ih == ph
    @test Int(inset.output.h[]) == Int(plain.output.h[]) + 16
    @test Int(inset.output.w[]) == Int(plain.output.w[])
end

end # testset
end # function
