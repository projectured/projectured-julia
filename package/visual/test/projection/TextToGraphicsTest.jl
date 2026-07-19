function test_text_to_graphics()
_test_measure(cw, lh) = (text, font) -> (length(text) * cw, lh)

# The TextToGraphics canvas carries a persistent highlight rect (behind the text)
# and cursor rect (in front) so that moving the caret never regenerates the spans;
# both are zero-width/invisible when no selection is set. The content is laid out
# as one sub-canvas per visual line (line at `y`, segments at `y` relative to it),
# so these helpers recursively flatten the tree into entries with ABSOLUTE
# coordinates, exposing the same `.x/.y/.text/.color/.w/.h` fields the assertions
# read regardless of nesting depth.
function _flat(c, ox::Int=0, oy::Int=0, acc=Tuple{Any,Int,Int}[])
    for i in 1:length(c.elements)
        e = c.elements[i]
        if e isa GraphicsCanvas
            _flat(e, ox + Int(e.x), oy + Int(e.y), acc)
        else
            push!(acc, (e, ox + Int(e.x), oy + Int(e.y)))
        end
    end
    acc
end
_all(c) = _flat(c)
_texts(c) = [(text = e.text, color = e.color, x = ax, y = ay) for (e, ax, ay) in _flat(c) if e isa GraphicsText]
_imgs(c)  = [(x = ax, y = ay, w = Int(e.w), h = Int(e.h)) for (e, ax, ay) in _flat(c) if e isa GraphicsImage]
_rects(c) = [(x = ax, y = ay, w = Int(e.w), h = Int(e.h), color = e.color) for (e, ax, ay) in _flat(c) if e isa GraphicsRect && Int(e.w) > 0]

@testset "TextToGraphics" begin

# basic layout (wrapping is now done by WordWrapping upstream)
st_wrap = TextBlock(
    TextString("Hello world this is a long text", font_ubuntu_monospace_regular_20, color_red),
)
m = _test_measure(10, 18)
chain = ChainingProjection(WordWrapping(max_width=200, measure=m), TextToGraphics(measure=m))
sdl_cell = print_document(chain, st_wrap).output
texts = _texts(sdl_cell)
@test length(texts) >= 2  # should wrap
@test texts[1].y == 0
@test texts[2].y == 18  # second line

# newline handling
st_nl = TextBlock(
    TextString("line1\nline2\nline3", font_ubuntu_monospace_regular_20, color_white),
)
sdl_nl = print_document(TextToGraphics(measure=_test_measure(10, 20)), st_nl).output
items_nl = _texts(sdl_nl)
@test length(items_nl) == 3
@test items_nl[1].text == "line1"
@test items_nl[2].text == "line2"
@test items_nl[3].text == "line3"
@test items_nl[1].y == 0
@test items_nl[2].y == 20
@test items_nl[3].y == 40

# color preservation
st_color = TextBlock(
    TextString("red text", font_ubuntu_monospace_regular_20, color_red),
    TextString(" blue text", font_ubuntu_monospace_regular_20, color_blue),
)
sdl_color = print_document(TextToGraphics(measure=_test_measure(10, 48)), st_color).output
items_c = _texts(sdl_color)
@test items_c[1].color == color_red    # red
@test items_c[2].color == color_blue   # blue

# continuation on same line
@test items_c[2].y == items_c[1].y  # same line
@test items_c[2].x > items_c[1].x   # to the right

# reactivity: a text change invalidates that line's segment vector (but, by
# per-line locality, NOT the top-level line list — see the locality testset).
st_react = TextBlock(
    TextString("short", font_ubuntu_monospace_regular_20, color_white),
)
sdl_react = print_document(TextToGraphics(measure=_test_measure(10, 48)), st_react).output
line1 = sdl_react.elements[2].elements[1]   # top[2]=line stack, [1]=first line sub-canvas
_ = length(line1.elements)
@test is_cell_up_to_date(getfield(line1.elements, :elements))
st_react.elements[1].content = "changed"
@test !is_cell_up_to_date(getfield(line1.elements, :elements))
items_r = _texts(sdl_react)
@test items_r[1].text == "changed"

