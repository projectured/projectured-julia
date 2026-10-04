mutable struct _WidgetTextMockEditor
    document::Any
end

# A language of the tests: its first character is red.
ProjecturedPlatform.WidgetModule.compute_code_pieces(::Val{:widget_text_test_code}, text::AbstractString, appearance) =
    isempty(text) ? Tuple{Int,Any}[(0, nothing)] : Tuple{Int,Any}[(1, color_red), (length(text) - 1, nothing)]

function test_widget_text_editing()

_font = StyleFont("Ubuntu Mono", 20)
_stub = FixedMeasure(10, 18, 6, 0)

# An editable WidgetText: content is a TextBlock recursed through the Text domain.
function _doc()
    content = TextBlock(TextString("edit me", _font, color_default))
    WidgetText(content)
end

# Combined renderer: widget nodes via WidgetToGraphics, the recursed TextBlock via
# TextToGraphics.
function _proj()
    w2g = WidgetToGraphics(_font; measure=_stub)
    RecursiveProjection(TypeDispatchingProjection(vcat(
        w2g.dispatch,
        Pair{Type,Any}[TextBlock => TextToGraphics(measure=_stub)],
    )))
end

# `content` + flat text caret at offset n — a cursor at char n inside the widget's
# single-span text (flat offset == char index for one span).
_cursor(n) = ConcreteReference(FieldReferenceStep("content"),
    ConcreteReference(TextRangeReferenceStep(n, n), EmptyReference()))

@testset "WidgetText recurses Document content and renders to graphics" begin
    doc = _doc()
    iomap = print_document(_proj(), nothing, doc, PrinterContext())
    @test iomap.output isa GraphicsCanvas
end

@testset "a WidgetText has the control padding of the theme, unless it gives its own" begin
    # The same text with the default padding and with none: the default adds the
    # room of the theme's control padding, left and right at the sides and top
    # and bottom above and below, and a padding the document gives is kept.
    padding = make_scaled_theme(make_slate_light_theme(font = _font)).control_padding
    extent(document) = (output = print_document(_proj(), nothing, document, PrinterContext()).output;
                        (Int(output.w), Int(output.h)))
    padded, bare = extent(WidgetText("edit me")), extent(WidgetText("edit me"; padding = Inset(0, 0, 0, 0)))
    @test padded .- bare == (padding.left[] + padding.right[], padding.top[] + padding.bottom[])
end

@testset "typing into a WidgetText edits via the Text domain, re-rooted at content" begin
    doc = _doc()
    set_selection!(doc, _cursor(3))            # cursor after "edi"
    iomap = print_document(_proj(), nothing, doc, PrinterContext())

    op = read_intent(_proj(), iomap, KeyPress('X', "X", ModifierKeys(); time = 0.0))
    @test op isa ReplaceStringRangeOperation
    # The widget prepended `content` to the Text-domain reference.
    @test op.reference.head == FieldReferenceStep("content")

    evaluate_operation(_WidgetTextMockEditor(doc), op)
    @test doc.content.elements[1].content == "ediXt me"
end

@testset "a field of code draws a span for each piece, and its edits stay ranges of its content" begin
    doc = WidgetText("abc"; language = :widget_text_test_code)
    set_selection!(doc, ConcreteReference(FieldReferenceStep("content"),
                                          ConcreteReference(RangeReferenceStep(2, 2), EmptyReference())))
    iomap = print_document(_proj(), nothing, doc, PrinterContext())
    spans = collect(iomap.content_iomap.input.elements)
    @test [span.content for span in spans] == ["a", "bc"]
    @test spans[1].font_color == color_red
    op = read_intent(_proj(), iomap, KeyPress('X', "X", ModifierKeys(); time = 0.0))
    @test op isa ReplaceStringRangeOperation
    @test strip_reference_types(op.reference) == ConcreteReference(FieldReferenceStep("content"),
        ConcreteReference(RangeReferenceStep(2, 2), EmptyReference()))
    # An empty field of code is one empty span.
    empty = print_document(_proj(), nothing, WidgetText(""; language = :widget_text_test_code), PrinterContext())
    @test [span.content for span in empty.content_iomap.input.elements] == [""]
end

@testset "an empty field shows its placeholder below its caret, and a press puts the caret at its start" begin
    doc = WidgetText(""; placeholder = "age > 30")
    iomap = print_document(_proj(), nothing, doc, PrinterContext())
    find_placeholder() = findfirst(e -> e isa GraphicsText && e.text == "age > 30", collect(iomap.output.elements))
    k = find_placeholder()
    @test k !== nothing
    @test iomap.output.elements[k].color != color_default
    # The content, which holds the caret, draws after it, and the box is as wide as it.
    @test findfirst(e -> e isa GraphicsCanvas, collect(iomap.output.elements)) > k
    @test iomap.output.w >= 8 * 10
    op = read_intent(_proj(), iomap, MouseClick(:left, 60, 5, 1, ModifierKeys(); time = 0.0))
    @test op isa ReplaceSelectionOperation
    @test strip_reference_types(op.path) == ConcreteReference(FieldReferenceStep("content"),
        ConcreteReference(RangeReferenceStep(0, 0), EmptyReference()))
    # A field with a text shows no placeholder.
    doc.content = "a"
    @test find_placeholder() === nothing
    doc.content = ""
    @test find_placeholder() !== nothing
