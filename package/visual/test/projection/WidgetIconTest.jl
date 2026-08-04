# Icons (Stage 5). An icon is a *named* value resolved by a registry to a renderer
# with the uniform signature (elems, x, y, size, color); the widget printers draw it
# tinted to the label's foreground. v1 ships a built-in vector set (GraphicsPolyline);
# glyph-font (GraphicsText) and raster (GraphicsImage) backings register the same way.


# Collect every graphics primitive of type T in a canvas tree, descending into both
# nested canvases and viewports (the tab strip lives inside a GraphicsViewport).
function _prims_of(canvas, ::Type{T}) where {T}
    out = T[]
    walk(c) = for el in c.elements
        el = el isa CellModule.Cell ? el[] : el
        el isa T && push!(out, el)
        el isa GraphicsCanvas && walk(el)
        el isa GraphicsViewport && walk(el.content)
    end
    walk(canvas)
    out
end

function test_widget_icon()
@testset "Icons" begin

proj = make_widget_projection_example()
_btn(; kw...) = print_document(proj, WidgetButton(Point2D(0, 0), Point2D(0, 0), "Save"; kw...)).output

@testset "a built-in vector icon renders as tinted polylines and widens the button" begin
    plain  = _btn()
    iconed = _btn(icon = :save)
    @test isempty(_prims_of(plain, GraphicsPolyline))      # no icon ⇒ no polylines
    @test !isempty(_prims_of(iconed, GraphicsPolyline))    # :save draws polylines
    @test Int(iconed.w[]) > Int(plain.w[])                 # icon + gap widens it
end

@testset "an unknown icon name is a no-op (no draw, no width)" begin
    plain = _btn()
    none  = _btn(icon = :no_such_icon)
    @test isempty(_prims_of(none, GraphicsPolyline))
    @test Int(none.w[]) == Int(plain.w[])
end

@testset "a disabled button tints its icon with the muted color" begin
    en = _prims_of(_btn(icon = :save), GraphicsPolyline)
    di = _prims_of(_btn(icon = :save, enabled = false), GraphicsPolyline)
    @test !isempty(en) && !isempty(di)
    ec, dc = en[1].color, di[1].color
    @test (ec.red, ec.green, ec.blue) != (dc.red, dc.green, dc.blue)   # different tint
end

@testset "a bound command's icon drives the button (Action.icon)" begin
    save = Action("Save"; icon = :save)
    b = print_document(proj, WidgetButton(Point2D(0, 0), Point2D(0, 0), "Save"; command = save)).output
    @test !isempty(_prims_of(b, GraphicsPolyline))
end

@testset "a glyph-font icon registers and renders as text (pluggable backing)" begin
    register_icon!(:test_glyph_A, glyph_icon(font_ubuntu_regular_20, 'A'))
    b = _btn(icon = :test_glyph_A)
    @test "A" in [string(t.text) for t in _prims_of(b, GraphicsText)]
end

@testset "a menu item shows a leading icon" begin
    io = print_document(proj, WidgetMenuItem("Save"; icon = :save)).output
    @test !isempty(_prims_of(io, GraphicsPolyline))
end

@testset "WidgetToolButton is an icon-first button" begin
    tb = WidgetToolButton(:save)
    @test tb isa WidgetButton
    @test tb.icon === :save
    @test !isempty(_prims_of(print_document(proj, tb).output, GraphicsPolyline))
end

@testset "a tabbed pane draws an icon on a 3-tuple tab" begin
    plain = print_document(proj, WidgetTabbedPane([("A", WidgetLabel(Point2D(0,0), "x")),
                                                     ("B", WidgetLabel(Point2D(0,0), "y"))])).output
    iconed = print_document(proj, WidgetTabbedPane([("A", WidgetLabel(Point2D(0,0), "x"), :folder),
                                                      ("B", WidgetLabel(Point2D(0,0), "y"))])).output
    @test isempty(_prims_of(plain, GraphicsPolyline))      # icon-less tabs
    @test !isempty(_prims_of(iconed, GraphicsPolyline))    # the :folder tab icon
end

@testset "media-transport icons render as filled polygons" begin
    for name in (:play, :pause, :stop, :step_forward, :step, :finish)
        @test !isempty(_prims_of(_btn(icon = name), GraphicsPolygon))
    end
    @test length(_prims_of(_btn(icon = :play),  GraphicsPolygon)) == 1   # one triangle
    @test length(_prims_of(_btn(icon = :pause), GraphicsPolygon)) == 2   # two bars
    # The fill tints like a stroke: a disabled button mutes it.
    en = _prims_of(_btn(icon = :play), GraphicsPolygon)
    di = _prims_of(_btn(icon = :play, enabled = false), GraphicsPolygon)
    ec, dc = en[1].color, di[1].color
    @test (ec.red, ec.green, ec.blue) != (dc.red, dc.green, dc.blue)
end

@testset "a tree node draws its registered icon (chevrons are lines, not polylines)" begin
    tr = WidgetTree(Point2D(0, 0), Any[
        WidgetTreeNode(:folder, "src", Any[WidgetTreeNode(:file, "a.jl")]),
    ])
    @test !isempty(_prims_of(print_document(proj, tr).output, GraphicsPolyline))
    # An icon-less tree (bare tuple form) draws no icon polylines.
    tuple_tree = WidgetTree(Point2D(0, 0), Any[("src", Any["a.jl"])])
    @test isempty(_prims_of(print_document(proj, tuple_tree).output, GraphicsPolyline))
end

end # @testset
end # function
