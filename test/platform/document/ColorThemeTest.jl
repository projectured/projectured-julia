"""
The palettes, the kinds of colour of a theme and the colour theme: a step of a
ramp and a role resolve in the colour settings of an appearance, a scaled theme
follows a change of a setting and of a fine-tune, each palette meets the contrast
rules in each mode and contrast, and save and load keep the settings and the
fine-tunes.
"""

using Test
using ProjecturedPlatform.StyleModule
using ProjecturedKernel.EventModule: SystemColors

@theme struct ThColored
    font::StyleFont = StyleFont("Ubuntu", 14)
    key::StyleColor = ColorRole(:field)
    word::TextRole = TextRole(:keyword; weight = 700)
    step::StyleColor = PaletteColor(:green, 9)
    fixed::StyleColor = color_white
end

# Each pair of a text role and the surfaces that it sits on, with the least
# contrast that it needs in a normal and in a high contrast theme.
const _CONTRAST_RULES = [
    ((:text, :text_muted, :keyword, :definition, :function_name, :field, :string_literal,
      :character_literal, :number_literal, :boolean_literal, :null_literal, :symbol_literal,
      :constant, :type_name, :reference, :link, :operator, :punctuation, :punctuation_lit,
      :comment, :markup, :heading, :accent_text, :error_text, :warning_text, :success_text,
      :info_text), (:background, :surface), 4.5, 7.0),
    ((:text_faint,), (:background, :surface), 3.0, 4.5),
    ((:border_strong, :focus_ring, :selection_ring), (:background, :surface), 3.0, 4.5),
    ((:text_on_accent,), (:accent, :error_fill, :success_fill), 4.5, 7.0),
    ((:text_inverse, :text_inverse_muted), (:surface_inverse,), 4.5, 4.5),
]

function test_color_theme()
@testset "Color theme" begin

@testset "the Radix palette is in the registry, with every hue in both modes" begin
    @test "radix" in get_palette_names()
    palette = find_palette("radix")
    @test palette === RADIX_PALETTE
    for mode in (:light, :dark), hue in PALETTE_HUES
        ramp = find_palette_ramp(palette, hue, mode)
        @test ramp isa NTuple{12,StyleColor}
    end
    @test format_style_color(find_palette_ramp(palette, :neutral, :light)[1]) == "#fcfcfdff"
    @test format_style_color(find_palette_ramp(palette, :blue, :light)[9]) == "#3e63ddff"
    @test format_style_color(find_palette_ramp(palette, :neutral, :dark; neutral = :sand)[1]) == "#111110ff"
    @test find_palette_ramp(palette, :neutral, :light; neutral = :violet) ===
          find_palette_ramp(palette, :neutral, :light; neutral = :slate)
    @test find_palette_ramp(palette, :chartreuse, :light) === nothing
    @test_throws "gives no ramp of the hue" TablePalette("broken"; light = Dict(), dark = Dict(),
                                                         hues = Dict(), neutrals = [:x])
end

@testset "a step of a ramp: the accent, the alpha and a minimum contrast" begin
    palette = RADIX_PALETTE
    blue9 = find_palette_ramp(palette, :blue, :light)[9]
    @test compute_palette_color(palette, PaletteColor(:accent, 9), :light; accent = :blue) == blue9
    @test compute_palette_color(palette, PaletteColor(:accent, 9), :light; accent = :nothing_here) == blue9
    half = compute_palette_color(palette, PaletteColor(:blue, 9; alpha = 0.5), :light)
    @test half.alpha == 0.5 && half.red == blue9.red
    # Orange 11 of Radix has 4.40 against the light background; the minimum moves it.
    orange = find_palette_ramp(palette, :orange, :light)[11]
    backdrop = find_palette_ramp(palette, :neutral, :light)
    @test compute_contrast_ratio(orange, backdrop[1]) < 4.5
    moved = compute_palette_color(palette, PaletteColor(:orange, 11; minimum_contrast = 4.5), :light)
    @test minimum(compute_contrast_ratio(moved, b) for b in backdrop[1:2]) >= 4.5
    @test minimum(compute_contrast_ratio(moved, b) for b in backdrop[1:2]) < 4.7
    # A step that reaches it stays as it is.
    violet = find_palette_ramp(palette, :violet, :light)[11]
    @test compute_palette_color(palette, PaletteColor(:violet, 11; minimum_contrast = 4.5), :light) == violet
    # Against white, a red of the dark mode moves toward the dark end.
    dark_red = compute_palette_color(palette, PaletteColor(:red, 9; minimum_contrast = 4.5,
                                                           against = color_white), :dark)
    @test compute_contrast_ratio(dark_red, color_white) >= 4.5
    @test_throws ArgumentError PaletteColor(:blue, 13)
    @test compute_contrast_ratio(color_black, color_white) ≈ 21.0
end

