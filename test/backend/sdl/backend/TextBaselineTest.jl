# SDL draws a text with its baseline the ascent of `compute_text_extent` below
# its `y`, and each glyph at the pen position of the layout, whatever the font,
# the size and the ratio.

# The darkness of each pixel of a BMP written by `write_image`, as a matrix
# [row, column] from the top left: 0 is white and 765 is black.
function _read_bmp_darkness(pixels)
    le(i, n) = sum(Int(pixels[i + k]) << (8k) for k in 0:(n - 1))
    data_off = le(11, 4)
    width = le(19, 4)
    height = abs(reinterpret(Int32, UInt32(le(23, 4))))
    bytes = le(29, 2) ÷ 8
    stride = ((width * bytes + 3) ÷ 4) * 4
    darkness(x, y) = let i = data_off + (height - 1 - y) * stride + x * bytes + 1
        765 - Int(pixels[i]) - Int(pixels[i + 1]) - Int(pixels[i + 2])
    end
    [darkness(x, y) for y in 0:(height - 1), x in 0:(width - 1)]
end

# The image of `texts` drawn black on white by `write_image` at `ratio`, as the
# darkness matrix of `_read_bmp_darkness`.
function _draw_darkness(texts, width, height, ratio)
    white = GraphicsRect(0, 0, width, height; color = StyleColor(1.0, 1.0, 1.0, 1.0))
    canvas = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)), Cell(Int32(width)), Cell(Int32(height)),
                            CellVector(Cell[Cell(e) for e in Any[white; texts]]),
                            layout_none, true, Cell(nothing))
    filename = tempname() * ".bmp"
    write_image(canvas, filename; width = width, height = height, supersample = 1, density = ratio)
    darkness = _read_bmp_darkness(read(filename))
    rm(filename)
    darkness
end

# The bottom row of the ink (a pixel darker than half) in the device columns
# `columns`, counted from 0 at the top, or `nothing` with no ink.
function _ink_bottom_row(darkness, columns)
    rows = [y - 1 for y in axes(darkness, 1) for x in columns
            if 0 <= x < size(darkness, 2) && darkness[y, x + 1] > 765 ÷ 2]
    isempty(rows) ? nothing : maximum(rows)
end

function test_sdl_text_baseline_ink()
@testset "SDL draws texts of different fonts on one baseline" begin
    baseline = 60
    # An "x" has no descender, so its ink ends on the baseline. The fonts
    # differ in their ascent, and one is larger.
    faces = [font_ubuntu_regular_20, font_ubuntu_monospace_regular_20,
             font_dejavu_sans_regular_20, font_ubuntu_bold_36]
    column = 20
    texts = Any[]
    spans = UnitRange{Int}[]
    for font in faces
        width, ascent, _ = compute_text_extent("xx", font)
        push!(texts, GraphicsText("xx", column, baseline - ascent;
                                  font = font, color = StyleColor(0.0, 0.0, 0.0, 1.0)))
        push!(spans, column:(column + width - 1))
        column += width + 20
    end
    for ratio in (1, 2)
        darkness = _draw_darkness(texts, column, 100, ratio)
        bottoms = [_ink_bottom_row(darkness, (first(span) * ratio):(last(span) * ratio)) for span in spans]
        @testset "at ratio $ratio" begin
            @test all(!isnothing, bottoms)
            # The last row of ink sits right above the baseline, for every font.
            @test all(==(baseline * ratio - 1), bottoms)
        end
    end
end
end

# The device column where the ink of `with_bar` starts to be darker than the ink
# of `without_bar` by more than half, in the device rows `rows`.
function _new_ink_column(with_bar, without_bar, rows)
    for x in axes(with_bar, 2), y in rows
        with_bar[y, x] - without_bar[y, x] > 765 ÷ 2 && return x - 1
    end
    nothing
end

function test_sdl_text_pen_positions()
@testset "SDL draws each glyph at the pen position of the layout" begin
    # A bar after each prefix of a text starts where the layout puts the pen
    # after the prefix, plus the left bearing of the bar. These texts kern, mix
    # advances that are not whole pixels, and moved SDL_ttf's own layout away
    # from the layout by up to 1.78 device pixels. The arrow is a glyph that
    # Ubuntu Mono lacks and a fallback font draws.
    ubuntu = font_ubuntu_regular_20
    bold = font_ubuntu_bold_20
    cases = [(with_font_size(ubuntu, 20), "WWWWWWWWWW"),
             (with_font_size(ubuntu, 20), "Selection stored in each"),
             (with_font_size(ubuntu, 20), "office fi"),
             (with_font_size(ubuntu, 14), "LTAV"),
             (with_font_size(bold, 36), "AVAWAToTy"),
             (font_dejavu_sans_regular_20, "Type yj"),
             (font_ubuntu_monospace_regular_20, "abc def"),
             (font_ubuntu_monospace_regular_20, "a→b")]
    x0 = 10
    for (font, text) in cases, ratio in (1, 2)
        width, ascent, descent = compute_text_extent(text * "|", font)
        pitch = ascent + descent + 4
        count = length(text) + 1
        rows = [(k, first(text, k)) for k in 0:(count - 1)]
        draw(bar) = _draw_darkness([GraphicsText(prefix * bar, x0, k * pitch; font = font,
                                                 color = StyleColor(0.0, 0.0, 0.0, 1.0))
                                    for (k, prefix) in rows],
                                   x0 + width + 10, count * pitch, ratio)
        with_bar, without_bar = draw("|"), draw("")
        band(k) = (k * pitch * ratio + 1):((k + 1) * pitch * ratio)
        # Row 0 is the bar alone: its ink starts at its left bearing.
        bearing = _new_ink_column(with_bar, without_bar, band(0)) - x0 * ratio
        errors = Float64[]
        for (k, prefix) in rows[2:end]
            column = _new_ink_column(with_bar, without_bar, band(k))
            pen = compute_caret_offsets(FontFileMeasure(), prefix * "|", font)[k + 1]
            push!(errors, column - x0 * ratio - bearing - pen * ratio)
        end
        @testset "$(basename(compute_font_path(font))) $(font.size) $(repr(text)) at ratio $ratio" begin
            @test maximum(abs, errors) <= 1
        end
    end
end
end
