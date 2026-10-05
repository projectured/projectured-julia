# The tools follow the scales of the appearance: the natural renderer gives the
# fault log, the gesture log, the message log, the statistics table, the undo
# history and the file-system tree the scaled theme of their slice, so at a font
# scale of 1.5 every text of a tool is 1.5 times as large, and a tool projection
# with no theme has the default styles.

# Every style field named in `roles` of `build()` holds the font size `base_size`
# and the color of `theme_type()`, and of `build(theme = …)` at a font scale of
# 1.5 a font `base_size * 1.5` large, with the same color. `build` is the builder
# of a tool projection, and the projection holds no theme.
function _check_tool_theme(build, theme_type, roles, base_size::Integer)
    defaults = theme_type()
    plain = build()
    @test !hasfield(typeof(plain), :theme)
    scaled = build(theme = get_scaled_theme!(Appearance(font_scale = 1.5), theme_type))
    for role in roles
        color = get_theme_value(defaults, role).color
        @test getproperty(plain, role).font.size == base_size
        @test is_color_equal(getproperty(plain, role).color, color)
        @test getproperty(scaled, role).font.size == round(Int, base_size * 1.5)
        @test is_color_equal(getproperty(scaled, role).color, color)
    end
end

function test_tool_themes()
@testset "the tools follow the scales of the appearance" begin

@testset "FaultLogToSyntax reads FaultTheme" begin
    _check_tool_theme(make_fault_log_projection, FaultTheme,
                      (:count_text, :site_text, :origin_text, :message_text, :empty_text), 13)

    log = FaultLog()
    push!(log.entries, FaultLogEntry(1, UInt64(1), :print, :Test, "boom", 1))
    plain = draw_font_sizes(log, Appearance())
    @test !isempty(plain)
    @test draw_font_sizes(log, Appearance(font_scale = 1.5)) == round.(Int, plain .* 1.5)
end

@testset "GestureLogToSyntax reads GestureLogTheme" begin
    _check_tool_theme(make_gesture_log_projection, GestureLogTheme,
                      (:index_text, :gesture_text, :operation_text, :muted_text, :empty_text), 13)
end

@testset "MessageLogToSyntax reads MessageLogTheme" begin
    _check_tool_theme(make_message_log_projection, MessageLogTheme,
                      (:level_text, :message_text, :empty_text), 13)

    log = MessageLog()
    record_message!(log, "Info", "hello")
    plain = draw_font_sizes(log, Appearance())
    @test !isempty(plain)
    @test draw_font_sizes(log, Appearance(font_scale = 1.5)) == round.(Int, plain .* 1.5)
end

@testset "FrameStatisticsToWidget reads FrameStatisticsTheme" begin
    _check_tool_theme(make_frame_statistics_projection, FrameStatisticsTheme,
                      (:header_text, :row_text, :empty_text, :slow_text), 13)

    statistics = FrameStatistics()
    push!(statistics.rows, FrameStatisticsRow("frame_time", :second, 10, 1.0, 2.0, 1.5, 0.3, 15.0))
    plain = draw_font_sizes(statistics, Appearance())
    @test !isempty(plain)
    @test draw_font_sizes(statistics, Appearance(font_scale = 1.5)) == round.(Int, plain .* 1.5)
end

@testset "UndoBufferToSyntax reads UndoTheme" begin
    _check_tool_theme(make_undo_projection, UndoTheme,
                      (:index_text, :step_text, :ahead_text, :marker_text, :barrier_text, :empty_text), 13)
end

@testset "FileSystemFileToSyntaxLeaf and FileSystemDirectoryToSyntaxNode read FileSystemTheme" begin
    _check_tool_theme((; theme = nothing) -> FileSystemFileToSyntaxLeaf(;
        file_text = get_file_system_style(theme, :file_text)), FileSystemTheme, (:file_text,), 14)
    _check_tool_theme((; theme = nothing) -> FileSystemDirectoryToSyntaxNode(;
        directory_text = get_file_system_style(theme, :directory_text)), FileSystemTheme, (:directory_text,), 14)
end

end
end
