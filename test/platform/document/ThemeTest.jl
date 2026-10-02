"""
`@theme`, the kinds of length, the scaled theme and `Appearance`: each kind takes
its scale, a scaled value follows its field and its scale, and a read through an
`UntrackedCell` records no edge.
"""

using Test
using ProjecturedPlatform.StyleModule
using ProjecturedKernel.CellModule

@theme struct ThSample
    body::StyleText       = StyleText(font_ubuntu_regular_20, color_black)
    caption::StyleFont    = font_ubuntu_regular_14
    rule::StyleStroke     = StyleStroke(color_black, 2)
    padding::Spacing      = Spacing(Inset(9, 9, 14, 14))
    gap::Spacing          = Spacing(4)
    corner::Radius        = Radius(8)
    border::LineWidth     = LineWidth(1)
    knob::ControlSize     = ControlSize(Point2D(44, 24))
    icon::IconSize        = IconSize(20)
    background::StyleColor = color_white
    columns::Int          = 3
end

"A theme whose fields have docstrings."
@theme struct ThDocumented
    "The space between two items."
    gap::Spacing = Spacing(4)
    plain::StyleColor = color_white
    """
    The color of a line,
    in two lines.
    """
    line::StyleColor = color_black
end

@theme struct ThUndocumented
    "The gap."
    gap::Spacing = Spacing(4)
end

function test_theme()
@testset "Theme" begin

@testset "a string before a field is its docstring" begin
    @test get_theme_field_names(ThDocumented) == (:gap, :plain, :line)
    @test find_theme_field_text(ThDocumented, :gap) == "The space between two items."
    @test find_theme_field_text(ThDocumented, :plain) === nothing
    @test find_theme_field_text(ThDocumented, :line) == "The color of a line,\nin two lines."
    @test find_theme_field_text(ThSample, :gap) === nothing
    @test get_theme_field_texts(ThDocumented) ==
          (gap = "The space between two items.", line = "The color of a line,\nin two lines.")
    # A theme with no docstring of its own keeps the docstrings of its fields.
    @test find_theme_field_text(ThUndocumented, :gap) == "The gap."
    @test make_scaled_theme(ThDocumented(), Appearance(spacing_scale = 2.0)).gap == 8
    @test_throws "as its docstring" macroexpand(@__MODULE__,
        :(@theme struct ThWrong; 1 + 2; gap::Spacing = Spacing(4); end))
end

@testset "the default theme and its fields" begin
    theme = ThSample()
    @test theme isa Theme
    @test get_theme_type(theme) === ThSample
    @test get_theme_field_names(ThSample) ==
          (:body, :caption, :rule, :padding, :gap, :corner, :border, :knob, :icon,
           :background, :columns)
    @test theme.gap == Spacing(4)
end

@testset "at 1.0 every value stays" begin
    scaled = make_scaled_theme(ThSample())
    @test scaled isa ScaledTheme
    @test scaled.body.font.size == 20
    @test scaled.caption.size == 14
    @test scaled.rule.width == 2
    @test scaled.padding.left[] == 14
    @test scaled.gap == 4
    @test scaled.corner == 8
    @test scaled.border == 1
    @test scaled.knob.x[] == 44
    @test scaled.icon == 20
    @test scaled.background == color_white
    @test scaled.columns == 3
end

@testset "each kind takes its own scale" begin
    appearance = Appearance(font_scale = 1.5, icon_scale = 2.0, spacing_scale = 0.5,
                            control_scale = 1.25, radius_scale = 3.0, line_scale = 2.0)
    scaled = make_scaled_theme(ThSample(), appearance)
    @test scaled.body.font.size == 30
    @test scaled.body.color == color_black
    @test scaled.caption.size == 21
    @test scaled.rule.width == 4
    @test scaled.padding.top[] == 4 && scaled.padding.left[] == 7
    @test scaled.gap == 2
    @test scaled.corner == 24
    @test scaled.border == 2
    @test scaled.knob.x[] == 55 && scaled.knob.y[] == 30
    @test scaled.icon == 40
    @test scaled.background == color_white
    @test scaled.columns == 3
end

@testset "a bare number takes the kind that the field declares" begin
    appearance = Appearance(spacing_scale = 2.0, radius_scale = 3.0)
    scaled = make_scaled_theme(ThSample(gap = 5, corner = 2), appearance)
    @test scaled.gap == 10
    @test scaled.corner == 6
    @test get_theme_appearance(scaled) === appearance
    @test convert_theme_value(Spacing, 3) == Spacing(3)
    @test convert_theme_value(Int, 3) === 3
end

@testset "a length above 0 stays at least 1" begin
    scaled = make_scaled_theme(ThSample(), Appearance(line_scale = 0.1, spacing_scale = 0.1))
    @test scaled.border == 1
    @test scaled.gap == 1
end

@testset "a scaled value follows its field and its scale" begin
    appearance = Appearance()
    theme = ThSample()
    scaled = make_scaled_theme(theme, appearance)
    @test scaled.gap == 4
    theme.gap = Spacing(6)
    @test scaled.gap == 6
    appearance.spacing_scale = 2.0
    @test scaled.gap == 12
    @test get_base_theme(scaled) === theme
end

@testset "a read through an untracked cell records no edge" begin
    appearance = Appearance()
    scaled = make_scaled_theme(ThSample(), appearance)
    gap = UntrackedCell{Int}(@computation scaled.gap)
    reader = Cell(@computation gap[] + 1)
    @test reader[] == 5
    appearance.spacing_scale = 2.0
    @test is_cell_up_to_date(reader)       # no edge: the reader keeps its value
    @test gap[] == 8                       # a new read sees the new scale
end

@testset "an appearance holds one theme of each type" begin
    appearance = Appearance()
    scaled = get_scaled_theme!(appearance, ThSample)
    @test get_scaled_theme!(appearance, ThSample) === scaled
    @test get_theme(appearance, ThSample) === get_base_theme(scaled)
    other = set_theme!(appearance, ThSample(gap = Spacing(10)))
    @test get_scaled_theme!(appearance, ThSample) === other
    @test other.gap == 10
    @test get_theme(Appearance(), ThSample) === nothing
end

@testset "two appearances are independent" begin
    first_appearance = Appearance()
    second_appearance = Appearance()
    first_scaled = get_scaled_theme!(first_appearance, ThSample)
    second_scaled = get_scaled_theme!(second_appearance, ThSample)
    first_appearance.font_scale = 2.0
    @test first_scaled.body.font.size == 40
    @test second_scaled.body.font.size == 20
end

end
end
