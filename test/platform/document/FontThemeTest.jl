"""
The font theme: the steps of the type scale, what a role of the font theme
resolves to in an appearance, a scaled theme that follows a change of a step, the
one rounding of the font scale, the two forms of a text role, and save and load of
the font theme and of a role that names a step.
"""

using Test
using ProjecturedPlatform.StyleModule

@theme struct ThFonted
    quiet::ThemeFont = FontRole(:quiet)
    code::ThemeFont = FontRole(:document_code; weight = 700)
    note::ThemeText = TextRole(:text_muted; font_role = :quiet, italic = true)
end

@theme struct ThIconed
    mark::ThemeText = TextRole(:warning_text; font = StyleFont("Lucide", 13))
end

function test_font_theme()
@testset "Font theme" begin

@testset "the default steps" begin
    theme = FontTheme()
    @test (theme.sans_family, theme.mono_family) == ("Ubuntu", "Ubuntu Mono")
    @test theme.page_title == FontStep(:sans, 20; weight = 500)
    @test theme.text == FontStep(:sans, 13)
    @test theme.label == FontStep(:sans, 13; weight = 500)
    @test theme.quiet == FontStep(:sans, 12)
    @test theme.heading_1 == FontStep(:sans, 24; weight = 700)
    @test theme.heading_6 == FontStep(:sans, 14; weight = 700)
    @test theme.code == FontStep(:mono, 13)
    @test theme.document_code == FontStep(:mono, 14)
    names = get_theme_field_names(FontTheme)
    steps = [getproperty(theme, name) for name in names if getproperty(theme, name) isa FontStep]
    @test length(steps) == 18
    @test sort(unique(step.size for step in steps)) == [12, 13, 14, 16, 20, 24]
    @test sort(unique(Int(step.weight) for step in steps)) == [400, 500, 700]
    @test all(name -> find_theme_field_text(FontTheme, name) !== nothing, names)
    @test_throws ArgumentError FontStep(:serif, 12)
    @test_throws ArgumentError FontStep(:sans, 0)
    @test_throws ArgumentError FontStep(:sans, 12; weight = 0)
    @test_throws ArgumentError FontStep(:sans, 12; weight = 1001)
    @test get_font_theme(Appearance()) isa FontTheme
end

@testset "a role resolves to the family, the size, the weight and the slant of its step" begin
    appearance = Appearance()
    @test resolve_font_role(FontRole(:quiet), appearance) == StyleFont("Ubuntu", 12)
    @test resolve_font_role(FontRole(:document_code), appearance) == StyleFont("Ubuntu Mono", 14)
    @test resolve_font_role(FontRole(:label), appearance) == StyleFont("Ubuntu", 13; weight = 500)
    # The weight and the slant of the role go over those of the step.
    @test resolve_font_role(FontRole(:label; weight = 700, italic = true), appearance) ==
          StyleFont("Ubuntu", 13; weight = 700, italic = true)
    @test resolve_font_role(FontRole(:quiet; italic = false), appearance).italic == false
    @test_throws "no_such_role" resolve_font_role(FontRole(:no_such_role), appearance)
    @test_throws "sans_family" resolve_font_role(FontRole(:sans_family), appearance)
end

@testset "a change of a family or of a step moves every role that names it" begin
    appearance = Appearance()
    get_font_theme(appearance).sans_family = "DejaVu Sans"
    @test resolve_font_role(FontRole(:quiet), appearance).family == "DejaVu Sans"
    @test resolve_font_role(FontRole(:heading_2), appearance).family == "DejaVu Sans"
    @test resolve_font_role(FontRole(:code), appearance).family == "Ubuntu Mono"
    get_font_theme(appearance).mono_family = "DejaVu Sans Mono"
    @test resolve_font_role(FontRole(:code), appearance).family == "DejaVu Sans Mono"
    get_font_theme(appearance).quiet = FontStep(:sans, 11; weight = 300)
    @test resolve_font_role(FontRole(:quiet), appearance) == StyleFont("DejaVu Sans", 11; weight = 300)
end

@testset "the font scale rounds the size once" begin
    appearance = Appearance(font_scale = 1.1)
    # 12 × 1.1 = 13.2 → 13.
    @test scale_theme_value(FontRole(:quiet), nothing, appearance).size == 13
    @test scale_theme_value(FontRole(:document_code), nothing, appearance).size == 15
    appearance.font_scale = 1.0
    @test scale_theme_value(FontRole(:quiet), nothing, appearance).size == 12
    get_font_theme(appearance).quiet = FontStep(:sans, 15)
    appearance.font_scale = 0.5
    @test scale_theme_value(FontRole(:quiet), nothing, appearance).size == 8
end

@testset "a text role with a role of the font theme" begin
    new = TextRole(:text_muted; font_role = :quiet, weight = 700)
    @test new.font == FontRole(:quiet; weight = 700)
    @test new.color == ColorRole(:text_muted)
    @test TextRole(:keyword; weight = 700).font == FontRole(:text; weight = 700)
    appearance = Appearance()
    text = scale_theme_value(new, nothing, appearance)
    @test text.font == StyleFont("Ubuntu", 12; weight = 700)
    @test text.color == resolve_theme_color(ColorRole(:text_muted), appearance)