# hex color parsing
st_hex = TextBlock(TextString("hex", font_ubuntu_monospace_regular_20, StyleColor(1.0, 0.53, 0.0, 1.0)))
sdl_hex = print_document(TextToGraphics(measure=_test_measure(10, 48)), st_hex).output
h = _texts(sdl_hex)[1]
# StyleColor is now carried through unchanged (no byte round-trip).
@test h.color == StyleColor(1.0, 0.53, 0.0, 1.0)

end # @testset "TextToGraphics"

@testset "TextToGraphics ListNode path" begin

# Build a TextBlock with ListNode elements: two paragraphs separated by TextNewline
node = ListNode(TextString("Hello world", font_ubuntu_monospace_regular_20, color_red))
push!(node, TextNewline(font=font_ubuntu_monospace_regular_20))
push!(node, TextString("Second paragraph", font_ubuntu_monospace_regular_20, color_blue))

tt = TextBlock()
tt.elements = node

p = TextToGraphics(measure=_test_measure(10, 20))
iomap = print_document(p, IdentityProjection(), tt, PrinterContext())
canvas = iomap.output

# Top-level canvas has ListNode elements, layout_vertical, non-overlapping
@test canvas.elements isa ListNode
@test canvas.layout == layout_vertical
@test canvas.overlapping_elements == false

# First paragraph sub-canvas
para1 = canvas.elements.value
@test para1 isa GraphicsCanvas
@test para1.y == 0
@test para1.elements isa CellVector
@test length(para1.elements) >= 1
@test para1.elements[1].text == "Hello world"

# Second paragraph is lazily computed via .next
next_node = canvas.elements.next
@test next_node !== nothing
para2 = next_node.value
@test para2 isa GraphicsCanvas
@test para2.y == 20  # one line_height below first paragraph
@test para2.elements[1].text == "Second paragraph"

# No third paragraph
@test next_node.next === nothing

end # @testset "TextToGraphics ListNode path"

@testset "TextToGraphics ListNode lazy evaluation" begin

# Verify laziness: next paragraphs are not computed until forced
counter = Ref(0)
node = ListNode(TextString("Para 1", font_ubuntu_monospace_regular_20, color_white))

# Build a lazy chain of paragraphs
node2 = ListNode(TextNewline(font=font_ubuntu_monospace_regular_20))
node.next = node2
node2.prev = node

node3 = ListNode(TextString("Para 2", font_ubuntu_monospace_regular_20, color_white))
set_cell_function!(getfield(node2, :next), () -> begin
    counter[] += 1
    node3.prev = node2
    node3
end)

tt = TextBlock()
tt.elements = node

p = TextToGraphics(measure=_test_measure(10, 20))
iomap = print_document(p, IdentityProjection(), tt, PrinterContext())

# The first paragraph collects spans until it finds the TextNewline,
# walking past it forces node2.next thunk to find where para 2 starts
@test counter[] == 1

# But the second paragraph's sub-canvas is lazily built (output .next thunk)
# Forcing it should not increase counter (input already walked)
next_node = iomap.output.elements.next
@test next_node !== nothing
@test counter[] == 1

end # @testset "TextToGraphics ListNode lazy evaluation"

@testset "TextToGraphics inline image" begin

m = _test_measure(10, 18)
st = TextBlock(
    TextString("ab", font_ubuntu_monospace_regular_20, color_white),
    TextGraphics(ImageMemory(nothing), 64, 64),
    TextString("cd", font_ubuntu_monospace_regular_20, color_white),
)
canvas = print_document(TextToGraphics(measure=m), st).output

# Exactly one GraphicsImage, at the expected box (after "ab" = 20px).
imgs = _imgs(canvas)
@test length(imgs) == 1
gi = imgs[1]
@test gi.x == 20
@test gi.y == 0
@test gi.w == 64
@test gi.h == 64

# Line height follows the image height.
@test canvas.h >= 64

# Surrounding text flows before/after the image on the same line.
texts = _texts(canvas)
@test length(texts) == 2
@test texts[1].text == "ab" && texts[1].x == 0
@test texts[2].text == "cd" && texts[2].x == 20 + 64

end # @testset "TextToGraphics inline image"

@testset "TextToGraphics inline image hit-test" begin

