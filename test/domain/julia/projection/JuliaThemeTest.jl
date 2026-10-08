# The Julia syntax follows the scales of the appearance: the natural renderer gives
# the Julia projections the scaled `JuliaTheme` of its appearance, so at a font scale
# of 1.5 every text of a Julia document is 1.5 times as large, and a Julia
# projection that a builder gives no style has the default styles.

function test_julia_theme()
@testset "the Julia syntax follows the scales of the appearance" begin
    document = parse_julia("function f(x)\n    y = g(x, 2.5, \"s\", true, nothing, :sym)\n    y.z\nend")
    plain = draw_font_sizes(document, Appearance())
    @test !isempty(plain)
    @test draw_font_sizes(document, Appearance(font_scale = 1.5)) == round.(Int, plain .* 1.5)
    @test JuliaIntegerToSyntaxLeaf().style.font.size == 14
    theme = get_scaled_theme!(Appearance(font_scale = 1.5), JuliaTheme)
    leaf = JuliaIntegerToSyntaxLeaf(; style = get_julia_style(theme, :number_text))
    @test leaf.style.font.size == 21
    @test is_color_equal(leaf.style.color, get_theme_value(JuliaTheme(), :number_text).color)
    # Each kind of value takes the role of its kind, and `<:` an operator.
    role(name) = resolve_theme_color(ColorRole(name), Appearance())
    @test is_color_equal(JuliaIntegerToSyntaxLeaf().style.color, role(:number_literal))
    @test is_color_equal(JuliaFloatToSyntaxLeaf().style.color, role(:number_literal))
    @test is_color_equal(JuliaBoolToSyntaxLeaf().style.color, role(:boolean_literal))
    @test is_color_equal(JuliaNothingToSyntaxLeaf().style.color, role(:null_literal))
    @test is_color_equal(JuliaSymbolToSyntaxLeaf().style.color, role(:symbol_literal))
    @test is_color_equal(JuliaStringToSyntaxLeaf().style.color, role(:string_literal))
    @test is_color_equal(JuliaCharToSyntaxLeaf().style.color, role(:character_literal))
    @test is_color_equal(JuliaSubtypeToSyntaxNode().op_style.color, role(:operator))
    # A name whose kind its place gives takes the role of the kind, in bold at
    # its definition, on the screen.
    function drawn(source)
        texts = draw_texts(parse_julia(source), Appearance())
        name -> only(unique((color, weight) for (text, color, weight) in texts if strip(text) == name))
    end
    function_texts = drawn("function f(x::Int)::Bool\n    x.y\nend")
    @test function_texts("f") == (role(:function_name), 700)
    @test function_texts("Int") == (role(:type_name), 400)
    @test function_texts("Bool") == (role(:type_name), 400)
    @test function_texts("y") == (role(:field), 400)
    @test function_texts("x") == (role(:variable), 400)
    struct_texts = drawn("struct P <: Q{R}\n    a::Int\nend")
    @test struct_texts("P") == (role(:type_name), 700)
    @test struct_texts("Q") == (role(:type_name), 400)
    @test drawn("abstract type A end")("A") == (role(:type_name), 700)
    @test drawn("module M\nend")("M") == (role(:module_name), 700)
    @test drawn("@show x")("@show") == (role(:macro_name), 400)
    # A projection holds its styles and no theme, and its builder reads a theme
    # that is not scaled as at no scale.
    @test !hasfield(JuliaIntegerToSyntaxLeaf, :theme)
    built = JuliaToSyntax(; theme = JuliaTheme())
    @test unwrap_cell(only(rule for rule in built.dispatch if first(rule) === JuliaInteger)[2].style).font.size == 14
end
end
