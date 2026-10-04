# The gesture map, the command palette, the Help menu, and the reference
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
    plain = GestureMapToSyntax()
    scaled = GestureMapToSyntax(theme = get_scaled_theme!(Appearance(font_scale = 1.5), GestureHelpTheme))
    _check_theme_roles(plain, scaled, defaults,
                       [(:header, :map_header_text), (:gesture, :map_gesture_text),
                        (:description, :map_description_text), (:muted, :map_muted_text)])
end

@testset "CommandPaletteToSyntax reads GestureHelpTheme" begin
    defaults = make_scaled_theme(GestureHelpTheme())
    plain = CommandPaletteToSyntax()
    scaled = CommandPaletteToSyntax(theme = get_scaled_theme!(Appearance(font_scale = 1.5), GestureHelpTheme))
    _check_theme_roles(plain, scaled, defaults,
                       [(:query, :palette_query_text), (:header, :palette_header_text),
                        (:selected, :palette_selected_text), (:command, :palette_command_text),
                        (:muted, :palette_muted_text)])
end

@testset "CommandPaletteDecoratorProjection reads the palette panel of GestureHelpTheme" begin
    measure = FixedMeasure(8, 12, 4, 0)
    plain = CommandPaletteDecoratorProjection(inner = IdentityProjection(), measure = measure)
    style = unwrap_cell(plain.style)
    @test style.palette_radius == 6
    @test style.palette_border_width == 2
    @test style.palette_padding == 10
    @test is_color_equal(style.palette_background, color_solarized_background_lighter)
    @test is_color_equal(style.palette_border, color_solarized_blue)

    scaled = CommandPaletteDecoratorProjection(inner = IdentityProjection(), measure = measure,
        theme = get_scaled_theme!(Appearance(radius_scale = 2.0), GestureHelpTheme))
    @test unwrap_cell(scaled.style).palette_radius == 12
end

@testset "HelpListToSyntax reads HelpTheme" begin
    defaults = make_scaled_theme(HelpTheme())
    plain = HelpListToSyntax()
    scaled = HelpListToSyntax(theme = get_scaled_theme!(Appearance(font_scale = 1.5), HelpTheme))
    _check_theme_roles(plain, scaled, defaults,
                       [(:heading, :heading_text), (:name, :name_text), (:detail, :detail_text),
                        (:description, :description_text), (:muted, :muted_text)])
end

@testset "AboutPageToSyntax reads HelpTheme" begin
    defaults = make_scaled_theme(HelpTheme())
    plain = AboutPageToSyntax()
    scaled = AboutPageToSyntax(theme = get_scaled_theme!(Appearance(font_scale = 1.5), HelpTheme))
    _check_theme_roles(plain, scaled, defaults,
                       [(:name, :title_text), (:summary, :description_text), (:detail, :detail_text)])
end

@testset "ReferenceToText reads ReferenceTheme" begin
    defaults = make_scaled_theme(ReferenceTheme())
    plain = ReferenceToText()
    theme = get_scaled_theme!(Appearance(font_scale = 1.5), ReferenceTheme)
    scaled = ReferenceToText(font = get_reference_style(theme, :font),
                             style = make_theme_values_field(ReferenceTheme, theme))
    @test plain.font.size == defaults.font.size
    @test scaled.font.size == round(Int, plain.font.size * 1.5)
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
    scaled = make_reference_inspector_projection(
        theme = get_scaled_theme!(Appearance(font_scale = 1.5), InspectorTheme))
    @test plain.font.size == defaults.font.size
    @test scaled.font.size == round(Int, plain.font.size * 1.5)
    @test plain.header_font.size == defaults.header_font.size
    @test scaled.header_font.size == round(Int, plain.header_font.size * 1.5)
    @test is_color_equal(plain.header_color, defaults.header_color)
    @test is_color_equal(scaled.header_color, plain.header_color)
    # A value given for a keyword stays fixed regardless of the theme.
    fixed = make_reference_inspector_projection(
        theme = get_scaled_theme!(Appearance(font_scale = 1.5), InspectorTheme),
        font = StyleFont("Ubuntu Mono", 20))
    @test fixed.font.size == 20
end

@testset "a document of the Help menu and of an inspector follows the font scale" begin
    for document in (AboutPage(), DocumentTypeList(), ReferenceInspector())
        plain = draw_font_sizes(document, Appearance())
        @test !isempty(plain)
        @test draw_font_sizes(document, Appearance(font_scale = 1.5)) == round.(Int, plain .* 1.5)
    end
end

end
end