m = _test_measure(10, 18)
p = TextToGraphics(measure=m)
st = TextBlock(
    TextString("ab", font_ubuntu_monospace_regular_20, color_white),
    TextGraphics(ImageMemory(nothing), 64, 64),
    TextString("cd", font_ubuntu_monospace_regular_20, color_white),
)
iomap = print_document(p, st)

# A click path encodes (element-index → pixel offset). The persistent highlight
# rect is element 1, so the image (2nd text segment) is element index 2 (0-based);
# rx<32 is its left half, rx>=32 its right half.
click(rx) = ReplaceSelectionOperation(
    ConcreteReference(RangeReferenceStep(2, 3),
        ConcreteReference(PointReferenceStep(rx, 0), EmptyReference())))
left  = read_intent(p, iomap, click(10))
right = read_intent(p, iomap, click(50))
@test left isa ReplaceSelectionOperation
@test right isa ReplaceSelectionOperation
# Left half → cursor before the image (flat 2, end of "ab"); right half → the
# offset past it (flat 3). The image is zero-width in the caret stream, but the
# hit-test still resolves the two halves to distinct flat offsets.
@test is_reference_equal(left.path,  TextModule._flat_caret_ref(2))
@test is_reference_equal(right.path, TextModule._flat_caret_ref(3))

end # @testset "TextToGraphics inline image hit-test"

@testset "TextToGraphics renders fill_color as a background rect" begin

m = _test_measure(10, 18)
hl = TextString("hi", font_ubuntu_monospace_regular_20, color_red)
hl.fill_color = color_blue              # a highlighted span opts into a swatch
plain = TextString("xy", font_ubuntu_monospace_regular_20, color_red)
st = TextBlock(hl, plain)
canvas = print_document(TextToGraphics(measure=m), st).output

# Exactly one *visible* rect — the filled span; the default-`nothing` span gets
# none. The always-present highlight/cursor overlay rects are zero-width here.
rects = _rects(canvas)
@test length(rects) == 1
rect = rects[1]
@test rect.x == 0 && rect.y == 0
@test rect.w == 20 && rect.h == 18      # tight measured box of "hi"
@test rect.color == color_blue   # blue fill

# The fill rect is drawn before its text, so it paints behind.
flat = _flat(canvas)
rect_idx = findfirst(t -> t[1] isa GraphicsRect && Int(t[1].w) > 0, flat)
hi_idx   = findfirst(t -> t[1] isa GraphicsText && t[1].text == "hi", flat)
@test rect_idx !== nothing && hi_idx !== nothing
@test rect_idx < hi_idx

end # @testset "TextToGraphics fill_color rect"

@testset "TextToGraphics per-line dirty-rect locality" begin

# Lines split at TextNewline elements become independent reactive sub-canvases.
# Editing one line must invalidate only that line's segment vector — never the
# top-level line list (so the backend dirty-walk descends and repaints just the
# edited line) and never an earlier line.
m = _test_measure(10, 20)
nl() = TextNewline(font=font_ubuntu_monospace_regular_20)
st = TextBlock(
    TextString("alpha", font_ubuntu_monospace_regular_20, color_white), nl(),
    TextString("beta",  font_ubuntu_monospace_regular_20, color_white), nl(),
    TextString("gamma", font_ubuntu_monospace_regular_20, color_white),
)
canvas = print_document(TextToGraphics(measure=m), st).output

# Top canvas: [highlight, vertical line stack, cursor].
stack = canvas.elements[2]
@test stack isa GraphicsCanvas
@test stack.layout == layout_vertical
@test length(stack.elements) == 3
lines = [stack.elements[i] for i in 1:3]
@test all(l -> l isa GraphicsCanvas, lines)
@test [Int(l.y) for l in lines] == [0, 20, 40]      # cumulative line heights
@test [_texts(l)[1].text for l in lines] == ["alpha", "beta", "gamma"]

# Force every line's segment vector + text, then snapshot validity.
for l in lines
    _ = length(l.elements)
    for i in 1:length(l.elements); _ = l.elements[i].text; end
end
topback   = getfield(canvas.elements, :elements)
stackback = getfield(stack.elements, :elements)
lineback(L) = getfield(lines[L].elements, :elements)
@test is_cell_up_to_date(topback) && is_cell_up_to_date(stackback)
@test all(L -> is_cell_up_to_date(lineback(L)), 1:3)

