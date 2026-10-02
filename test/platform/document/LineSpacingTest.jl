# The distance between lines and the box of a line that holds one text. A line
# of FontMetrics(12, 4, 2) has the natural distance 18: its ascent, descent and
# line gap, added.
function test_line_spacing()
@testset "the line spacing" begin

    metrics = FontMetrics(12, 4, 2)

    @testset "each spacing gives its line distance" begin
        @test compute_line_distance(SingleSpacing(), metrics) == 18
        @test compute_line_distance(MultipleSpacing(1.5), metrics) == 27
        @test compute_line_distance(ExactSpacing(10), metrics) == 10
        @test compute_line_distance(AtLeastSpacing(10), metrics) == 18
        @test compute_line_distance(AtLeastSpacing(30), metrics) == 30
    end

    @testset "half of the leading is above the ink" begin
        # The leading of single spacing is the line gap, 2.
        @test compute_baseline_offset(SingleSpacing(), metrics) == 1 + 12
        @test compute_baseline_offset(MultipleSpacing(1.5), metrics) == (27 - 16) / 2 + 12
        # A distance less than the ink has a negative leading.
        @test compute_baseline_offset(ExactSpacing(10), metrics) == (10 - 16) / 2 + 12
    end

    measure = FixedMeasure(8, 12, 4, 0)

    @testset "the box of a line with fixed numbers" begin
        @test compute_text_extent(measure, "abc", StyleFont("Ubuntu", 20)) == (24, 12, 4)
        @test compute_line_box(measure, "abc", StyleFont("Ubuntu", 20)) == LineBox(24, 16, 12, 0)
        # Double spacing puts half of the leading of 16 above the text.
        @test compute_line_box(measure, "abc", StyleFont("Ubuntu", 20);
                               spacing = MultipleSpacing(2)) == LineBox(24, 32, 20, 8)
        # A line box holds the ink of its text at any spacing.
        @test compute_line_box(measure, "abc", StyleFont("Ubuntu", 20);
                               spacing = ExactSpacing(10)) == LineBox(24, 16, 12, 0)
    end

    @testset "the box of a line from the font files" begin
        file = FontFileMeasure()
        # Ubuntu 20: ascent 18.64, descent 3.78, line gap 0.56, so the line
        # distance is 22.98 and the baseline 0.28 + 18.64 below the top.
        @test compute_line_box(file, "Type", StyleFont("Ubuntu", 20)) ==
              LineBox(compute_text_extent("Type", StyleFont("Ubuntu", 20))[1], 23, 19, 0)
        # Ubuntu Mono 20: ascent 16.60 and descent 3.40, no line gap. The line
        # distance is 20, and the box of the line reaches the bottom of the box
        # of the text, 17 + 4.
        @test compute_line_box(file, "abc", StyleFont("Ubuntu Mono", 20)) == LineBox(30, 21, 17, 0)
        # An empty text is a line of its font.
        @test compute_line_box(file, "", StyleFont("Ubuntu", 20)) == LineBox(0, 23, 19, 0)
    end

end
end
