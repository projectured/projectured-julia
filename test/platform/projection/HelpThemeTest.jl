# The gesture map, the Help menu, and the reference
# inspectors follow the scales of the appearance: the natural renderer gives
# each a scaled theme, so at a font scale of 1.5 every text they draw is 1.5
# times as large, and a projection with no theme has the default styles.

# Every (projection field, theme field) pair of `roles`: the plain projection
# `plain` (no theme) holds the font size and the color of the field `theme_field`
# of the default theme at no scale, `defaults`, and `scaled` (built with a theme at a font
# scale of 1.5) holds a font 1.5 times as large, with the same color.
function _check_theme_roles(plain, scaled, defaults, roles)
    for (field, theme_field) in roles
        expected = getproperty(defaults, theme_field)
        got = getproperty(plain, field)
        @test got.font.size == expected.font.size
        @test is_color_equal(got.color, expected.color)
        large = getproperty(scaled, field)
        @test large.font.size == round(Int, got.font.size * 1.5)
        @test is_color_equal(large.color, got.color)
    end
end

function test_help_themes()
@testset "the gesture help, the help menu and the inspectors follow the scales of the appearance" begin

@testset "GestureMapToSyntax reads GestureHelpTheme" begin
    defaults = make_scaled_theme(GestureHelpTheme())
    plain = make_gesture_map_syntax_projection()
    @test !hasfield(typeof(plain), :theme)
    scaled = make_gesture_map_syntax_projection(
        theme = get_scaled_theme!(Appearance(scale = AppearanceScale(font_scale = 1.5)), GestureHelpTheme))
    _check_theme_roles(plain, scaled, defaults,
                       [(:header, :map_header_text), (:gesture, :map_gesture_text),
                        (:description, :map_description_text), (:muted, :map_muted_text)])
end

@testset "HelpGroupToWidget and HelpEntryToWidget read HelpTheme" begin
    defaults = make_scaled_theme(HelpTheme())
    theme = get_scaled_theme!(Appearance(scale = AppearanceScale(font_scale = 1.5)), HelpTheme)
    plain = make_help_group_projection()
    @test !hasfield(typeof(plain), :theme)
    _check_theme_roles(plain, make_help_group_projection(; theme), defaults, [(:line, :heading_text)])
    plain = make_help_entry_projection()
    @test !hasfield(typeof(plain), :theme)
    _check_theme_roles(plain, make_help_entry_projection(; theme), defaults,
                       [(:name, :name_text), (:detail, :detail_text), (:description, :description_text),
                        (:muted, :muted_text)])
end

@testset "AboutPageToSyntax reads HelpTheme" begin
    defaults = make_scaled_theme(HelpTheme())
    plain = make_about_page_projection()
    @test !hasfield(typeof(plain), :theme)
    scaled = make_about_page_projection(theme = get_scaled_theme!(Appearance(scale = AppearanceScale(font_scale = 1.5)), HelpTheme))
    _check_theme_roles(plain, scaled, defaults,
                       [(:name, :title_text), (:summary, :description_text), (:detail, :detail_text)])
end

@testset "ReferenceToText reads ReferenceTheme" begin
    defaults = make_scaled_theme(ReferenceTheme())
    plain = ReferenceToText()
    @test !hasfield(typeof(plain), :font)
    theme = get_scaled_theme!(Appearance(scale = AppearanceScale(font_scale = 1.5)), ReferenceTheme)
    scaled = ReferenceToText(style = make_theme_values_field(ReferenceTheme, theme))
    @test plain.style.font.size == defaults.font.size
    @test scaled.style.font.size == round(Int, plain.style.font.size * 1.5)
    @test plain.style.aside_font.size == defaults.aside_font.size
    @test scaled.style.aside_font.size == round(Int, plain.style.aside_font.size * 1.5)
    for role in (:punctuation_color, :name_color, :index_color, :type_color, :projection_color, :unknown_color)
        @test is_color_equal(getproperty(plain.style, role), getproperty(defaults, role))
        @test is_color_equal(getproperty(scaled.style, role), getproperty(plain.style, role))
    end
end

@testset "ReferenceInspectorToText reads InspectorTheme" begin
    defaults = make_scaled_theme(InspectorTheme())
    plain = ReferenceInspectorToText()
    @test !hasfield(typeof(plain), :font)
    scaled = make_reference_inspector_projection(
        theme = get_scaled_theme!(Appearance(scale = AppearanceScale(font_scale = 1.5)), InspectorTheme))
    @test plain.header_font.size == defaults.header_font.size
    @test scaled.header_font.size == round(Int, plain.header_font.size * 1.5)
    @test is_color_equal(plain.header_color, defaults.header_color)
    @test is_color_equal(scaled.header_color, plain.header_color)
end

@testset "a line of an inspector draws at one size" begin
    # The words of a step and the "which is" that ends its line take the font of
    # the reference theme.
    inspector = ReferenceInspector(reference = Reference(FieldReferenceStep("entries"),
                                                         FieldReferenceStep("name")))
    texts = draw_texts(inspector, Appearance())
    sizes = draw_font_sizes(inspector, Appearance())
    which = findfirst(text -> occursin("which is", text[1]), texts)
    @test which !== nothing && which > 1
    @test sizes[which] == sizes[which - 1] == make_scaled_theme(ReferenceTheme()).font.size
end

@testset "a document of the Help menu and of an inspector follows the font scale" begin
    for document in (AboutPage(), update_help_groups!(DocumentTypeList()), ReferenceInspector())
        plain = draw_font_sizes(document, Appearance())
        @test !isempty(plain)
        @test draw_font_sizes(document, Appearance(scale = AppearanceScale(font_scale = 1.5))) == round.(Int, plain .* 1.5)
    end
end

end
end