# Edit the LAST line. Only its segment vector goes stale.
st.elements[5].content = "gamma!"          # element 5 = the 3rd TextString
@test is_cell_up_to_date(topback)                  # line list is structural — untouched
@test is_cell_up_to_date(stackback)
@test is_cell_up_to_date(lineback(1))
@test is_cell_up_to_date(lineback(2))
@test !is_cell_up_to_date(lineback(3))
@test _texts(lines[3])[1].text == "gamma!"

end # @testset "TextToGraphics per-line locality"

@testset "TextToGraphics lays out TextLine blocks" begin

m = _test_measure(10, 18)
p = TextToGraphics(measure=m)
_span(s) = TextString(s, font_ubuntu_monospace_regular_20, color_white)
mkblock() = TextBlock(TextLine(_span("hello"); indentation = 2), TextLine(_span("world")))

# One row per line, the break between them implied by the second line. The indent
# shifts its line and belongs to no span — two spaces at 10px each.
canvas = print_document(p, mkblock()).output
@test [(t.text, t.x, t.y) for t in _texts(canvas)] == [("hello", 20, 0), ("world", 0, 18)]
@test Int(canvas.h) == 36

# The coordinate table addresses a span inside a line by its index path.
@test [sc.span_path for sc in print_document(p, mkblock()).char_to_coord] == [[1, 1], [2, 1]]

# The caret lands on the character it was placed against: past the indent on an
# indented line, and on the right row for the line below. The selection is a flat
# offset; `_flat_base` names it from the structural (line, span) coordinate.
fb(path, k)  = TextModule._flat_base(mkblock(), path) + k
cflat(op)    = (r = strip_reference_types(op isa ReplaceSelectionOperation ? op.path : op);
                (r.head::TextRangeReferenceStep).start)
coord(op)    = TextModule._flat_to_span(mkblock(), cflat(op))   # (span_path, char)
caret(block) = [(r.x, r.y, r.h) for r in _rects(print_document(p, block).output) if r.w == 2]
@test caret(with_selection(mkblock(), TextModule._flat_caret_ref(fb(Int[1, 1], 0)))) == [(20, 0, 18)]
@test caret(with_selection(mkblock(), TextModule._flat_caret_ref(fb(Int[2, 1], 3)))) == [(30, 18, 18)]

# A click on the second row selects inside *that line's* span; Down crosses into
# it; End goes to the end of the line the caret is already on.
iomap = print_document(p, with_selection(mkblock(), TextModule._flat_caret_ref(fb(Int[1, 1], 0))))
click = read_intent(p, iomap, MousePress(:left, 31, 20))
@test click isa ReplaceSelectionOperation
@test coord(click) == ([2, 1], 3)
@test coord(read_intent(p, iomap, KeyDown(:down, ModifierKeys())))[1] == [2, 1]
@test coord(read_intent(p, iomap, KeyDown(:end, ModifierKeys()))) == ([1, 1], 5)

# A blank line keeps its row. It has neither a glyph nor a terminating
# `TextNewline` to take a height from, so the block's prevailing font sizes it.
blank = print_document(p, TextBlock(TextLine(_span("a")), TextLine(), TextLine(_span("b")))).output
@test Int(blank.h) == 54
@test [t.y for t in _texts(blank)] == [0, 36]

# The empty group a *trailing* newline leaves behind is not a line, and must not
# grow a phantom blank row.
trailing = print_document(p, TextBlock(_span("a"), TextNewline(font = font_ubuntu_monospace_regular_20))).output
@test Int(trailing.h) == 18

end # @testset "TextToGraphics lays out TextLine blocks"

@testset "TextColumnReferenceStep reserves the column-box geometry (variant 2)" begin

# Variant 2 (`TextColumnReferenceStep`) is reserved but has no producer yet; assert its
# geometry function directly on a hand-built two-row coord map (monospace, 10px/glyph).
_font = font_ubuntu_monospace_regular_20
measure = (t, f) -> (length(t) * 10, 18)
p = TextToGraphics(measure = measure)
SC = TextToGraphicsModule.SegCoord
coord_map = [SC([1], 0, 6, 0,  0, _font, "abcdef", 60, 18),
             SC([3], 0, 6, 0, 20, _font, "ghijkl", 60, 18)]
