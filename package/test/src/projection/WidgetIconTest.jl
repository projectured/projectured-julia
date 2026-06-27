# Icons (Stage 5). An icon is a *named* value resolved by a registry to a renderer
# with the uniform signature (elems, x, y, size, color); the widget printers draw it
# tinted to the label's foreground. v1 ships a built-in vector set (GraphicsPolyline);
# glyph-font (GraphicsText) and raster (GraphicsImage) backings register the same way.

using Projectured: GraphicsPolyline, GraphicsText, font_ubuntu_regular_24

# Collect every graphics primitive of type T in a canvas tree.
function _prims_of(canvas, ::Type{T}) where {T}
    out = T[]
    walk(c) = for el in c.elements
        el = el isa Projectured.ReactiveModule.Cell ? el[] : el
        el isa T && push!(out, el)
        el isa GraphicsCanvas && walk(el)
    end
    walk(canvas)
    out
end

function test_widget_icon()
@testset "Icons" begin

proj = make_widget_projection_example()
_btn(; kw...) = projection_print(proj, WidgetButton(Point2D(0, 0), Point2D(0, 0), "Save"; kw...)).output

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
    @test (en[1].r, en[1].g, en[1].b) != (di[1].r, di[1].g, di[1].b)   # different tint
end

@testset "a bound command's icon drives the button (Action.icon)" begin
    save = Action("Save"; icon = :save)
    b = projection_print(proj, WidgetButton(Point2D(0, 0), Point2D(0, 0), "Save"; command = save)).output
    @test !isempty(_prims_of(b, GraphicsPolyline))
end

@testset "a glyph-font icon registers and renders as text (pluggable backing)" begin
    register_icon!(:test_glyph_A, glyph_icon(font_ubuntu_regular_24, 'A'))
    b = _btn(icon = :test_glyph_A)
    @test "A" in [string(t.text) for t in _prims_of(b, GraphicsText)]
end

@testset "a menu item shows a leading icon" begin
    io = projection_print(proj, WidgetMenuItem("Save"; icon = :save)).output
    @test !isempty(_prims_of(io, GraphicsPolyline))
end

@testset "WidgetToolButton is an icon-first button" begin
    tb = WidgetToolButton(:save)
    @test tb isa WidgetButton
    @test tb.icon === :save
    @test !isempty(_prims_of(projection_print(proj, tb).output, GraphicsPolyline))
end

end # @testset
end # function
