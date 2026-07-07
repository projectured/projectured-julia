mutable struct _PcEditor
    document::Any
end

function test_projection_configuring()

_font = font_ubuntu_monospace_regular_20
_mkchange(g, o) = IntentModule.Intent(g, o)
_content_ref() = ConcreteReferencePath(FieldReference("content"), EmptyReferencePath())
_input() = TextText(TextString("alpha dolor", _font, color_default))

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
    @test out.operation.reference.head == FieldReference("pattern")

    evaluate_operation(nothing, out.operation)
    @test th.pattern[] == "alpha"

end # @testset

@testset "Ctrl+F toggles and Escape hides the control bar" begin

    pcp = ProjectionConfiguringProjection(inner=TextHighlighting("dolor"))
    iomap = print_document(pcp, nothing, _input(), PrinterContext())

    # Control starts visible → Ctrl+F hides it.
    ctrl_f = KeyDown(:f, Modifiers(ctrl=true))
    op = read_intent(pcp, nothing, _mkchange(ctrl_f, nothing), iomap).operation
    @test op isa ReplaceReferencedValueOperation && op.value == false   # hide = visible←false
    @test op.document === iomap.control_widget

    # Escape also hides while visible.
    esc = KeyDown(:escape, Modifiers())
    op_esc = read_intent(pcp, nothing, _mkchange(esc, nothing), iomap).operation
    @test op_esc isa ReplaceReferencedValueOperation && op_esc.value == false

    # After hiding, Ctrl+F shows again.
    iomap.control_widget.visible = false
    op2 = read_intent(pcp, nothing, _mkchange(ctrl_f, nothing), iomap).operation
    @test op2 isa ReplaceReferencedValueOperation && op2.value == true   # show = visible←true

end # @testset

@testset "end-to-end: clicking a control-bar checkbox flips the inner field" begin

    stub(t, f) = (length(t) * 10, 24)
    font = font_ubuntu_monospace_regular_20
    fg   = (0xee, 0xee, 0xee, 0xff)

    inner = TextFiltering()                       # case_insensitive=false, invert=false
    pcp   = ProjectionConfiguringProjection(inner=inner)
    w2g   = WidgetToGraphics(font; measure=stub)
    renderer = RecursiveProjection(TypeDispatchingProjection(vcat(
        w2g.dispatch,
        Pair{Type,Any}[TextText => TextToGraphics(measure=stub)])))
    proj  = ChainingProjection(pcp, renderer)

    doc   = TextText(TextString("alpha dolor", font, color_default))
    iomap = print_document(proj, nothing, doc, PrinterContext())

    # A click that lands on a checkbox routes through renderer → split pane →
    # composite rows → checkbox, bubbles a ReplaceReferencedValueOperation, and PCP
    # redirects it onto the inner projection's bool cell.
    flipped = false
    for y in 0:4:120, x in 150:5:230
        op = read_intent(proj, iomap, MousePress(:left, x, y, Modifiers()))
        op isa ReplaceReferencedValueOperation || continue
        evaluate_operation(_PcEditor(doc), op)
        if inner.case_insensitive[] || inner.invert[]
            flipped = true
            break
        end
    end
    @test flipped

end # @testset

@testset "end-to-end: typing edits the inner projection's pattern live" begin

    stub(t, f) = (max(1, length(t)) * 10, 24)
    font = font_ubuntu_monospace_regular_20

    inner = TextHighlighting("dolor")
    pcp   = ProjectionConfiguringProjection(inner=inner)
    w2g   = WidgetToGraphics(font; measure=stub)
    renderer = RecursiveProjection(TypeDispatchingProjection(vcat(
        w2g.dispatch,
        Pair{Type,Any}[TextText => TextToGraphics(measure=stub)])))
    proj  = ChainingProjection(pcp, renderer)

    doc   = TextText(TextString("alpha dolor", font, color_default))
    ctx   = with_available_size(PrinterContext(); width=Cell(800), height=Cell(600))
    iomap = print_document(proj, nothing, doc, ctx)

    # A KeyPress routes to the (only) editable control and appends to the pattern.
    #
    # Currently broken: the widget layer routes coordless events (KeyPress/KeyDown)
    # *strictly* by selection with no "sole editable widget" fallback (see
    # documentation/document/widget.md and `_selected_split_slot` /
    # `_selected_composite_slot`). And pcp itself consumes ReplaceSelectionOps on
    # the control slot (Case 3 in ProjectionConfiguring.jl), so the classic
    # "Tab to focus, then type" bootstrap does not persist either. Reaching this
    # test's expectation needs either an autofocus semantic in the widget layer
    # or a pcp change that lets control-directed selections persist — both are
    # design decisions, not local test fixes.
    op = read_intent(proj, nothing, _mkchange(KeyPress('X', "X", Modifiers()), nothing), iomap).operation
    @test_broken op isa ReplaceReferencedValueOperation
    op isa ReplaceReferencedValueOperation || return
    @test op.reference.head == FieldReference("pattern")
    evaluate_operation(_PcEditor(doc), op)
    @test inner.pattern[] == "dolorX"

end # @testset

end # test_projection_configuring
