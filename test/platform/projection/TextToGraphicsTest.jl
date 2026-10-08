function test_text_to_graphics()
_test_measure(cw, lh) = FixedMeasure(cw, lh - lh÷4, lh÷4, 0)

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
    TextString("Hello world this is a long text", StyleFont("Ubuntu Mono", 20), color_red),
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
    TextString("line1\nline2\nline3", StyleFont("Ubuntu Mono", 20), color_white),
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
    TextString("red text", StyleFont("Ubuntu Mono", 20), color_red),
    TextString(" blue text", StyleFont("Ubuntu Mono", 20), color_blue),
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
    TextString("short", StyleFont("Ubuntu Mono", 20), color_white),
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
st_hex = TextBlock(TextString("hex", StyleFont("Ubuntu Mono", 20), StyleColor(1.0, 0.53, 0.0, 1.0)))
sdl_hex = print_document(TextToGraphics(measure=_test_measure(10, 48)), st_hex).output
h = _texts(sdl_hex)[1]
# StyleColor is now carried through unchanged (no byte round-trip).
@test h.color == StyleColor(1.0, 0.53, 0.0, 1.0)

end # @testset "TextToGraphics"

@testset "TextToGraphics ListNode path" begin

# Build a TextBlock with ListNode elements: two paragraphs separated by TextNewline
node = ListNode(TextString("Hello world", StyleFont("Ubuntu Mono", 20), color_red))
push!(node, TextNewline(font=StyleFont("Ubuntu Mono", 20)))
push!(node, TextString("Second paragraph", StyleFont("Ubuntu Mono", 20), color_blue))

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
node = ListNode(TextString("Para 1", StyleFont("Ubuntu Mono", 20), color_white))

# Build a lazy chain of paragraphs
node2 = ListNode(TextNewline(font=StyleFont("Ubuntu Mono", 20)))
node.next = node2
node2.prev = node