@testset "each palette meets the contrast rules in each mode and contrast" begin
    for name in get_palette_names(), mode in (:light, :dark), contrast in (:normal, :high)
        appearance = Appearance(color_palette = name, color_mode = mode, color_contrast = contrast)
        color(role) = resolve_theme_color(ColorRole(role), appearance)
        for (roles, surfaces, normal, high) in _CONTRAST_RULES, role in roles, surface in surfaces
            # A translucent surface sits over the background.
            back = color(surface)
            back.alpha < 1 && (back = color_interpolate(color(:background), back, back.alpha))
            ratio = compute_contrast_ratio(color(role), back)
            least = contrast === :high ? high : normal
            ratio >= least ||
                @info "contrast" name mode contrast role surface ratio least
            @test ratio >= least
        end
    end
end

@testset "the selection ring and the focus ring differ in each variant" begin
    for mode in (:light, :dark), contrast in (:normal, :high)
        appearance = Appearance(color_mode = mode, color_contrast = contrast)
        @test resolve_theme_color(ColorRole(:selection_ring), appearance) !=
              resolve_theme_color(ColorRole(:focus_ring), appearance)
    end
end

@testset "the kinds of a value differ in each palette and each variant" begin
    # The least OKLab distance between two kinds. A string and a symbol are the
    # nearest pair: 0.037 in the light Radix palette, and 0.028 in its high
    # contrast variant, where a contrast of 7 takes green and teal to dark steps.
    least = 0.025
    kinds = (:string_literal, :number_literal, :boolean_literal, :symbol_literal)
    for name in get_palette_names(), mode in (:light, :dark), contrast in (:normal, :high)
        appearance = Appearance(color_palette = name, color_mode = mode, color_contrast = contrast)
        function oklab(role)
            lightness, chroma, hue = convert_color_to_oklch(resolve_theme_color(ColorRole(role), appearance))
            (lightness, chroma * cosd(hue), chroma * sind(hue))
        end
        for (i, a) in enumerate(kinds), b in kinds[i+1:end]
            distance = sqrt(sum(abs2, oklab(a) .- oklab(b)))
            distance >= least || @info "kinds" name mode contrast a b distance
            @test distance >= least
        end
    end
    appearance = Appearance()
    @test resolve_theme_color(ColorRole(:character_literal), appearance) ==
          resolve_theme_color(ColorRole(:string_literal), appearance)
    @test resolve_theme_color(ColorRole(:null_literal), appearance) ==
          resolve_theme_color(ColorRole(:boolean_literal), appearance)
end

@testset "a role and a step resolve in the colour settings of the appearance" begin
    appearance = Appearance()
    @test get_color_variant(appearance) === :light
    @test get_color_variant(:dark, :high) === :dark_high_contrast
    @test get_color_variant(:system, :normal) === :light
    @test Set(keys(appearance.color_themes)) == Set(COLOR_VARIANTS)
    background = resolve_theme_color(ColorRole(:background), appearance)
    @test format_style_color(background) == "#f9f9fbff"
    @test format_style_color(resolve_theme_color(ColorRole(:surface), appearance)) == "#fcfcfdff"
    @test resolve_theme_color(color_red, appearance) === color_red
    faint = resolve_theme_color(ColorRole(:text; alpha = 0.5), appearance)
    @test faint.alpha == 0.5
    @test_throws "has no role" resolve_theme_color(ColorRole(:no_such_role), appearance)
    # A role may name another role, and a cycle is an error.
    get_color_theme(appearance).definition = ColorRole(:keyword)
    @test resolve_theme_color(ColorRole(:definition), appearance) ==
          resolve_theme_color(ColorRole(:keyword), appearance)
    get_color_theme(appearance).keyword = ColorRole(:definition)
    @test_throws "cycle" resolve_theme_color(ColorRole(:definition), appearance)
end

@testset "a scaled theme follows the mode, the palette settings and a fine-tune" begin
    appearance = Appearance()
    scaled = make_scaled_theme(ThColored(), appearance)
    light_key = scaled.key
    @test light_key == resolve_theme_color(ColorRole(:field), appearance)
    @test scaled.word.font.weight == 700
    @test scaled.word.color == resolve_theme_color(ColorRole(:keyword), appearance)
    @test scaled.fixed === color_white
    appearance.color_mode = :dark
    @test scaled.key != light_key
    @test format_style_color(scaled.step) == format_style_color(find_palette_ramp(RADIX_PALETTE, :green, :dark)[9])
    appearance.color_neutral = :sand
    @test format_style_color(resolve_theme_color(ColorRole(:background), appearance)) == "#111110ff"
    appearance.color_accent = :pink
    @test resolve_theme_color(ColorRole(:accent_tint), appearance) ==
          find_palette_ramp(RADIX_PALETTE, :pink, :dark)[3]
    # A fine-tune of a role in the dark theme stays in the dark theme.
    appearance.color_themes[:dark].field = color_red
    @test scaled.key === color_red
    appearance.color_mode = :light
    @test scaled.key == light_key
    # The high contrast theme of the light mode has a darker muted text.
    muted = resolve_theme_color(ColorRole(:text_muted), appearance)
    appearance.color_contrast = :high
    @test compute_relative_luminance(resolve_theme_color(ColorRole(:text_muted), appearance)) <
          compute_relative_luminance(muted)
    # An unknown palette falls back to the default.
    appearance.color_palette = "no-such-palette"
    @test resolve_theme_color(ColorRole(:background), appearance) isa StyleColor
    # A theme read at no scale resolves in the default appearance.
    @test get_theme_value(ThColored(), :key) == resolve_theme_color(ColorRole(:field), Appearance())