end

@testset "a disabled WidgetText accepts no edits" begin
    content = TextBlock(TextString("edit me", _font, color_default))
    doc = WidgetText(content; enabled=false)
    set_selection!(doc, _cursor(3))
    iomap = print_document(_proj(), nothing, doc, PrinterContext())
    @test iomap.output isa GraphicsCanvas                      # still renders
    @test read_intent(_proj(), iomap, KeyPress('X', "X", ModifierKeys(); time = 0.0)) === nothing
    @test doc.content.elements[1].content == "edit me"         # value unchanged
end

@testset "backspace and arrow navigation are re-rooted at content too" begin
    doc = _doc()
    set_selection!(doc, _cursor(4))            # cursor after "edit"
    iomap = print_document(_proj(), nothing, doc, PrinterContext())

    bs = read_intent(_proj(), iomap, KeyDown(:backspace, ModifierKeys(); time = 0.0))
    @test bs isa ReplaceStringRangeOperation
    @test bs.reference.head == FieldReferenceStep("content")
    evaluate_operation(_WidgetTextMockEditor(doc), bs)
    @test doc.content.elements[1].content == "edi me"

    iomap2 = print_document(_proj(), nothing, doc, PrinterContext())
    arrow = read_intent(_proj(), iomap2, KeyDown(:left, ModifierKeys(); time = 0.0))
    @test arrow isa ReplaceSelectionOperation
    @test arrow.path.head == FieldReferenceStep("content")
end

# Each drawn text and where it starts, in the frame the widget is placed in.
function _drawn_texts(canvas, ox = 0, oy = 0, found = Tuple{String,Int,Int}[])
    x = ox + Int(canvas.x); y = oy + Int(canvas.y)
    for element in canvas.elements
        if element isa GraphicsText
            push!(found, (String(element.text), x + Int(element.x), y + Int(element.y)))
        elseif element isa GraphicsCanvas
            _drawn_texts(element, x, y, found)
        end
    end
    found
end

@testset "a WidgetTextarea edits its text, and Return breaks the line" begin
    content = TextBlock(TextString("one two", _font, color_default))
    doc = WidgetTextarea(content; position = Point2D(40, 40), rows = 3)
    set_selection!(doc, _cursor(3))            # cursor after "one"
    iomap = print_document(_proj(), nothing, doc, PrinterContext())

    typed = read_intent(_proj(), iomap, KeyPress('X', "X", ModifierKeys(); time = 0.0))
    @test typed isa ReplaceStringRangeOperation
    @test typed.reference.head == FieldReferenceStep("content")
    broken = read_intent(_proj(), iomap, KeyDown(:return, ModifierKeys(); time = 0.0))
    @test broken isa ReplaceStringRangeOperation
    @test broken.replacement == "\n"
    @test broken.reference.head == FieldReferenceStep("content")
    # Tab is not text, so it goes on to move the focus.
    @test read_intent(_proj(), iomap, KeyDown(:tab, ModifierKeys(); time = 0.0)) === nothing

    evaluate_operation(_WidgetTextMockEditor(doc), broken)
    @test doc.content.elements[1].content == "one\n two"
    # The two lines are drawn one below the other.
    lines = [(text, y) for (text, _, y) in _drawn_texts(iomap.output) if !isempty(strip(text))]
    @test any(line -> occursin("one", line[1]), lines)
    @test any(line -> occursin("two", line[1]), lines)
    one_y = first(y for (text, y) in lines if occursin("one", text))
    two_y = first(y for (text, y) in lines if occursin("two", text))
    @test two_y > one_y

    # A press on the drawn second line puts the caret into that line. The test is
    # the window: the press is in the frame of the textarea's own canvas.
    _, x, y = first(t for t in _drawn_texts(iomap.output) if occursin("two", t[1]))
    click = read_intent(_proj(), iomap, MouseClick(:left, x + 25 - Int(iomap.output.x), y + 4 - Int(iomap.output.y),
                                                   ModifierKeys(); time = 0.0))
    @test click isa ReplaceSelectionOperation
    @test click.path.head == FieldReferenceStep("content")
    @test click.path.tail.head isa TextRangeReferenceStep
    @test click.path.tail.head.start > 4       # past "one" and the line break
end

