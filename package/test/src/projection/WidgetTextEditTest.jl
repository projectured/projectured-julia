mutable struct _WidgetTextMockEditor
    document::Any
end

function test_widget_text_editing()

_font = font_ubuntu_monospace_regular_24
_stub(t, f) = (length(t) * 10, 24)

# An editable WidgetText: content is a TextText recursed through the Text domain.
function _doc()
    content = TextText(TextString("edit me", _font, color_default))
    WidgetText(Point2D(0, 0), content)
end

# Combined renderer: widget nodes via WidgetToGraphics, the recursed TextText via
# TextToGraphics.
function _proj()
    w2g = WidgetToGraphics(_font; measure=_stub)
    RecursiveProjection(TypeDispatchingProjection(vcat(
        w2g.dispatch,
        Pair{DataType,Any}[TextText => TextToGraphics(measure=_stub)],
    )))
end

# `content.elements[1].content{n}` — a cursor at char n inside the widget's text.
_cursor(n) = ConcreteReferencePath(FieldReference("content"),
    ConcreteReferencePath(FieldReference("elements"),
        ConcreteReferencePath(RangeReference(0, 1),
            ConcreteReferencePath(FieldReference("content"),
                ConcreteReferencePath(RangeReference(n, n), EmptyReferencePath())))))

@testset "WidgetText recurses Document content and renders to graphics" begin
    doc = _doc()
    iomap = projection_print(_proj(), nothing, doc, PrinterContext())
    @test iomap.output isa GraphicsCanvas
end

@testset "typing into a WidgetText edits via the Text domain, re-rooted at content" begin
    doc = _doc()
    set_selection!(doc, _cursor(3))            # cursor after "edi"
    iomap = projection_print(_proj(), nothing, doc, PrinterContext())

    op = projection_read(_proj(), iomap, KeyPress('X', "X", Modifiers()))
    @test op isa StringReplaceRangeOperation
    # The widget prepended `content` to the Text-domain reference.
    @test op.reference.head == FieldReference("content")

    evaluate_operation(_WidgetTextMockEditor(doc), op)
    @test doc.content.elements[1].content == "ediXt me"
end

@testset "backspace and arrow navigation are re-rooted at content too" begin
    doc = _doc()
    set_selection!(doc, _cursor(4))            # cursor after "edit"
    iomap = projection_print(_proj(), nothing, doc, PrinterContext())

    bs = projection_read(_proj(), iomap, KeyDown(:backspace, Modifiers()))
    @test bs isa StringReplaceRangeOperation
    @test bs.reference.head == FieldReference("content")
    evaluate_operation(_WidgetTextMockEditor(doc), bs)
    @test doc.content.elements[1].content == "edi me"

    iomap2 = projection_print(_proj(), nothing, doc, PrinterContext())
    arrow = projection_read(_proj(), iomap2, KeyDown(:left, Modifiers()))
    @test arrow isa ReplaceSelectionOperation
    @test arrow.path.head == FieldReference("content")
end

end # test_widget_text_editing
