mutable struct _PcEditor
    document::Any
end

function test_projection_configuring()

_font = font_ubuntu_monospace_regular_20
_mkchange(g, o) = IntentModule.Intent(g, o)
_content_ref() = ConcreteReference(FieldReferenceStep("content"), EmptyReference())
_input() = TextBlock(TextString("alpha dolor", _font, color_default))

@testset "ProjectionConfiguringProjection stacks control above document" begin

    th  = TextHighlighting("dolor")
    pcp = ProjectionConfiguringProjection(inner=th)
    iomap = print_document(pcp, nothing, _input(), PrinterContext())

    out = iomap.output
    @test out isa WidgetSplitPane
    @test out.orientation == :vertical
    @test length(out.elements) == 2
    @test out.elements[1] === iomap.control_widget        # control bar on top
    # A non-widget projected document is wrapped in a WidgetScrollPane so the
    # WidgetSplitPane will render it.
    @test out.elements[2] isa WidgetScrollPane
    @test out.elements[2].content === iomap.inner_iomap.output

end # @testset

@testset "control edit is redirected onto the inner projection's parameter" begin

    th  = TextHighlighting("dolor")
    pcp = ProjectionConfiguringProjection(inner=th)
    iomap = print_document(pcp, nothing, _input(), PrinterContext())

    ctrl = iomap.control_iomap.controls[1][1]   # the pattern control
    edit = ReplaceReferencedValueOperation(ctrl, _content_ref(), "alpha")
    out  = read_intent(pcp, nothing, _mkchange(nothing, edit), iomap)

    @test out.operation isa ReplaceReferencedValueOperation
    @test out.operation.document === th
    @test out.operation.reference.head == FieldReferenceStep("pattern")

    evaluate_operation(nothing, out.operation)
    @test th.pattern[] == "alpha"

end # @testset

@testset "Ctrl+F toggles and Escape hides the control bar" begin

    pcp = ProjectionConfiguringProjection(inner=TextHighlighting("dolor"))
    iomap = print_document(pcp, nothing, _input(), PrinterContext())

    # Control starts visible → Ctrl+F hides it. Showing and hiding the bar is view
    # state, so a history does not record it.
    ctrl_f = KeyDown(:f, ModifierKeys(ctrl=true); time = 0.0)
    marked = read_intent(pcp, nothing, _mkchange(ctrl_f, nothing), iomap).operation
    @test marked isa ReplaceViewStateOperation
    op = get_wrapped_operation(marked)
    @test op isa ReplaceReferencedValueOperation && op.value == false   # hide = visible←false
    @test op.document === iomap.control_widget

    # Escape also hides while visible.
    esc = KeyDown(:escape, ModifierKeys(); time = 0.0)
    op_esc = read_intent(pcp, nothing, _mkchange(esc, nothing), iomap).operation
    @test op_esc isa ReplaceViewStateOperation && get_wrapped_operation(op_esc).value == false

    # After hiding, Ctrl+F shows again.
    iomap.control_widget.visible = false
    op2 = read_intent(pcp, nothing, _mkchange(ctrl_f, nothing), iomap).operation
    @test op2 isa ReplaceViewStateOperation && get_wrapped_operation(op2).value == true   # show = visible←true

end # @testset

@testset "end-to-end: clicking a control-bar checkbox flips the inner field" begin

    stub = FixedMeasure(10, 18, 6, 0)
    font = font_ubuntu_monospace_regular_20
    fg   = (0xee, 0xee, 0xee, 0xff)

    inner = TextFiltering()                       # case_insensitive=false, invert=false
    pcp   = ProjectionConfiguringProjection(inner=inner)
    w2g   = WidgetToGraphics(font; measure=stub)
    renderer = RecursiveProjection(TypeDispatchingProjection(vcat(
        w2g.dispatch,
        Pair{Type,Any}[TextBlock => TextToGraphics(measure=stub)])))
    proj  = ChainingProjection(pcp, renderer)

    doc   = TextBlock(TextString("alpha dolor", font, color_default))
    iomap = print_document(proj, nothing, doc, PrinterContext())

    # A click that lands on a checkbox routes through renderer → split pane →
    # composite rows → checkbox, bubbles a ReplaceReferencedValueOperation, and PCP
    # redirects it onto the inner projection's bool cell.
    flipped = false
    for y in 0:4:120, x in 150:5:230
        op = read_intent(proj, iomap, MouseClick(:left, x, y, ModifierKeys(); time = 0.0))
        op isa ReplaceReferencedValueOperation || continue
        evaluate_operation(_PcEditor(doc), op)
        if inner.case_insensitive[] || inner.invert[]
            flipped = true
            break
        end
    end
    @test flipped

