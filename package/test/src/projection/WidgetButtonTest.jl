mutable struct _WidgetButtonMockEditor
    document::Any
end

function test_widget_button_behavior()

_font = font_ubuntu_monospace_regular_24
_stub(t, f) = (length(t) * 10, 24)

# Recursively scan a canvas's elements for a GraphicsImage (canvases nest other
# canvases as elements).
function _canvas_has_image(canvas)
    for elem in canvas.elements
        elem isa GraphicsImage && return true
        elem isa GraphicsCanvas && _canvas_has_image(elem) && return true
    end
    false
end

# The standard widget renderer used by the button examples.
_proj() = SequentialProjection(
    WidgetHoverTrackingProjection(inner = RecursiveProjection(TypeDispatchingProjection(
        WidgetToGraphics(_font; measure=_stub).dispatch))))

# A lone button with a side-effecting action over a captured counter.
function _button_doc()
    count = Ref(0)
    button = WidgetButton(Point2D(0, 0), Point2D(120, 40), "Go";
                          action = (_editor) -> (count[] += 1))
    (button, count)
end

@testset "button click invokes its action via InvokeWidgetActionOperation" begin
    button, count = _button_doc()
    proj = _proj()
    iomap = projection_print(proj, nothing, button, PrinterContext())
    @test iomap.output isa GraphicsCanvas

    # Click inside the button (its canvas is at 0,0 sized 120×40).
    op = projection_read(proj, iomap, MousePress(:left, 10, 10, Modifiers()))
    @test op isa InvokeWidgetActionOperation
    @test op.widget === button

    evaluate_operation(_WidgetButtonMockEditor(button), op)
    @test count[] == 1
    evaluate_operation(_WidgetButtonMockEditor(button), op)
    @test count[] == 2
end

@testset "a non-left click does nothing" begin
    button, _ = _button_doc()
    proj = _proj()
    iomap = projection_print(proj, nothing, button, PrinterContext())
    @test projection_read(proj, iomap, MousePress(:right, 10, 10, Modifiers())) === nothing
end

@testset "press / release drive the transient pressed flag" begin
    button, _ = _button_doc()
    proj = _proj()
    iomap = projection_print(proj, nothing, button, PrinterContext())

    down = projection_read(proj, iomap, MouseDown(:left, 10, 10, Modifiers()))
    @test down isa ReplaceReferencedValue
    @test down.value == true
    evaluate_operation(_WidgetButtonMockEditor(button), down)
    @test button.pressed == true

    up = projection_read(proj, iomap, MouseUp(:left, 10, 10, Modifiers()))
    @test up isa ReplaceReferencedValue
    @test up.value == false
    evaluate_operation(_WidgetButtonMockEditor(button), up)
    @test button.pressed == false
end

@testset "a move over the button sets its hovered flag" begin
    button, _ = _button_doc()
    proj = _proj()
    iomap = projection_print(proj, nothing, button, PrinterContext())
    op = projection_read(proj, iomap, MouseMove(10, 10, :none, Modifiers()))
    @test op isa ReplaceReferencedValue
    @test op.document === button && op.value == true
    evaluate_operation(_WidgetButtonMockEditor(button), op)
    @test button.hovered == true
end

@testset "the hover tracker clears the previously-hovered button on leave" begin
    # Two buttons side by side inside a composite.
    a = WidgetButton(Point2D(0, 0), Point2D(100, 40), "A"; action = (_e) -> nothing)
    b = WidgetButton(Point2D(120, 0), Point2D(100, 40), "B"; action = (_e) -> nothing)
    composite = WidgetComposite(Point2D(0, 0), Any[a, b])
    proj = _proj()                          # one tracker instance, reused across reads
    ed = _WidgetButtonMockEditor(composite)

    iomap = projection_print(proj, nothing, composite, PrinterContext())
    op_a = projection_read(proj, iomap, MouseMove(10, 10, :none, Modifiers()))
    @test op_a isa ReplaceReferencedValue && op_a.document === a
    evaluate_operation(ed, op_a)
    @test a.hovered == true

    # Move onto B: the tracker clears A (hover + press) and sets B.
    iomap2 = projection_print(proj, nothing, composite, PrinterContext())
    op_b = projection_read(proj, iomap2, MouseMove(130, 10, :none, Modifiers()))
    @test op_b isa CompoundOperation
    evaluate_operation(ed, op_b)
    @test a.hovered == false
    @test b.hovered == true

    # Move into dead space: B clears, nothing new hovered.
    iomap3 = projection_print(proj, nothing, composite, PrinterContext())
    op_void = projection_read(proj, iomap3, MouseMove(300, 300, :none, Modifiers()))
    evaluate_operation(ed, op_void)
    @test b.hovered == false
end

@testset "button click inside a composite still reaches the action" begin
    count = Ref(0)
    button = WidgetButton(Point2D(0, 0), Point2D(100, 40), "X";
                          action = (_e) -> (count[] += 1))
    composite = WidgetComposite(Point2D(0, 0), Any[button])
    proj = _proj()
    iomap = projection_print(proj, nothing, composite, PrinterContext())
    op = projection_read(proj, iomap, MousePress(:left, 10, 10, Modifiers()))
    @test op isa InvokeWidgetActionOperation && op.widget === button
    evaluate_operation(_WidgetButtonMockEditor(composite), op)
    @test count[] == 1
end

@testset "an ImageDocument content renders as a GraphicsImage" begin
    # A 2×2 RGBA buffer carried by an ImageMemory, so no decode/SDL is needed.
    pixels = UInt8[0xff,0x00,0x00,0xff, 0x00,0xff,0x00,0xff,
                   0x00,0x00,0xff,0xff, 0xff,0xff,0xff,0xff]
    image = ImageMemory((pixels, 2, 2))
    button = WidgetButton(Point2D(0, 0), Point2D(40, 40), image; action = (_e) -> nothing)
    iomap = projection_print(_proj(), nothing, button, PrinterContext())
    canvas = iomap.output
    @test canvas isa GraphicsCanvas
    @test _canvas_has_image(canvas)
end

@testset "a label with image content renders a GraphicsImage at its natural size" begin
    pixels = UInt8[0xff,0x00,0x00,0xff, 0x00,0xff,0x00,0xff,
                   0x00,0x00,0xff,0xff, 0xff,0xff,0xff,0xff]
    label = WidgetLabel(Point2D(0, 0), ImageMemory((pixels, 2, 2)))
    iomap = projection_print(_proj(), nothing, label, PrinterContext())
    @test _canvas_has_image(iomap.output)
end

end # test_widget_button_behavior
