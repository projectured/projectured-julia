# The documents of the text layout examples: one `TextBlock` for each rule of the
# line model of `TextToGraphics`, and one for the line spacings. The text of each
# document says what to look at. `make_text_layout_projection_example` lays them
# out.

_make_layout_heading(text) = TextString(text, font_ubuntu_bold_24, color_default)
_make_layout_prose(text) = TextString(text, font_ubuntu_regular_20, color_default)
_make_layout_code(text) = TextString(text, font_ubuntu_monospace_regular_20, color_solarized_violet)
_make_layout_newline() = TextNewline(font = font_ubuntu_regular_20)

# Runs of several fonts and sizes, a glyph that a fallback font draws, an emoji
# and an inline icon, on one line.
function make_text_baseline_document_example()
    newline = _make_layout_newline
    TextBlock(
        _make_layout_heading("One baseline for every run"), newline(),
        _make_layout_prose("Every run of a line sits on the baseline of the line, whatever its font and its size. " *
                           "The top of a run is the baseline less its own ascent, so a small run starts lower " *
                           "and a large one starts higher."), newline(),
        newline(),
        _make_layout_prose("Body text, "),
        _make_layout_code("measure_string()"),
        _make_layout_prose(", a "),
        TextString("Large", font_ubuntu_bold_36, color_default),
        _make_layout_prose(" word, a "),
        TextString("small", font_ubuntu_regular_14, color_default),
        _make_layout_prose(" one, a "),
        TextString("serif", font_liberation_serif_italic_24, color_default),
        _make_layout_prose(" one, an arrow → that a fallback font draws, an emoji 😀 and an icon "),
        TextGraphics(_load_inline_image("file.png"), 24, 24),
        _make_layout_prose(" share one baseline."), newline(),
        newline(),
        _make_layout_prose("The letters without descenders end on one line. The descenders of g, p and y " *
                           "reach below it, and the icon stands on it."),
    )
end

# Lines whose fonts ask for different heights, a code line with no line gap, an
# image on the baseline and an empty line.
function make_text_line_height_document_example()
    newline = _make_layout_newline
    TextBlock(
        _make_layout_heading("Each line is as high as its fonts ask"), newline(),
        _make_layout_prose("The height of a line comes from the boxes on it: the largest ascent, the largest " *
                           "descent and the largest line gap. So the lines below are not all the same height."),
        newline(),
        newline(),
        TextString("A line of small text, Ubuntu at 14 pixels.", font_ubuntu_regular_14, color_default), newline(),
        _make_layout_prose("A line of body text, Ubuntu at 20 pixels."), newline(),
        _make_layout_prose("One "),
        TextString("LARGE", font_ubuntu_bold_36, color_default),
        _make_layout_prose(" word makes the whole line taller."), newline(),
        _make_layout_code("Code in Ubuntu Mono has no line gap: its lines are 20 pixels apart,"), newline(),
        _make_layout_code("and the box of such a line is 21 pixels, so its ink is never cut."), newline(),
        _make_layout_prose("An image "),
        TextGraphics(_load_inline_image("projectured.png"), 48, 48),
        _make_layout_prose(" stands on the baseline, as a picture in line with text does."), newline(),
        _make_layout_prose("An empty line takes the height of its own font:"), newline(),
        newline(),
        _make_layout_prose("and the text goes on below it."),
    )
end

# Kerned pairs in a large bold font, next to a monospace line with no kerning.
function make_text_kerning_document_example()
    newline = _make_layout_newline
    TextBlock(
        _make_layout_heading("Kerning"), newline(),
        _make_layout_prose("A font file gives a kerning for some pairs of glyphs. The layout reads it from the " *
                           "kern table, and every backend draws each glyph at the pen position that the layout " *
                           "computed."), newline(),
        newline(),
        TextString("AVAWAToTy WAVE LT Yo", font_ubuntu_bold_36, color_default), newline(),
        TextString("AVAWAToTy WAVE LT Yo", font_ubuntu_monospace_regular_36, color_default), newline(),
        newline(),
        _make_layout_prose("The first line kerns: the V tucks under the A, and the o under the T. The second line " *
                           "is monospace, and its font has no kerning. Put the caret between A and V in the first " *
                           "line: it stands where V starts, after the kerning of the pair."),
    )
end

# Lines of mixed sizes to select across and to click between.
function make_text_selection_document_example()
    newline = _make_layout_newline
    TextBlock(
        _make_layout_heading("Select across lines"), newline(),
        _make_layout_prose("A selection covers the full line box of each line it spans, so its rows meet with no " *
                           "gap and no overlap. A click picks the line whose box holds it, then the character " *
                           "boundary nearest to it, also in the space between two lines."), newline(),
        newline(),
        _make_layout_prose("Drag from here,"), newline(),
        _make_layout_prose("across a line of "),
        TextString("large", font_ubuntu_bold_36, color_default),
        _make_layout_prose(" type,"), newline(),
        TextString("across a small line,", font_ubuntu_regular_14, color_default), newline(),
        _make_layout_prose("and a line of code, "),
        _make_layout_code("select(start, stop)"), _make_layout_prose(","), newline(),
        _make_layout_prose("to here."),
    )
end

# A paragraph that wraps into several lines, under a heading and a sentence that
# name the spacing that lays it out.
function make_text_spacing_document_example(title::AbstractString, description::AbstractString)
    newline = _make_layout_newline
    TextBlock(
        _make_layout_heading(title), newline(),
        _make_layout_prose(description), newline(),
        newline(),
        _make_layout_prose("Line spacing sets the distance from the top of a line to the top of the next one. " *
                           "Single spacing is the natural distance: the largest ascent, descent and line gap of " *
                           "the line. A multiple scales that distance. An exact distance ignores the fonts, so the " *
                           "ink of two lines can overlap. A minimum takes the larger of the two. Half of the " *
                           "leading, the space that the distance adds to the ink, is above the ink, and half is " *
                           "below it."),
    )
end
