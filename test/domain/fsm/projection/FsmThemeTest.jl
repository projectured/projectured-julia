# The Fsm syntax follows the scales of the appearance: the chain to text gives
# the Fsm projections, and the Julia nodes a guard, an action, an entry or a
# variable's type or default is built from, the scaled themes of its appearance,
# so at a font scale of 1.5 every text of a component is 1.5 times as large, and
# a Fsm projection that a builder gives no style has the default styles.

function test_fsm_theme()
@testset "the Fsm syntax follows the scales of the appearance" begin
    document = make_fsm_toggle_document_example()
    _projection(appearance) = ChainingProjection(
        RecursiveProjection(FsmToSyntax(;
            theme = get_scaled_theme!(appearance, FsmTheme),
            julia_theme = get_scaled_theme!(appearance, JuliaTheme),
            syntax_theme = get_scaled_theme!(appearance, SyntaxTheme))),
        RecursiveProjection(SyntaxToText(; theme = get_scaled_theme!(appearance, SyntaxTheme))),
        TextToGraphics(; measure = FixedMeasure(8, 12, 4, 0),
                       theme = get_scaled_theme!(appearance, TextTheme)))
    offer = PrinterContext(EmptyReference(), Cell(800), Cell(600), Dict{Symbol,Any}())
    draw(appearance) = collect_font_sizes(print_document(_projection(appearance), nothing, document, offer).output)

    plain = draw(Appearance())
    @test !isempty(plain)
    @test draw(Appearance(font_scale = 1.5)) == round.(Int, plain .* 1.5)

    @test FsmStateToSyntaxNode().keyword.font.size == 14
    theme = get_scaled_theme!(Appearance(font_scale = 1.5), FsmTheme)
    node = FsmStateToSyntaxNode(; keyword = get_fsm_style(theme, :keyword_text))
    @test node.keyword.font.size == 21
    @test is_color_equal(node.keyword.color, get_theme_value(FsmTheme(), :keyword_text).color)
    # A projection holds its styles and no theme, and its builder reads a theme
    # that is not scaled as at no scale.
    # Each kind of name takes the role of its kind, in bold at its declaration.
    role(name) = resolve_theme_color(ColorRole(name), Appearance())
    @test is_color_equal(FsmStateToSyntaxNode().name.color, role(:enum_member))
    @test FsmStateToSyntaxNode().name.font.weight == 700
    @test is_color_equal(FsmEventToSyntaxLeaf().name.color, role(:event))
    @test is_color_equal(FsmTimerToSyntaxLeaf().name.color, role(:event))
    @test is_color_equal(FsmVariableToSyntaxNode().name.color, role(:variable))
    @test is_color_equal(FsmMachineToSyntaxNode().name.color, role(:type_name))
    @test is_color_equal(FsmComponentToSyntaxNode().name.color, role(:type_name))
    @test is_color_equal(FsmTransitionToSyntaxNode().event_reference.color, role(:event))
    @test is_color_equal(FsmTransitionToSyntaxNode().state_reference.color, role(:enum_member))
    @test is_color_equal(FsmMachineToSyntaxNode().state_reference.color, role(:enum_member))
    @test is_color_equal(FsmStateToSyntaxLabel().name.color, role(:enum_member))
    @test !hasfield(FsmStateToSyntaxNode, :theme)
    @test !hasfield(FsmStateToSyntaxLabel, :theme)
    built = FsmToSyntax(; theme = FsmTheme())
    @test unwrap_cell(only(rule for rule in built.dispatch if first(rule) === FsmState)[2].keyword).font.size == 14
    label = FsmToSyntaxLabel(; theme = get_scaled_theme!(Appearance(font_scale = 1.5), FsmTheme))
    @test unwrap_cell(only(rule for rule in label.dispatch if first(rule) === FsmState)[2].name).font.size == 21
end
end
