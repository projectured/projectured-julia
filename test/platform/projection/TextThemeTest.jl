# The text and the syntax follow the scales of the appearance. The natural
# renderer gives its text rows the scaled `TextTheme` and its syntax rows the
# scaled `SyntaxTheme` of its appearance: at a font scale of 1.5 a number, a
# string, an empty placeholder and a reflected object draw their text, and the
# whitespace of their layout, 1.5 times as large, the caret
# and the band of a selection follow the line and the radius scales, and a change
# of a scale reaches the next print. A projection built with no theme draws the
# values of the default theme.

"""
    collect_font_sizes(canvas) -> Vector{Int}

The size of the font of each text that the canvas tree `canvas` draws, in order.
"""
function collect_font_sizes(canvas)
    sizes = Int[]
    function walk(c)
        for element in c.elements
            element = element isa Cell ? element[] : element
            if element isa GraphicsCanvas
                walk(element)
            elseif element isa GraphicsViewport
                walk(element.content)
            elseif element isa GraphicsText
                push!(sizes, element.font.size)
            end
        end
    end
    walk(canvas)
    sizes
end

"""
    draw_font_sizes(document, appearance) -> Vector{Int}

The size of the font of each text that the natural renderer draws for `document`
with `appearance`, with a fixed measure in a box of 800 by 600. A domain test
compares the sizes at a font scale with those at no scale.
"""
draw_font_sizes(document, appearance::Appearance) =
    collect_font_sizes(print_document(NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0), appearance),
                                      nothing, document,
                                      PrinterContext(EmptyReference(), Cell(800), Cell(600),
                                                     Dict{Symbol,Any}())).output)

function test_text_and_syntax_themes()
@testset "the text and the syntax follow the scales of the appearance" begin

measure = FixedMeasure(8, 12, 4, 0)
offer = PrinterContext(EmptyReference(), Cell(800), Cell(600), Dict{Symbol,Any}())
drawn(appearance, document) = draw_font_sizes(document, appearance)

@testset "at a font scale of 1.5 the text is 1.5 times as large" begin
    # The last is a reflected object: its fields are indented, and the indentation
    # takes the font of its separators.
    for document in (PrimitiveNumber(42), PrimitiveString("text"), DocumentNothing(),
                     (name = "x", size = 2, inner = (flag = true,)))
        plain = drawn(Appearance(), document)
        large = drawn(Appearance(font_scale = 1.5), document)
        @test !isempty(plain) && length(large) == length(plain)
        @test large == round.(Int, plain .* 1.5)
    end
end

@testset "a change of the scale reaches the next print" begin
    appearance = Appearance()
    projection = NaturalToGraphics(; measure, appearance)
    document = PrimitiveNumber(42)
    print_size() = only(unique(collect_font_sizes(print_document(projection, nothing, document, offer).output)))
    @test print_size() == 14
    appearance.font_scale = 2.0
    @test print_size() == 28
end

@testset "the caret and the band of a selection follow the line and the radius scales" begin
    appearance = Appearance(line_scale = 2.0, radius_scale = 1.5)
    text = TextToGraphics(; measure, theme = get_scaled_theme!(appearance, TextTheme))
    @test (text.caret_width, text.highlight_radius) == (4, 6)
    appearance.line_scale = 1.0
    @test text.caret_width == 2
    plain = TextToGraphics(; measure)
    @test (plain.caret_width, plain.highlight_radius) == (2, 4)
    @test plain.caret_color == get_theme_defaults(TextTheme).caret
end

@testset "a syntax leaf with no theme has the default style, and with a theme its scaled one" begin
    @test PrimitiveNumberToSyntaxLeaf().style.font.size == 14
    theme = get_scaled_theme!(Appearance(font_scale = 1.5), SyntaxTheme)
    leaf = PrimitiveNumberToSyntaxLeaf(; theme)
    @test leaf.style.font.size == 21
    @test is_color_equal(leaf.style.color, get_theme_value(SyntaxTheme(), :number_text).color)
end

end
end