# A caret in a plain string is a range of the `content` field itself.
_plain_cursor(n) = ConcreteReference(FieldReferenceStep("content"),
    ConcreteReference(RangeReferenceStep(n, n), EmptyReference()))

# The caret a widget holds, with the node types of the path left out.
_held_caret(widget) = strip_reference_types(widget.selection)

@testset "a disabled WidgetTextarea takes no edit" begin
    content = TextBlock(TextString("one", _font, color_default))
    off = WidgetTextarea(content; enabled = false)
    set_selection!(off, _cursor(1))
    iomap = print_document(_proj(), nothing, off, PrinterContext())
    @test read_intent(_proj(), iomap, KeyPress('X', "X", ModifierKeys(); time = 0.0)) === nothing
    @test read_intent(_proj(), iomap, KeyDown(:return, ModifierKeys(); time = 0.0)) === nothing
    @test read_intent(_proj(), iomap, MouseClick(:left, 10, 10, ModifierKeys(); time = 0.0)) === nothing
    @test off.content.elements[1].content == "one"

    plain = WidgetTextarea("one\ntwo"; enabled = false)
    set_selection!(plain, _plain_cursor(1))
    plain_iomap = print_document(_proj(), nothing, plain, PrinterContext())
    @test read_intent(_proj(), plain_iomap, KeyPress('X', "X", ModifierKeys(); time = 0.0)) === nothing
    @test plain.content == "one\ntwo"
end

@testset "a WidgetText of a plain string edits the string" begin
    doc = WidgetText("edit me")
    iomap = print_document(_proj(), nothing, doc, PrinterContext())
    # With no caret the string is drawn whole, and a key has nowhere to go.
    @test occursin("edit me", join(text for (text, _, _) in _drawn_texts(iomap.output)))
    @test read_intent(_proj(), iomap, KeyPress('X', "X", ModifierKeys(); time = 0.0)) === nothing

    # A press puts the caret into the string, under the pointer.
    _, x, y = first(t for t in _drawn_texts(iomap.output) if startswith(t[1], "edit"))
    click = read_intent(_proj(), iomap, MouseClick(:left, x + 32, y + 4, ModifierKeys(); time = 0.0))
    @test click isa ReplaceSelectionOperation
    @test click.path == _plain_cursor(3)
    evaluate_operation(_WidgetTextMockEditor(doc), click)
    @test _held_caret(doc) == _plain_cursor(3)

    # A typed letter is a string edit of the field, and the caret moves past it.
    typed = read_intent(_proj(), iomap, KeyPress('X', "X", ModifierKeys(); time = 0.0))
    @test typed isa ReplaceStringRangeOperation
    @test typed.reference == _plain_cursor(3)
    evaluate_operation(_WidgetTextMockEditor(doc), typed)
    @test doc.content == "ediXt me"
    @test _held_caret(doc) == _plain_cursor(4)
    @test occursin("ediXt me", join(text for (text, _, _) in _drawn_texts(iomap.output)))

    # Backspace and an arrow go through the text domain too.
    erased = read_intent(_proj(), iomap, KeyDown(:backspace, ModifierKeys(); time = 0.0))
    evaluate_operation(_WidgetTextMockEditor(doc), erased)
    @test doc.content == "edit me"
    moved = read_intent(_proj(), iomap, KeyDown(:left, ModifierKeys(); time = 0.0))
    @test moved isa ReplaceSelectionOperation && moved.path == _plain_cursor(2)

    # A validator sees the edit of a plain string as it sees any other.
    digits = WidgetText("12"; validator = make_numeric_validator())
    set_selection!(digits, _plain_cursor(2))
    digits_iomap = print_document(_proj(), nothing, digits, PrinterContext())
    @test read_intent(_proj(), digits_iomap, KeyPress('a', "a", ModifierKeys(); time = 0.0)) === nothing
    @test read_intent(_proj(), digits_iomap, KeyPress('3', "3", ModifierKeys(); time = 0.0)) isa
          ReplaceStringRangeOperation
end

@testset "a WidgetTextarea of a plain string edits the string, and Return breaks the line" begin
    doc = WidgetTextarea("one two"; rows = 3)
    set_selection!(doc, _plain_cursor(3))
    iomap = print_document(_proj(), nothing, doc, PrinterContext())
    broken = read_intent(_proj(), iomap, KeyDown(:return, ModifierKeys(); time = 0.0))
    @test broken isa ReplaceStringRangeOperation
    @test broken.replacement == "\n"
    evaluate_operation(_WidgetTextMockEditor(doc), broken)
    @test doc.content == "one\n two"
    lines = [(text, y) for (text, _, y) in _drawn_texts(iomap.output) if !isempty(strip(text))]
    one_y = first(y for (text, y) in lines if occursin("one", text))
    two_y = first(y for (text, y) in lines if occursin("two", text))
    @test two_y > one_y
end

end # test_widget_text_editing
