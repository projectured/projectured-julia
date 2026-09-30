# Icons. An icon is a *named* value resolved by a registry to a renderer with the
# uniform signature (elems, x, y, size, color); the widget printers draw it tinted
# to the label's foreground. Every built-in icon is a glyph of the Lucide icon
# font, drawn as a `GraphicsText` at the size of its box; a raster backing
# (GraphicsImage) registers the same way.


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

_icon_value(v) = v isa CellModule.Cell ? v[] : v

# The texts a canvas draws in the icon font, and the character of an icon name.
_is_icon_glyph(t) = endswith(_icon_value(t.font).filename, "lucide.ttf")
_glyphs_of(canvas) = [String(string(_icon_value(t.text)))
                      for t in _prims_of(canvas, GraphicsText) if _is_icon_glyph(t)]
_glyph(name) = string(find_icon_character(name))

function test_widget_icon()
@testset "Icons" begin

proj = make_widget_projection_example()
_btn(; kw...) = print_document(proj, WidgetButton("Save"; kw...)).output

@testset "a built-in icon is a glyph of the icon font, and it widens the button" begin
    plain  = _btn()
    iconed = _btn(icon = :save)
    @test isempty(_glyphs_of(plain))                       # no icon ⇒ no glyph
    @test _glyphs_of(iconed) == [_glyph(:save)]            # one glyph, the right one
    @test Int(iconed.w[]) > Int(plain.w[])                 # icon + gap widens it
end

@testset "an unknown icon name is a no-op (no draw, no width)" begin
    plain = _btn()
    none  = _btn(icon = :no_such_icon)
    @test isempty(_glyphs_of(none))
    @test Int(none.w[]) == Int(plain.w[])
end

@testset "a disabled button tints its icon with the muted color" begin
    glyph(canvas) = only(t for t in _prims_of(canvas, GraphicsText) if _is_icon_glyph(t))
    ec = _icon_value(glyph(_btn(icon = :save)).color)
    dc = _icon_value(glyph(_btn(icon = :save, enabled = false)).color)
    @test (ec.red, ec.green, ec.blue) != (dc.red, dc.green, dc.blue)   # different tint
end

@testset "a bound command's icon drives the button (Action.icon)" begin
    save = Action("Save"; icon = :save)
    b = print_document(proj, WidgetButton(save)).output
    @test _glyphs_of(b) == [_glyph(:save)]
end

@testset "a glyph-font icon is drawn at the size of its box" begin
    register_icon!(:test_glyph_A, make_glyph_icon(font_ubuntu_regular_20, 'A'))
    b = _btn(icon = :test_glyph_A)
    @test "A" in [string(_icon_value(t.text)) for t in _prims_of(b, GraphicsText)]
    # The font names a size; the box decides it.
    elements = Any[]
    make_glyph_icon(font_ubuntu_regular_20, 'A')(elements, 3, 4, 37, StyleColor(0.0, 0.0, 0.0, 1.0))
    t = only(elements)
    @test (Int(_icon_value(t.x)), Int(_icon_value(t.y))) == (3, 4)
    @test _icon_value(t.font).size == 37
    @test _icon_value(t.font).filename == font_ubuntu_regular_20.filename
end

@testset "a menu item shows a leading icon" begin
    io = print_document(proj, WidgetMenuItem("Save"; icon = :save)).output
    @test _glyphs_of(io) == [_glyph(:save)]
end

@testset "WidgetToolButton is an icon-first button" begin
    tb = WidgetToolButton(:save)
    @test tb isa WidgetButton
    @test tb.action.icon === :save
    @test _glyphs_of(print_document(proj, tb).output) == [_glyph(:save)]
end