end # @testset

@testset "a point on the document maps to the text position drawn there, and a point on the control to nothing" begin

    stub = FixedMeasure(10, 18, 6, 0)
    font = font_ubuntu_monospace_regular_20
    pcp  = ProjectionConfiguringProjection(inner=TextHighlighting("dolor"))
    w2g  = WidgetToGraphics(font; measure=stub)
    renderer = RecursiveProjection(TypeDispatchingProjection(vcat(
        w2g.dispatch,
        Pair{Type,Any}[TextBlock => TextToGraphics(measure=stub)])))
    proj  = ChainingProjection(pcp, renderer)
    doc   = TextBlock(TextString("alpha dolor", font, color_default))
    iomap = print_document(proj, nothing, doc, PrinterContext())
    # The control takes the first 120 pixels, and the document starts below the
    # divider, at 121.
    iomap.step_iomaps[1][].output.sizes = [120, 300]

    # Six characters of 10 pixels from the left edge: the caret after "alpha ".
    @test is_reference_equal(map_reference_backward(proj, iomap, PointReferenceStep(65, 132)),
                             TextModule.make_flat_caret_reference(6))
    # The control shows the inner projection, not the document.
    @test map_reference_backward(proj, iomap, PointReferenceStep(15, 60)) === nothing

end # @testset

@testset "end-to-end: typing edits the inner projection's pattern live" begin

    stub = FixedMeasure(10, 18, 6, 0)
    font = font_ubuntu_monospace_regular_20

    inner = TextHighlighting("dolor")
    pcp   = ProjectionConfiguringProjection(inner=inner)
    w2g   = WidgetToGraphics(font; measure=stub)
    renderer = RecursiveProjection(TypeDispatchingProjection(vcat(
        w2g.dispatch,
        Pair{Type,Any}[TextBlock => TextToGraphics(measure=stub)])))
    proj  = ChainingProjection(pcp, renderer)

    doc   = TextBlock(TextString("alpha dolor", font, color_default))
    ctx   = with_exact_size(PrinterContext(); width=Cell(800), height=Cell(600))
    iomap = print_document(proj, nothing, doc, ctx)

    # A KeyPress routes to the (only) editable control and appends to the pattern.
    #
    # Currently broken: the widget layer routes coordless events (KeyPress/KeyDown)
    # *strictly* by selection with no "sole editable widget" fallback (see
    # package/visual/doc/widget.md and `_selected_split_slot` /
    # `_selected_composite_slot`). And pcp itself consumes ReplaceSelectionOps on
    # the control slot (Case 3 in ProjectionConfiguring.jl), so the classic
    # "Tab to focus, then type" bootstrap does not persist either. Reaching this
    # test's expectation needs either an autofocus semantic in the widget layer
    # or a pcp change that lets control-directed selections persist — both are
    # design decisions, not local test fixes.
    op = read_intent(proj, nothing, _mkchange(KeyPress('X', "X", ModifierKeys(); time = 0.0), nothing), iomap).operation
    @test_broken op isa ReplaceReferencedValueOperation
    op isa ReplaceReferencedValueOperation || return
    @test op.reference.head == FieldReferenceStep("pattern")
    evaluate_operation(_PcEditor(doc), op)
    @test inner.pattern[] == "dolorX"

end # @testset

end # test_projection_configuring
