mutable struct _WidgetTextMockEditor
    document::Any
end

function test_widget_text_editing()

_font = font_ubuntu_monospace_regular_20
_stub(t, f) = (length(t) * 10, 24)

# An editable WidgetText: content is a TextBlock recursed through the Text domain.
function _doc()
    content = TextBlock(TextString("edit me", _font, color_default))
    WidgetText(Point2D(0, 0), content)
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

@testset "typing into a WidgetText edits via the Text domain, re-rooted at content" begin
    doc = _doc()
    set_selection!(doc, _cursor(3))            # cursor after "edi"
    iomap = print_document(_proj(), nothing, doc, PrinterContext())

    op = read_intent(_proj(), iomap, KeyPress('X', "X", ModifierKeys()))
    @test op isa ReplaceStringRangeOperation
    # The widget prepended `content` to the Text-domain reference.
    @test op.reference.head == FieldReferenceStep("content")

    evaluate_operation(_WidgetTextMockEditor(doc), op)
    @test doc.content.elements[1].content == "ediXt me"
end

@testset "a disabled WidgetText accepts no edits" begin
    content = TextBlock(TextString("edit me", _font, color_default))
    doc = WidgetText(Point2D(0, 0), content; enabled=false)
    set_selection!(doc, _cursor(3))
    iomap = print_document(_proj(), nothing, doc, PrinterContext())
    @test iomap.output isa GraphicsCanvas                      # still renders
    @test read_intent(_proj(), iomap, KeyPress('X', "X", ModifierKeys())) === nothing
    @test doc.content.elements[1].content == "edit me"         # value unchanged
end

@testset "backspace and arrow navigation are re-rooted at content too" begin
    doc = _doc()
    set_selection!(doc, _cursor(4))            # cursor after "edit"
    iomap = print_document(_proj(), nothing, doc, PrinterContext())

    bs = read_intent(_proj(), iomap, KeyDown(:backspace, ModifierKeys()))
    @test bs isa ReplaceStringRangeOperation
    @test bs.reference.head == FieldReferenceStep("content")
    evaluate_operation(_WidgetTextMockEditor(doc), bs)
    @test doc.content.elements[1].content == "edi me"

    iomap2 = print_document(_proj(), nothing, doc, PrinterContext())
    arrow = read_intent(_proj(), iomap2, KeyDown(:left, ModifierKeys()))
    @test arrow isa ReplaceSelectionOperation
    @test arrow.path.head == FieldReferenceStep("content")
end

end # test_widget_text_editing
