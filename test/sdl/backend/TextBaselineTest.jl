# SDL draws a text with its baseline the ascent of `compute_text_extent` below
# its `y`, whatever the font and the size.

# The bottom row of the ink of every pixel darker than half in the columns
# `columns` of a BMP written by `write_image`, or `nothing` with no ink.
function _ink_bottom_row(pixels, columns)
    le(i, n) = sum(Int(pixels[i + k]) << (8k) for k in 0:(n - 1))
    data_off = le(11, 4)
    width = le(19, 4)
    height = abs(reinterpret(Int32, UInt32(le(23, 4))))
    bytes = le(29, 2) ÷ 8
    stride = ((width * bytes + 3) ÷ 4) * 4
    dark(x, y) = let i = data_off + (height - 1 - y) * stride + x * bytes + 1
        Int(pixels[i]) + Int(pixels[i + 1]) + Int(pixels[i + 2]) < 3 * 128
    end
    rows = [y for y in 0:(height - 1) for x in columns if 0 <= x < width && dark(x, y)]
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
    white = GraphicsRect(0, 0, column, 100; color = StyleColor(1.0, 1.0, 1.0, 1.0))
    canvas = GraphicsCanvas(Cell(Int32(0)), Cell(Int32(0)), Cell(Int32(column)), Cell(Int32(100)),
                            CellVector(Cell[Cell(e) for e in Any[white; texts]]),
                            layout_none, true, Cell(nothing))
    for ratio in (1, 2)
        filename = tempname() * ".bmp"
        write_image(canvas, filename; width = column, height = 100, supersample = 1, scale = ratio)
        pixels = read(filename)
        rm(filename)
        bottoms = [_ink_bottom_row(pixels, (first(span) * ratio):(last(span) * ratio)) for span in spans]
        @testset "at ratio $ratio" begin
            @test all(!isnothing, bottoms)
            # The last row of ink sits right above the baseline, for every font.
            @test all(==(baseline * ratio - 1), bottoms)
        end
    end
end
end