end

@testset "a text role with an exact font" begin
    mark = TextRole(:warning_text; font = StyleFont("Lucide", 13))
    @test mark.font == StyleFont("Lucide", 13)
    @test mark.color == ColorRole(:warning_text)
    for keywords in ((font_role = :quiet,), (weight = 700,), (italic = true,))
        @test_throws ArgumentError TextRole(:warning_text; font = StyleFont("Lucide", 13), keywords...)
    end
    appearance = Appearance(font_scale = 1.5)
    scaled = scale_theme_value(mark, nothing, appearance)
    @test scaled.font == StyleFont("Lucide", 20)
    @test scaled.color == resolve_theme_color(ColorRole(:warning_text), appearance)
    # No font role changes it.
    get_font_theme(appearance).text = FontStep(:sans, 30)
    @test scale_theme_value(mark, nothing, appearance).font.size == 20
    @test make_scaled_theme(ThIconed(), appearance).mark.font == StyleFont("Lucide", 20)
end

@testset "a scaled theme follows the font theme and the font scale" begin
    appearance = Appearance()
    scaled = make_scaled_theme(ThFonted(), appearance)
    @test scaled.quiet == StyleFont("Ubuntu", 12)
    @test scaled.code == StyleFont("Ubuntu Mono", 14; weight = 700)
    @test scaled.note.font == StyleFont("Ubuntu", 12; italic = true)
    get_font_theme(appearance).quiet = FontStep(:sans, 20)
    @test scaled.quiet.size == 20
    @test scaled.note.font.size == 20
    get_font_theme(appearance).sans_family = "DejaVu Sans"
    @test scaled.quiet.family == "DejaVu Sans"
    appearance.font_scale = 2.0
    @test scaled.quiet.size == 40
    # A theme read at no scale takes the default font theme.
    @test get_theme_value(ThFonted(), :quiet) == StyleFont("Ubuntu", 12)
    @test get_theme_value(ThFonted(), :note).font == StyleFont("Ubuntu", 12; italic = true)
end

@testset "save and load keep the font theme and a role that names a step" begin
    mktempdir(; prefix = "font-theme-") do directory
        path = joinpath(directory, "appearance.toml")
        appearance = Appearance()
        theme = get_font_theme(appearance)
        theme.sans_family = "DejaVu Sans"
        theme.label = FontStep(:sans, 14; weight = 600, italic = true)
        theme.code = FontStep(:mono, 15)
        set_theme!(appearance, ThFonted(quiet = FontRole(:section; weight = 500),
                                        note = TextRole(:accent_text; font_role = :badge, italic = false)))
        save_appearance!(appearance, path)
        text = read(path, String)
        @test occursin("[FontTheme]", text)
        @test !occursin("mono_family", text)      # a field at its default is not saved
        @test !occursin("page_title", text)

        loaded = Appearance()
        set_theme!(loaded, ThFonted())
        load_appearance!(loaded, path)
        fonts = get_font_theme(loaded)
        @test fonts.sans_family == "DejaVu Sans"
        @test fonts.mono_family == "Ubuntu Mono"
        @test fonts.label == FontStep(:sans, 14; weight = 600, italic = true)
        @test fonts.code == FontStep(:mono, 15)
        @test fonts.page_title == FontTheme().page_title
        @test get_theme(loaded, ThFonted).quiet == FontRole(:section; weight = 500)
        @test get_theme(loaded, ThFonted).note == TextRole(:accent_text; font_role = :badge, italic = false)

        # A text role with an exact font keeps its font and its colour role.
        set_theme!(appearance, ThIconed(mark = TextRole(:error_text; font = StyleFont("Lucide", 17; weight = 700))))
        save_appearance!(appearance, path)
        text = read(path, String)
        @test occursin("Lucide", text) && occursin("error_text", text)
        loaded_mark = Appearance()
        set_theme!(loaded_mark, ThIconed())
        load_appearance!(loaded_mark, path)
        @test get_theme(loaded_mark, ThIconed).mark ==
              TextRole(:error_text; font = StyleFont("Lucide", 17; weight = 700))

        # A table of the old form, with a base, does not load: the field keeps its default.
        write(path, "[ThFonted.quiet]\nbase = \"font\"\nrelative_size = 2.0\n" *
                    "[FontTheme.quiet]\nfamily = \"serif\"\nsize = 12\n" *
                    "[FontTheme.text]\nfamily = \"mono\"\nsize = 17\n")
        load_appearance!(loaded, path)
        fresh = Appearance()
        set_theme!(fresh, ThFonted())
        load_appearance!(fresh, path)
        @test get_theme(fresh, ThFonted).quiet == FontRole(:quiet)
        # An invalid step keeps the default; a valid one is read; a field not named takes its default.
        @test get_font_theme(loaded).quiet == FontTheme().quiet
        @test get_font_theme(loaded).text == FontStep(:mono, 17)
        @test get_font_theme(loaded).sans_family == "Ubuntu"
        # A table of a role is read.
        write(path, "[ThFonted.quiet]\nrole = \"title\"\nweight = 500\n")
        load_appearance!(loaded, path)
        @test get_theme(loaded, ThFonted).quiet == FontRole(:title; weight = 500)
    end
end

end
end
