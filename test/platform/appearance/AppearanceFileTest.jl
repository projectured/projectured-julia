# Save and load of an appearance. A round trip keeps the zoom, the scales and the
# base values of each theme. A theme that the appearance does not hold yet takes
# its table when it is made, and a load writes a held theme in place, so its
# scaled theme follows. A key that a file does not name takes its default, and a
# key that it does not know is ignored.

function test_appearance_file()
@testset "save and load of an appearance" begin
mktempdir() do folder
    path = joinpath(folder, "appearance.toml")

    @testset "a round trip keeps every value" begin
        appearance = Appearance(zoom = 1.25, font_scale = 1.5, line_scale = 2.0)
        get_scaled_theme!(appearance, WidgetTheme)
        theme = get_theme(appearance, WidgetTheme)
        theme.primary = StyleColor(0.2, 0.4, 0.6, 1.0)
        theme.font = StyleFont("DejaVu Sans", 22)
        theme.item_gap = Spacing(7)
        theme.control_padding = Spacing(Inset(1, 2, 3, 4))
        theme.switch_track = ControlSize(Point2D(50, 20))
        @test save_appearance!(appearance, path) == path
        loaded = Appearance()
        get_scaled_theme!(loaded, WidgetTheme)
        load_appearance!(loaded, path)
        @test (loaded.zoom, loaded.font_scale, loaded.line_scale, loaded.icon_scale) == (1.25, 1.5, 2.0, 1.0)
        saved = get_theme(loaded, WidgetTheme)
        @test is_color_equal(saved.primary, StyleColor(0.2, 0.4, 0.6, 1.0))
        @test saved.font.size == 22 && saved.font.family == "DejaVu Sans"
        @test saved.item_gap == Spacing(7)
        inset = saved.control_padding.value
        @test (inset.top[], inset.bottom[], inset.left[], inset.right[]) == (1, 2, 3, 4)
        @test (saved.switch_track.value.x[], saved.switch_track.value.y[]) == (50, 20)
        @test saved.background == WidgetTheme().background
    end

    @testset "a theme that the appearance does not hold yet takes its table when it is made" begin
        loaded = load_appearance!(Appearance(), path)
        @test isempty(loaded.themes) && haskey(loaded.saved_themes, "WidgetTheme")
        scaled = get_scaled_theme!(loaded, WidgetTheme)
        @test scaled.item_gap == 7
        @test isempty(loaded.saved_themes)
    end

    @testset "a load writes a held theme in place, so its scaled theme follows" begin
        live = Appearance()
        scaled = get_scaled_theme!(live, WidgetTheme)
        @test scaled.item_gap == 2
        load_appearance!(live, path)
        @test scaled.item_gap == 7
        @test live.zoom == 1.25
    end

    @testset "a key that the file does not name takes its default, and an unknown key is ignored" begin
        write(path, "font_scale = 2.0\nunknown = 3\n\n[WidgetTheme]\nitem_gap = 9\n" *
                    "not_a_field = 1\nprimary = \"not a color\"\n\n[NoSuchTheme]\nx = 1\n")
        live = Appearance(zoom = 1.5)
        scaled = get_scaled_theme!(live, WidgetTheme)
        get_theme(live, WidgetTheme).radius = Radius(20)
        load_appearance!(live, path)
        @test (live.zoom, live.font_scale) == (1.0, 2.0)
        @test scaled.item_gap == 9
        @test get_theme(live, WidgetTheme).radius == Radius(6)
        @test get_theme(live, WidgetTheme).primary == WidgetTheme().primary
        @test haskey(live.saved_themes, "NoSuchTheme")
    end

    @testset "a missing file changes nothing" begin
        @test load_appearance!(Appearance(zoom = 1.5), joinpath(folder, "none.toml")).zoom == 1.5
    end

    @testset "a load prints the view again, and a save does not" begin
        appearance = Appearance()
        @test is_appearance_change(appearance, LoadAppearanceOperation(appearance, path))
        @test !is_appearance_change(appearance, SaveAppearanceOperation(appearance, path))
    end
end
end
end