node3 = ListNode(TextString("Para 2", StyleFont("Ubuntu Mono", 20), color_white))
set_cell_computation!(getfield(node2, :next), () -> begin
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

@testset "TextToGraphics reads a key on a list of text without walking it" begin

# Ten thousand paragraphs, each link computed when it is first read. The printer
# reads the first paragraph; a key must read no more, because a list can be
# endless and a list block keeps no line geometry for a key to move along.
font = StyleFont("Ubuntu Mono", 20)
computed = Ref(0)
function make_paragraph(i)
    text = ListNode(TextString("paragraph $i", font, color_white))
    newline = ListNode(TextNewline(font = font))
    text.next = newline
    newline.prev = text
    i < 10_000 && set_cell_computation!(getfield(newline, :next), () -> begin
        computed[] += 1
        following = make_paragraph(i + 1)
        following.prev = newline
        following
    end)
    text
end
block = TextBlock()
block.elements = make_paragraph(1)
p = TextToGraphics(measure = _test_measure(10, 20))
iomap = print_document(p, IdentityProjection(), block, PrinterContext())
printed = computed[]
@test printed <= 1
for key in (:up, :down, :home, :end, :return)
    @test read_intent(p, iomap, KeyDown(key, ModifierKeys(); time = 0.0)) === nothing
end
@test computed[] == printed

end # @testset "TextToGraphics reads a key on a list of text without walking it"

@testset "TextToGraphics inline image" begin

m = _test_measure(10, 18)
st = TextBlock(
    TextString("ab", StyleFont("Ubuntu Mono", 20), color_white),
    TextGraphics(ImageMemory(nothing), 64, 64),
    TextString("cd", StyleFont("Ubuntu Mono", 20), color_white),
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
    TextString("ab", StyleFont("Ubuntu Mono", 20), color_white),
    TextGraphics(ImageMemory(nothing), 64, 64),
    TextString("cd", StyleFont("Ubuntu Mono", 20), color_white),
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
# Left half → the caret before the image (flat 2, the end of "ab"); right half →
# the caret after it (flat 3, the start of "cd"). The image is one position of the
# caret stream.
@test is_reference_equal(left.path,  TextModule.make_flat_caret_reference(2))
@test is_reference_equal(right.path, TextModule.make_flat_caret_reference(3))
# The reader of that path reads the backward mapping of the element path.
@test is_reference_equal(map_reference_backward(p, iomap, click(10).path), left.path)

end # @testset "TextToGraphics inline image hit-test"

@testset "TextToGraphics maps a point back to the caret at it" begin

m = _test_measure(10, 18)
p = TextToGraphics(measure=m)
st = TextBlock(TextString("abc", StyleFont("Ubuntu Mono", 20), color_white))
iomap = print_document(p, st)
# Ten pixels to a character, from where the segment starts: a point 12 pixels in
# is nearest the boundary after "a", and one 28 pixels in the end of "abc".
segment = first(iomap.char_to_coord)
at(dx) = PointReferenceStep(segment.x + dx, segment.y + 5)
caret = map_reference_backward(p, iomap, at(12))
@test is_reference_equal(caret, TextModule.make_flat_caret_reference(1))
@test is_reference_equal(map_reference_backward(p, iomap, ConcreteReference(at(28))),
                         TextModule.make_flat_caret_reference(3))
# The reader of a click reads the same map.
click = read_intent(p, iomap, MouseClick(:left, segment.x + 12, segment.y + 5; time = 0.0))
@test is_reference_equal(click.path, caret)
# A reference that names neither a point nor an element maps to nothing.
@test map_reference_backward(p, iomap, EmptyReference()) === nothing

end # @testset "TextToGraphics maps a point back to the caret at it"

@testset "TextToGraphics renders fill_color as a background rect" begin

m = _test_measure(10, 18)
hl = TextString("hi", StyleFont("Ubuntu Mono", 20), color_red)
hl.fill_color = color_blue              # a highlighted span opts into a swatch
plain = TextString("xy", StyleFont("Ubuntu Mono", 20), color_red)
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
nl() = TextNewline(font=StyleFont("Ubuntu Mono", 20))
st = TextBlock(
    TextString("alpha", StyleFont("Ubuntu Mono", 20), color_white), nl(),
    TextString("beta",  StyleFont("Ubuntu Mono", 20), color_white), nl(),
    TextString("gamma", StyleFont("Ubuntu Mono", 20), color_white),
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
_span(s) = TextString(s, StyleFont("Ubuntu Mono", 20), color_white)
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
# offset; `get_flat_base` names it from the structural (line, span) coordinate.
fb(path, k)  = TextModule.get_flat_base(mkblock(), path) + k
cflat(op)    = (r = strip_reference_types(op isa ReplaceSelectionOperation ? op.path : op);
                (r.head::TextRangeReferenceStep).start)
coord(op)    = TextModule._flat_to_span(mkblock(), cflat(op))   # (span_path, char)
caret(block) = [(r.x, r.y, r.h) for r in _rects(print_document(p, block).output) if r.w == 2]
@test caret(set_selection!(mkblock(), TextModule.make_flat_caret_reference(fb(Int[1, 1], 0)))) == [(20, 0, 18)]
@test caret(set_selection!(mkblock(), TextModule.make_flat_caret_reference(fb(Int[2, 1], 3)))) == [(30, 18, 18)]

# A click on the second row selects inside *that line's* span; Down crosses into
# it; End goes to the end of the line the caret is already on.
iomap = print_document(p, set_selection!(mkblock(), TextModule.make_flat_caret_reference(fb(Int[1, 1], 0))))
click = read_intent(p, iomap, MouseClick(:left, 31, 20; time = 0.0))
@test click isa ReplaceSelectionOperation
@test coord(click) == ([2, 1], 3)
@test coord(read_intent(p, iomap, KeyDown(:down, ModifierKeys(); time = 0.0)))[1] == [2, 1]
@test coord(read_intent(p, iomap, KeyDown(:end, ModifierKeys(); time = 0.0))) == ([1, 1], 5)

# A blank line keeps its row. It has neither a glyph nor a terminating
# `TextNewline` to take a height from, so the block's prevailing font sizes it.
blank = print_document(p, TextBlock(TextLine(_span("a")), TextLine(), TextLine(_span("b")))).output
@test Int(blank.h) == 54
@test [t.y for t in _texts(blank)] == [0, 36]

# The empty group a *trailing* newline leaves behind is not a line, and must not
# grow a phantom blank row.
trailing = print_document(p, TextBlock(_span("a"), TextNewline(font = StyleFont("Ubuntu Mono", 20)))).output
@test Int(trailing.h) == 18

end # @testset "TextToGraphics lays out TextLine blocks"

@testset "TextColumnReferenceStep reserves the column-box geometry (variant 2)" begin

# Variant 2 (`TextColumnReferenceStep`) is reserved but has no producer yet; assert its
# geometry function directly on a hand-built two-row coord map (monospace, 10px/glyph).
_font = StyleFont("Ubuntu Mono", 20)
measure = FixedMeasure(10, 14, 4, 0)
p = TextToGraphics(measure = measure)
SC = TextModule.SegmentCoordinate
coord_map = [SC([1], 0, 6, 0,  0, _font, "abcdef", 60, 18),
             SC([3], 0, 6, 0, 20, _font, "ghijkl", 60, 18)]
# Flat space: row 1 chars 0..6, an implicit break at 6, row 2 chars 7..13.
span_flat_offsets = Dict([1] => 0, [3] => 7)

# A column from flat 1 (row 1 col x=10) to flat 11 (row 2 char 4, col x=40): the
# rectangle [10 … 40] painted on both rows, regardless of the glyphs on each.
rects = TextModule._compute_column_geo(coord_map, span_flat_offsets, 1, 11, p)
@test length(rects) == 2                          # one rect per spanned row
@test all(r -> r[1] == 10 && r[3] == 30, rects)   # same [col10 … col40] box on every row
@test [r[2] for r in rects] == [0, 20]            # top row then bottom row

# Coinciding columns (zero width) or an unresolvable endpoint yield no box.
@test TextModule._compute_column_geo(coord_map, span_flat_offsets, 2, 9, p) == []

# A `TextColumnReferenceStep` selection is structural — not a character cursor, so char
# motion / flat edits decline (block editing is future work).
sel = ConcreteReference(TextColumnReferenceStep(1, 11), EmptyReference())
@test TextModule.is_structural_selection(sel)
@test TextModule._text_flat_selection(
          set_selection!(TextBlock(TextString("abcdef", _font, color_default)), sel)) === nothing

end # @testset "TextColumnReferenceStep column-box geometry"

@testset "TextSpanReferenceStep draws content-hugging per-row rects (variant 3)" begin

# A structural (whole-node) selection maps to a single contiguous TextSpanReferenceStep
# flat range that crosses the interior lines' indent/newline chrome. It must be drawn
# as one rect per row hugging that row's *content* — not a bounding box. Model the
# JSON `address` shape (monospace, 10px/glyph): a first line at indent 0, an interior
# line whose leading indent is a separate whitespace span, and a close line.
_font = StyleFont("Ubuntu Mono", 20)
measure = FixedMeasure(10, 14, 4, 0)
p = TextToGraphics(measure = measure)
SC = TextModule.SegmentCoordinate
# Each coordinate carries the line box of its row: the rows are 20 apart.
line = 20
#   row y=0 : "AB{"          flat 0..3   (node's first line, starts at x=0)
#   break                    flat 3
#   row y=20: "    " indent  flat 4..8   (blank — must NOT anchor the row)
#   row y=20: "CD"           flat 8..10  (content at x=40, the indentation level)
#   break                    flat 10
#   row y=40: "  " indent    flat 11..13 (blank)
#   row y=40: "}"            flat 13..14 (the close, at x=20)
coord_map = [SC([1], 0, 3,  0,  0, _font, "AB{",  30, line),
             SC([2], 0, 4,  0, 20, _font, "    ", 40, line),
             SC([3], 0, 2, 40, 20, _font, "CD",   20, line),
             SC([4], 0, 2,  0, 40, _font, "  ",   20, line),
             SC([5], 0, 1, 20, 40, _font, "}",    10, line)]
span_flat_offsets = Dict([1] => 0, [2] => 4, [3] => 8, [4] => 11, [5] => 13)

rects = TextModule._compute_span_rows(coord_map, span_flat_offsets, 0, 14, p)
@test length(rects) == 3                              # one rect per visual row
@test [r[2] for r in rects] == [0, 20, 40]            # top to bottom
@test all(r -> r[4] == line, rects)                   # each the line box of its row
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
@test TextModule._compute_span_rows(coord_map, span_flat_offsets, 4, 8, p) == []

end # @testset "TextSpanReferenceStep content-hugging per-row rects"

@testset "TextToGraphics draws a caret in an empty span, one line high" begin

m = _test_measure(10, 18)
for projection in (TextToGraphics(measure=m),
                   ChainingProjection(WordWrapping(max_width=200, measure=m), TextToGraphics(measure=m)))
    block = TextBlock(TextString("", StyleFont("Ubuntu Mono", 20), color_red))
    canvas = print_document(projection, set_selection!(block, TextModule.make_flat_caret_reference(0))).output
    @test [(r.x, r.y, r.w, r.h) for r in _rects(canvas)] == [(0, 0, 2, 18)]
    @test Int(canvas.h) == 18
end

# A caret after a '\n' at the end of a span stands on a line with no glyph yet,
# and it is as tall as a line all the same.
block = TextBlock(TextString("ab\n", StyleFont("Ubuntu Mono", 20), color_red))
canvas = print_document(TextToGraphics(measure=m), set_selection!(block, TextModule.make_flat_caret_reference(3))).output
@test [(r.x, r.y, r.w, r.h) for r in _rects(canvas)] == [(0, 18, 2, 18)]

end # @testset "TextToGraphics empty span"

@testset "TextToGraphics moves the caret onto an empty line and off it" begin

m = _test_measure(10, 18)
p = TextToGraphics(measure=m)
block(text, k) = set_selection!(TextBlock(TextString(text, StyleFont("Ubuntu Mono", 20), color_red)),
                                TextModule.make_flat_caret_reference(k))
flat(op) = (strip_reference_types(op.path).head::TextRangeReferenceStep).start
press(text, k, key) = (op = read_intent(p, print_document(p, block(text, k)), KeyDown(key, ModifierKeys(); time = 0.0));
                       op === nothing ? nothing : flat(op))
# "a", an empty line, then "b": Up goes from "b" onto the empty line, then onto
# "a", and Down comes back the same way.
@test press("a\n\nb", 3, :up) == 2
@test press("a\n\nb", 2, :up) == 0
@test press("a\n\nb", 0, :down) == 2
@test press("a\n\nb", 2, :down) == 3
# The line after a line break at the end of the text.
@test press("ab\n", 3, :up) == 0
@test press("ab\n", 0, :down) == 3
# An empty text has no line above and none below, so the key goes to the caller.
@test press("", 0, :up) === nothing
@test press("", 0, :down) === nothing
# A text with no glyph keeps its one line of height.
@test Int(print_document(p, block("", 0)).output.h) == 18

end # @testset "TextToGraphics empty line"

# A text reference maps forward to the characters of the text node that draws it,
# so the box of a part of a text is exact: here each character is 10 pixels wide.
@testset "TextToGraphics maps a text reference to the characters that draw it" begin
    measure = _test_measure(10, 18)
    projection = TextToGraphics(measure = measure)
    text_block = TextBlock(TextString("hello world", StyleFont("Ubuntu Mono", 20), color_black))
    iomap = print_document(projection, text_block)
    output = iomap.output
    box_of(reference) = find_reference_box(output, map_reference_forward(projection, iomap, reference);
                                           measure = measure)
    # The caret before `world`, a range of no width.
    caret = box_of(make_flat_caret_reference(6))
    @test (caret.x, caret.width) == (60, 0)
    # The characters of `world`.
    world = box_of(make_flat_range_reference(6, 11))
    @test (world.x, world.width) == (60, 50)
    @test world.height > 0
    # The text itself is its own canvas.
    @test map_reference_forward(projection, iomap, EmptyReference()) == EmptyReference()
    # A range across two visual lines maps to the region of its rows, after the
    # canvas of its line group: 50 pixels wide, and as high as both rows.
    two_lines = TextBlock(TextString("hello\nworld", StyleFont("Ubuntu Mono", 20), color_black))
    two_iomap = print_document(projection, two_lines)
    both = map_reference_forward(projection, two_iomap, make_flat_range_reference(0, 11))
    @test last(collect(get_reference_steps(both))) isa RegionReferenceStep
    box = find_reference_box(two_iomap.output, both; measure = measure)
    @test (box.x, box.width) == (0, 50)
    line = box_of(make_flat_range_reference(0, 5))
    @test box.height == 2 * line.height
end

# A text whose spans are a lazy list maps a span to the text node that draws it in
# the list of paragraph canvases. Spans and paragraphs count from their heads.
@testset "TextToGraphics maps a span of a lazy list to the text that draws it" begin
    measure = FixedMeasure(10, 18, 6, 0)
    projection = TextToGraphics(measure = measure)
    font = StyleFont("Ubuntu Mono", 20)
    head = ListNode(TextString("one", font, color_black))
    push!(head, TextString("two", font, color_black))
    push!(head, TextNewline(font = font))
    push!(head, TextString("three", font, color_black))
    pushfirst!(head, TextNewline(font = font))
    pushfirst!(head, TextString("zero", font, color_black))
    text_block = TextBlock()
    text_block.elements = head
    iomap = print_document(projection, IdentityProjection(), text_block, PrinterContext())
    spans(start, stop, rest = EmptyReference()) =
        ConcreteReference(FieldReferenceStep("elements"), ConcreteReference(RangeReferenceStep(start, stop), rest))
    image(reference) = map_reference_forward(projection, iomap, reference)
    box_of(reference) = find_reference_box(iomap.output, image(reference); measure = measure)
    # `two` is the second text of the head paragraph.
    two = box_of(spans(1, 2))
    @test (two.x, two.y, two.width) == (30, 0, 30)
    # `three` is the first text of the paragraph after it, one line lower.
    three = box_of(spans(3, 4))
    @test (three.x, three.width) == (0, 50)
    @test three.y == two.height
    # The characters `hr` of `three`.
    characters = box_of(spans(3, 4, ConcreteReference(FieldReferenceStep("content"),
                                                      ConcreteReference(RangeReferenceStep(1, 3), EmptyReference()))))
    @test (characters.x, characters.y, characters.width) == (10, three.y, 20)
    # `zero`, before the newline before the head, is one line above the head.
    zero = box_of(spans(-2, -1))
    @test (zero.x, zero.y, zero.width) == (0, -two.height, 40)
    # A newline draws no text.
    @test image(spans(2, 3)) === nothing
    # `one two` is a region of the head paragraph.
    both = image(spans(0, 2))
    @test last(collect(get_reference_steps(both))) isa RegionReferenceStep
    box = find_reference_box(iomap.output, both; measure = measure)
    @test (box.x, box.y, box.width, box.height) == (0, 0, 60, two.height)
    # From `two` to `three` is a region of the canvas of the text, two lines high.
    across = box_of(spans(1, 4))
    @test (across.x, across.y, across.width, across.height) == (0, 0, 60, 2 * two.height)
end

# A part of a lazy list of numbers maps forward through the whole chain, to the
# text that draws it, also a part that the printer did not reach yet and a part
# before the head.
@testset "a part of a lazy list maps forward to the text that draws it" begin
    measure = FixedMeasure(10, 18, 6, 0)
    element(k, rest = EmptyReference()) = ConcreteReference(ElementReferenceStep(k), rest)
    function box_of(document, projection, reference)
        iomap = print_document(projection, document)
        image = map_reference_forward(projection, iomap, annotate_reference_types(document, reference))
        image === nothing && return nothing
        find_reference_box(unwrap_cell(get_iomap_output(iomap)), image; measure = measure)
    end
    primes = make_lazy_document_example()
    projection = make_lazy_projection_example(measure = measure)
    first = box_of(primes, projection, element(1))
    @test (first.x, first.y, first.width) == (0, 0, 10)
    # The 40th prime, 173, is three characters wide, 39 lines below the first.
    fortieth = box_of(primes, projection, element(40))
    @test (fortieth.y, fortieth.width) == (39 * first.height, 30)
    # The caret after the first digit of the fifth prime, 11.
    caret = box_of(primes, projection,
                   element(5, ConcreteReference(FieldReferenceStep("value"),
                                                ConcreteReference(PositionReferenceStep(1), EmptyReference()))))
    @test (caret.x, caret.y, caret.width) == (10, 4 * first.height, 0)
    # Before the head: element 0 is -2 and element -2 is -5.
    both_ways = make_lazy_bidirectional_document_example()
    projection = make_lazy_bidirectional_projection_example(measure = measure)
    @test box_of(both_ways, projection, element(0)).y == -first.height
    @test box_of(both_ways, projection, element(-2)).y == -3 * first.height
end

# A lazy list of lines is drawn as a canvas for each line. A part of a line maps
# to the text node that draws it; lines and canvases count from their heads.
@testset "TextToGraphics draws a lazy list of lines" begin
    measure = FixedMeasure(10, 18, 6, 0)
    projection = TextToGraphics(measure = measure)
    font = StyleFont("Ubuntu Mono", 20)
    head = ListNode(TextLine(TextString("one", font, color_black), TextString("two", font, color_black)))
    push!(head, TextLine(TextString("three", font, color_black); indentation = 2))
    pushfirst!(head, TextLine(TextString("zero", font, color_black)))
    text_block = TextBlock()
    text_block.elements = head
    iomap = print_document(projection, IdentityProjection(), text_block, PrinterContext())
    range_of(start, stop, rest = EmptyReference()) =
        ConcreteReference(FieldReferenceStep("elements"), ConcreteReference(RangeReferenceStep(start, stop), rest))
    content(start, stop) = ConcreteReference(FieldReferenceStep("content"),
                                             ConcreteReference(RangeReferenceStep(start, stop), EmptyReference()))
    image(reference) = map_reference_forward(projection, iomap, reference)
    box_of(reference) = find_reference_box(iomap.output, image(reference); measure = measure)
    # `two` is the second span of the head line.
    two = box_of(range_of(0, 1, range_of(1, 2)))
    @test (two.x, two.y, two.width) == (30, 0, 30)
    # The next line is one line lower, and starts at its indentation; a whole line
    # with one text maps to that text.
    three = box_of(range_of(1, 2))
    @test (three.x, three.y, three.width) == (20, two.height, 50)
    # The characters `hr` of `three`.
    characters = box_of(range_of(1, 2, range_of(0, 1, content(1, 3))))
    @test (characters.x, characters.y, characters.width) == (30, three.y, 20)
    # `zero`, the line before the head, is one line above it.
    zero = box_of(range_of(-1, 0))
    @test (zero.x, zero.y, zero.width) == (0, -two.height, 40)
    # The head line, with its two spans, is a region of its canvas.
    both = image(range_of(0, 1))
    @test last(collect(get_reference_steps(both))) isa RegionReferenceStep
    box = find_reference_box(iomap.output, both; measure = measure)
    @test (box.x, box.y, box.width) == (0, 0, 60)
end

@testset "TextToGraphics starts a row at each soft break of a line" begin

m = _test_measure(10, 18)
p = TextToGraphics(measure = m)
font = StyleFont("Ubuntu Mono", 20)
make_block() = (line = TextLine(TextString("alpha beta gamma", font, color_white); indentation = 2);
                getfield(line, :soft_breaks)[] = [6, 11];
                TextBlock(TextDocument[line, TextLine(TextString("next", font, color_white))]))

# Each row starts at the indentation of the line; the next line follows the rows.
canvas = print_document(p, make_block()).output
@test [(t.text, t.x, t.y) for t in _texts(canvas)] ==
      [("alpha ", 20, 0), ("beta ", 20, 18), ("gamma", 20, 36), ("next", 0, 54)]

# A caret at a soft break stands at the start of the lower row, where a typed
# character goes; a caret inside a row stands in it.
caret(block) = [(r.x, r.y) for r in _rects(print_document(p, block).output) if r.w == 2]
@test caret(set_selection!(make_block(), TextModule.make_flat_caret_reference(8))) == [(20, 18)]
@test caret(set_selection!(make_block(), TextModule.make_flat_caret_reference(9))) == [(30, 18)]
@test caret(set_selection!(make_block(), TextModule.make_flat_caret_reference(4))) == [(40, 0)]

# A click on the second row puts the caret in that row.
iomap = print_document(p, make_block())
click = read_intent(p, iomap, MouseClick(:left, 41, 20; time = 0.0))
@test click isa ReplaceSelectionOperation
@test is_reference_equal(click.path, TextModule.make_flat_caret_reference(10))

end # @testset "TextToGraphics starts a row at each soft break of a line"

end # test_text_to_graphics