# Flat space: row 1 chars 0..6, an implicit break at 6, row 2 chars 7..13.
span_flat_offsets = Dict([1] => 0, [3] => 7)

# A column from flat 1 (row 1 col x=10) to flat 11 (row 2 char 4, col x=40): the
# rectangle [10 … 40] painted on both rows, regardless of the glyphs on each.
rects = TextToGraphicsModule._compute_column_geo(coord_map, span_flat_offsets, 1, 11, p)
@test length(rects) == 2                          # one rect per spanned row
@test all(r -> r[1] == 10 && r[3] == 30, rects)   # same [col10 … col40] box on every row
@test [r[2] for r in rects] == [0, 20]            # top row then bottom row

# Coinciding columns (zero width) or an unresolvable endpoint yield no box.
@test TextToGraphicsModule._compute_column_geo(coord_map, span_flat_offsets, 2, 9, p) == []

# A `TextColumnReferenceStep` selection is structural — not a character cursor, so char
# motion / flat edits decline (block editing is future work).
sel = ConcreteReference(TextColumnReferenceStep(1, 11), EmptyReference())
@test TextModule._is_structural_selection(sel)
@test TextModule._text_flat_selection(
          with_selection(TextBlock(TextString("abcdef", _font, color_default)), sel)) === nothing

end # @testset "TextColumnReferenceStep column-box geometry"

@testset "TextSpanReferenceStep draws content-hugging per-row rects (variant 3)" begin

# A structural (whole-node) selection maps to a single contiguous TextSpanReferenceStep
# flat range that crosses the interior lines' indent/newline chrome. It must be drawn
# as one rect per row hugging that row's *content* — not a bounding box. Model the
# JSON `address` shape (monospace, 10px/glyph): a first line at indent 0, an interior
# line whose leading indent is a separate whitespace span, and a close line.
_font = font_ubuntu_monospace_regular_20
measure = (t, f) -> (length(t) * 10, 18)
p = TextToGraphics(measure = measure)
SC = TextToGraphicsModule.SegCoord
fs = TextToGraphicsModule.font_logical_size(_font)
#   row y=0 : "AB{"          flat 0..3   (node's first line, starts at x=0)
#   break                    flat 3
#   row y=20: "    " indent  flat 4..8   (blank — must NOT anchor the row)
#   row y=20: "CD"           flat 8..10  (content at x=40, the indentation level)
#   break                    flat 10
#   row y=40: "  " indent    flat 11..13 (blank)
#   row y=40: "}"            flat 13..14 (the close, at x=20)
coord_map = [SC([1], 0, 3,  0,  0, _font, "AB{",  30, 18),
             SC([2], 0, 4,  0, 20, _font, "    ", 40, 18),
             SC([3], 0, 2, 40, 20, _font, "CD",   20, 18),
             SC([4], 0, 2,  0, 40, _font, "  ",   20, 18),
             SC([5], 0, 1, 20, 40, _font, "}",    10, 18)]
span_flat_offsets = Dict([1] => 0, [2] => 4, [3] => 8, [4] => 11, [5] => 13)

rects = TextToGraphicsModule._compute_span_rows(coord_map, span_flat_offsets, 0, 14, p)
@test length(rects) == 3                              # one rect per visual row
@test [r[2] for r in rects] == [0, 20, 40]            # top to bottom
@test all(r -> r[4] == fs, rects)                     # each the row's font height
# Row 1 hugs "AB{" — starts at the node's first char, ends at "{", NOT extended to
# the wider interior line's right edge (x=60).
@test (rects[1][1], rects[1][3]) == (0, 30)
# Interior line starts at its indentation level (x=40), not the highlighted indent's
# x=0, and ends at "CD"'s right edge.
@test (rects[2][1], rects[2][3]) == (40, 20)
# Close line starts at "}" (x=20), skipping its 2-space indent, and ends at x=30.
@test (rects[3][1], rects[3][3]) == (20, 10)

# A row whose only in-range content is whitespace yields no rect: select just the
# interior indent (flat 4..8) — blank, so no highlight.
@test TextToGraphicsModule._compute_span_rows(coord_map, span_flat_offsets, 4, 8, p) == []

end # @testset "TextSpanReferenceStep content-hugging per-row rects"

end # test_text_to_graphics
