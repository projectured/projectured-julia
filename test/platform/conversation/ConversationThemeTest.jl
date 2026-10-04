# The conversation projections follow the scales of the appearance: each of
# the six projections of `ConversationModule` holds the styles that its builder
# reads from the scaled `ConversationTheme`, so at a font scale of 1.5 every
# text is 1.5 times as large, at a spacing scale of 1.5 every gap and indent is
# 1.5 times as large, and a projection built with no styles holds the default
# values. `ConversationToWidget` gives the styles of one theme to its three
# composites.

# The projection that the type-dispatching projection `projection` gives to `T`.
_find_conversation_rule(projection, T) = last(only(rule for rule in projection.dispatch if first(rule) === T))

"""
    test_conversation_theme()

The conversation and the evaluator projections read `ConversationTheme`
through their style fields, and follow the font and the spacing scale of an
`Appearance`.
"""
function test_conversation_theme()
@testset "the conversation projections follow the scales of the appearance" begin

defaults = ConversationTheme()
scales = Appearance(font_scale = 1.5, spacing_scale = 1.5)
theme = get_scaled_theme!(scales, ConversationTheme)

@testset "ConversationConversationToWidgetComposite reads the gap between turns" begin
    plain = ConversationConversationToWidgetComposite()
    @test plain.turn_gap == 8
    @test !hasfield(ConversationConversationToWidgetComposite, :theme)
    scaled = _find_conversation_rule(ConversationToWidget(; theme), ConversationConversation)
    @test scaled.turn_gap == round(Int, 8 * 1.5)
end

@testset "ConversationTurnToWidgetComposite reads the role's label, its glyph and the gaps" begin
    plain = ConversationTurnToWidgetComposite()
    @test (plain.part_gap, plain.role_gap) == (8, 10)
    for (text_field, icon_field, color) in (
        (:user_role_text, :user_role_icon, color_indigo_600),
        (:assistant_role_text, :assistant_role_icon, color_solarized_cyan),
        (:other_role_text, :other_role_icon, color_slate_600))
        text = getproperty(plain, text_field)
        icon = getproperty(plain, icon_field)
        @test text.font.size == 13 && text.font.weight == 700 && text.font.family == "Ubuntu"
        @test is_color_equal(text.color, color)
        @test icon.font.size == 14 && icon.font.family == "Lucide"
        @test is_color_equal(icon.color, color)
    end
    scaled = _find_conversation_rule(ConversationToWidget(; theme), ConversationTurn)
    @test (scaled.part_gap, scaled.role_gap) == (round(Int, 8 * 1.5), round(Int, 10 * 1.5))
    @test scaled.user_role_text.font.size == round(Int, 13 * 1.5)
    @test scaled.user_role_icon.font.size == round(Int, 14 * 1.5)
end

@testset "ConversationPartToWidget reads the kind tag, the sections and their indent" begin
    plain = ConversationPartToWidget()
    @test plain.kind_text.font.size == 11 && plain.kind_text.font.weight == 700
    @test plain.section_text.font.size == 11 && plain.section_text.font.weight == 400
    @test plain.error_text.font.size == 11 && plain.error_text.font.weight == 700
    @test is_color_equal(plain.error_text.color, color_destructive)
    @test plain.section_gap == 10
    @test (plain.section_padding.top[], plain.section_padding.bottom[],
           plain.section_padding.left[], plain.section_padding.right[]) == (0, 0, 12, 0)

    scaled = _find_conversation_rule(ConversationToWidget(; theme), ConversationPart)
    @test scaled.kind_text.font.size == round(Int, 11 * 1.5)
    @test scaled.section_gap == round(Int, 10 * 1.5)
    @test scaled.section_padding.left[] == round(Int, 12 * 1.5)
    @test scaled.section_padding.top[] == 0
end

@testset "EvaluatorFormToVerticalLayout reads the prompts, and EvaluatorToplevelToWidgetComposite its gaps" begin
    plain = EvaluatorFormToVerticalLayout()
    @test (plain.row_gap, plain.prompt_gap) == (4, 8)
    @test plain.prompt_text.font.size == 14 && plain.prompt_text.font.family == "Ubuntu Mono"
    @test plain.prompt_text.font.weight == 400
    @test is_color_equal(plain.prompt_text.color, color_slate_500)
    @test is_color_equal(plain.error_prompt_text.color, color_destructive)

    scaled = make_evaluator_form_projection(; theme)
    @test scaled.prompt_text.font.size == round(Int, 14 * 1.5)
    @test scaled.row_gap == round(Int, 4 * 1.5)

    top_plain = EvaluatorToplevelToWidgetComposite()
    @test (top_plain.element_gap, top_plain.row_gap, top_plain.option_gap) == (8, 4, 12)
    top_scaled = make_evaluator_toplevel_projection(; theme)
    @test top_scaled.element_gap == round(Int, 8 * 1.5)
    @test top_scaled.option_gap == round(Int, 12 * 1.5)
end

@testset "ConversationComposerToWidget reads the composer's font, its gap and its colors" begin
    plain = ConversationComposerToWidget()
    @test plain.code_font == StyleFont("Ubuntu Mono", 14)
    @test plain.part_gap == 8
    @test is_color_equal(plain.plain_color, defaults.plain_color)
    @test is_color_equal(plain.placeholder_color, defaults.placeholder_color)
    @test is_color_equal(plain.valid_color, defaults.valid_color)
    @test is_color_equal(plain.invalid_color, defaults.invalid_color)
    @test is_color_equal(plain.completion_hint_color, defaults.completion_hint_color)
    # The composer and the transcript draw the committed sections of an
    # evaluation the same way, from the same fields.
    @test is_color_equal(plain.section_text.color, defaults.section_text.color)

    scaled = make_conversation_composer_projection(; theme)
    # A theme that is not scaled reads as at no scale.
    @test make_conversation_composer_projection(; theme = ConversationTheme()).code_font ==
          StyleFont("Ubuntu Mono", 14)
    @test scaled.code_font == StyleFont("Ubuntu Mono", 21)
    @test scaled.part_gap == round(Int, 8 * 1.5)
end

@testset "ConversationToWidget gives the same theme to its three composites" begin
    conversation = ConversationConversation([
        ConversationTurn(:user, [ConversationPart("hi")]),
        ConversationTurn(:assistant, [ConversationPart("there")])])
    plain_output = print_document(RecursiveProjection(ConversationToWidget()), conversation).output
    @test plain_output.gap == 8
    scaled_output = print_document(RecursiveProjection(ConversationToWidget(; theme)), conversation).output
    @test scaled_output.gap == round(Int, 8 * 1.5)
    turn_card = scaled_output.children[1]
    role_label = turn_card.title.children[2]
    @test role_label.text_style.font.size == round(Int, 13 * 1.5)
end

end
end