@testset "a tabbed pane draws an icon on a 3-tuple tab" begin
    plain = print_document(proj, WidgetTabbedPane([("A", WidgetLabel("x")),
                                                     ("B", WidgetLabel("y"))])).output
    iconed = print_document(proj, WidgetTabbedPane([("A", WidgetLabel("x"), :folder),
                                                      ("B", WidgetLabel("y"))])).output
    @test !(_glyph(:folder) in _glyphs_of(plain))          # icon-less tabs
    @test _glyph(:folder) in _glyphs_of(iconed)            # the :folder tab icon
end

@testset "the icons of a run are glyphs, one each, and they differ" begin
    names = (:play, :pause, :stop, :step_forward, :finish, :fast_forward, :chevrons_right,
             :skip_forward)
    for name in names
        @test _glyphs_of(_btn(icon = name)) == [_glyph(name)]
    end
    @test length(unique(_glyph(name) for name in names)) == length(names)
    # The glyph tints like text: a disabled button mutes it.
    glyph(canvas) = only(t for t in _prims_of(canvas, GraphicsText) if _is_icon_glyph(t))
    ec = _icon_value(glyph(_btn(icon = :play)).color)
    dc = _icon_value(glyph(_btn(icon = :play, enabled = false)).color)
    @test (ec.red, ec.green, ec.blue) != (dc.red, dc.green, dc.blue)
end

@testset "every built-in icon is a glyph the icon font has, drawn in its box" begin
    registry = ProjecturedWidget.WidgetModule.ICON_REGISTRY
    font = load_truetype_font(font_lucide_icons_20.filename)
    color = StyleColor(0.1, 0.2, 0.3, 1.0)
    for (name, codepoint) in ProjecturedWidget.WidgetModule.LUCIDE_ICON_GLYPHS
        # A code point the font does not have draws nothing, or a box.
        @test get_glyph_id(font, UInt32(codepoint)) != 0
        @test find_icon_character(name) == Char(codepoint)
        elements = Any[]
        registry[name](elements, 5, 6, 24, color)
        t = only(elements)
        @test t isa GraphicsText
        @test string(_icon_value(t.text)) == string(Char(codepoint))
        @test (Int(_icon_value(t.x)), Int(_icon_value(t.y))) == (5, 6)
        @test _icon_value(t.font).size == 24
    end
    @test find_icon_character(:no_such_icon) === nothing
end

@testset "a label with a font of its own writes an icon in the theme's color" begin
    plain = only(_prims_of(print_document(proj, WidgetLabel("x")).output, GraphicsText))
    icon = only(_prims_of(print_document(proj, WidgetLabel(_glyph(:loader);
                                                           text_style = font_lucide_icons_20)).output,
                          GraphicsText))
    @test _is_icon_glyph(icon)
    @test string(_icon_value(icon.text)) == _glyph(:loader)
    pc, ic = _icon_value(plain.color), _icon_value(icon.color)
    @test (pc.red, pc.green, pc.blue, pc.alpha) == (ic.red, ic.green, ic.blue, ic.alpha)
end

@testset "a tree node draws its registered icon" begin
    tr = WidgetTree(Any[
        WidgetTreeNode(:folder, "src", Any[WidgetTreeNode(:file, "a.jl")]),
    ]; expanded = Set([[1]]))
    canvas = print_document(proj, tr).output
    glyphs = _glyphs_of(canvas)
    @test _glyph(:folder) in glyphs && _glyph(:file) in glyphs
    # A named icon is as tall as a line, and the label starts after it and a gap.
    texts = _prims_of(canvas, GraphicsText)
    folder = only(t for t in texts if string(_icon_value(t.text)) == _glyph(:folder))
    src = only(t for t in texts if string(_icon_value(t.text)) == "src")
    @test Int(_icon_value(src.x)) > Int(_icon_value(folder.x)) + _icon_value(folder.font).size
    # An icon-less tree (bare tuple form) draws no icon of a node.
    tuple_tree = WidgetTree(Any[("src", Any["a.jl"])])
    glyphs = _glyphs_of(print_document(proj, tuple_tree).output)
    @test !(_glyph(:folder) in glyphs) && !(_glyph(:file) in glyphs)
end

end # @testset
end # function