end

@testset "a :system setting follows the colour settings of the system" begin
    appearance = Appearance()
    @test (appearance.color_mode, appearance.color_contrast) === (:system, :system)
    # With no answer of a backend, the system is light and normal.
    @test get_color_variant(appearance) === :light
    scaled = make_scaled_theme(ThColored(), appearance)
    light_key = scaled.key
    appearance.system_colors = SystemColors(; mode = :dark, contrast = :high)
    @test (get_color_mode(appearance), get_color_contrast(appearance)) === (:dark, :high)
    @test get_color_variant(appearance) === :dark_high_contrast
    @test resolve_theme_color(ColorRole(:background), appearance) ==
          resolve_theme_color(ColorRole(:background), Appearance(color_mode = :dark, color_contrast = :high))
    @test scaled.key != light_key
    # A setting that names a mode or a contrast does not follow the system.
    appearance.color_mode = :light
    appearance.color_contrast = :normal
    @test get_color_variant(appearance) === :light
    @test scaled.key == light_key
    # The accent of the system takes the hue whose step 9 is nearest.
    appearance.color_accent = :system
    @test get_color_accent(appearance) === :blue              # the system names no accent
    for (bytes, hue) in (((0xe5, 0x48, 0x4d), :red),         # step 9 of the Radix red
                         ((0xaf, 0x52, 0xde), :violet),      # the purple of macOS
                         ((0x21, 0x90, 0xa4), :teal),        # the teal of GNOME
                         ((0x8e, 0x8e, 0x93), :blue))        # graphite, a grey
        appearance.system_colors = SystemColors(; accent = bytes)
        @test get_color_accent(appearance) === hue
    end
    appearance.system_colors = SystemColors(; accent = (0xaf, 0x52, 0xde))
    @test resolve_theme_color(PaletteColor(:accent, 9), appearance) ==
          find_palette_ramp(RADIX_PALETTE, :violet, :light)[9]
    @test find_nearest_accent_hue(color_gray127, RADIX_PALETTE, :light) === nothing
end

@testset "save and load keep the colour settings, the fine-tunes and a role of a field" begin
    mktempdir(; prefix = "color-theme-") do directory
        path = joinpath(directory, "appearance.toml")
        appearance = Appearance(color_mode = :dark, color_contrast = :high, color_accent = :violet,
                                color_neutral = :mauve)
        theme = get_color_theme(appearance)
        theme.keyword = PaletteColor(:pink, 11; minimum_contrast = 7.0)
        appearance.color_themes[:light].heading = color_red
        set_theme!(appearance, ThColored(key = ColorRole(:string_literal; alpha = 0.5),
                                         step = PaletteColor(:teal, 10)))
        save_appearance!(appearance, path)
        text = read(path, String)
        @test occursin("color_mode = \"dark\"", text)
        @test !occursin("background", text)       # a role at its default is not saved
        @test !occursin("system_colors", text)    # a fact of the system is not saved

        loaded = Appearance()
        set_theme!(loaded, ThColored())
        load_appearance!(loaded, path)
        @test loaded.color_mode === :dark
        @test loaded.color_contrast === :high
        @test loaded.color_accent === :violet
        @test loaded.color_neutral === :mauve
        @test loaded.color_palette == "radix"
        @test get_color_theme(loaded).keyword == PaletteColor(:pink, 11; minimum_contrast = 7.0)
        @test loaded.color_themes[:light].heading == color_red
        @test loaded.color_themes[:dark].keyword == make_color_theme(:dark).keyword
        @test get_theme(loaded, ThColored).key == ColorRole(:string_literal; alpha = 0.5)
        @test get_theme(loaded, ThColored).step == PaletteColor(:teal, 10)
        @test get_theme(loaded, ThColored).word == TextRole(:keyword; weight = 700)

        # A mode that is not known takes the default, which follows the system.
        write(path, "color_mode = \"sepia\"\ncolor_contrast = \"high\"\n")
        load_appearance!(loaded, path)
        @test loaded.color_mode === :system
        @test loaded.color_contrast === :high
        @test get_color_theme(loaded).keyword == make_color_theme(:light_high_contrast).keyword
    end
end

end
end
