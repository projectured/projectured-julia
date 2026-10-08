# The value slot of a widget holds an `ObjectField`: each value widget, in an
# editor, under the nesting of `make_object_field_widget_dispatch`, shows the value
# of the field, writes the field when a person changes it, and Ctrl+Z takes the
# write back. The select makes the operation of each option when its popup opens.
# A text moves its caret after each key. A child that does not take a value sends
# no edit, and a `TextBlock` in a text still draws as text.

@document struct SlotSettings
    name::String
    count::Int
    ratio::Float64
    enabled::Bool
    style::Symbol
end

_slot_settings() = SlotSettings("gateway", 4, 0.5, true, :b, nothing)

# The recursion of a form whose value widgets print their slot through
# `ObjectFieldToValue`, in an undo buffer.
function _slot_projection()
    measure = FontFileMeasure()
    w2g = WidgetToGraphics(StyleFont("Ubuntu Mono", 20); measure)
    RecursiveProjection(TypeDispatchingProjection(vcat(
        Pair{Type,Any}[UndoBuffer => UndoBufferToAnyProjection()],
        LayoutToGraphics().dispatch,
        make_object_field_widget_dispatch(w2g.dispatch),
        Pair{Type,Any}[TextBlock => TextToGraphics(measure = measure)])))
end

# An editor on `widget` alone, in an undo buffer, after its first frame.
function _slot_editor(widget)
    backend = HeadlessBackend()
    editor = build_editor(UndoBuffer(widget), _slot_projection();
        backend, devices = ProjecturedKernel.DeviceModule.Device[Keyboard(), Mouse(), Display()],
        window = false, appearance = false, settings = false, tabs = false,
        focus_cycling = false)
    run_frame!(editor)
    (editor, backend)
end

_slot_frame(backend) = last(rendered_output(backend))

_slot_press!(editor, backend, events...) =
    (foreach(event -> push_event!(backend, event), events); run_frame!(editor))

_slot_click(x, y) = MouseClick(:left, x, y, 1, ModifierKeys(); time = 0.0)

_slot_undo!(editor, backend) =
    _slot_press!(editor, backend, KeyDown(:z, ModifierKeys(ctrl = true); time = 0.0))

# The texts that a frame draws, each with the point where it is drawn.
function _slot_drawn(canvas, ox = 0, oy = 0, found = Tuple{String,Int,Int}[])
    x = ox + Int(canvas.x)
    y = oy + Int(canvas.y)
    for element in canvas.elements
        element = element isa Cell ? element[] : element
        if element isa GraphicsText
            push!(found, (String(element.text), x + Int(element.x), y + Int(element.y)))
        elseif element isa GraphicsCanvas
            _slot_drawn(element, x, y, found)
        end
    end
    found
end

# A press at the first text `text` of the last frame.
function _slot_click_text(backend, text)
    (_, x, y) = first(entry for entry in _slot_drawn(_slot_frame(backend)) if entry[1] == text)
    _slot_click(x + 2, y + 2)
end

# A press at the middle of the drawing of the frame, which is the widget alone.
function _slot_click_middle(backend)
    frame = _slot_frame(backend)
    _slot_click(Int(frame.w) ÷ 2, Int(frame.h) ÷ 2)
end

function test_widget_value_slot()
@testset "WidgetValueSlot" begin

    @testset "a checkbox writes the field, and Ctrl+Z takes it back" begin
        settings = _slot_settings()
        editor, backend = _slot_editor(WidgetCheckbox(ObjectField(settings, "enabled")))
        _slot_press!(editor, backend, _slot_click_middle(backend))
        @test settings.enabled == false
        _slot_undo!(editor, backend)
        @test settings.enabled == true
    end

    @testset "a switch and a toggle write the field" begin
        settings = _slot_settings()
        editor, backend = _slot_editor(WidgetSwitch(checked = ObjectField(settings, "enabled")))
        _slot_press!(editor, backend, _slot_click_middle(backend))
        @test settings.enabled == false
        editor, backend = _slot_editor(WidgetToggle("On"; pressed = ObjectField(settings, "enabled")))
        _slot_press!(editor, backend, _slot_click_text(backend, "On"))
        @test settings.enabled == true
    end

    @testset "a spin box shows the field and steps it" begin
        settings = _slot_settings()
        editor, backend = _slot_editor(WidgetSpinBox(ObjectField(settings, "count"); min = 0, max = 10))
        @test any(entry -> entry[1] == "4", _slot_drawn(_slot_frame(backend)))
        frame = _slot_frame(backend)
        _slot_press!(editor, backend, _slot_click(Int(frame.w) - 4, 4))
        @test settings.count == 5
        _slot_undo!(editor, backend)
        @test settings.count == 4
    end

    @testset "a slider writes the field as a share" begin
        settings = _slot_settings()
        editor, backend = _slot_editor(WidgetSlider(ObjectField(settings, "ratio")))
        frame = _slot_frame(backend)
        _slot_press!(editor, backend, _slot_click(3 * Int(frame.w) ÷ 4, Int(frame.h) ÷ 2))
        @test 0.6 < settings.ratio < 0.9
    end

    @testset "a radio group shows the option of the field and stores an option" begin
        settings = _slot_settings()
        editor, backend = _slot_editor(WidgetRadioGroup([:a, :b, :c];
                                                        selected = ObjectField(settings, "style")))
        _slot_press!(editor, backend, _slot_click_text(backend, "c"))
        @test settings.style === :c
        _slot_undo!(editor, backend)
        @test settings.style === :b
    end

    @testset "a select makes the operation of each option when its popup opens" begin
        settings = _slot_settings()
        select = WidgetSelect(ObjectField(settings, "style"); options = Any[:a, :b, :c])
        projection = _slot_projection()
        iomap = print_document(projection, projection, select, PrinterContext())
        answer = read_intent(projection, iomap, _slot_click(5, 5))
        popup = get_wrapped_operation(answer)
        options = collect(popup.content.elements)
        @test length(options) == 3
        pick = options[3].operation
        @test pick isa ReplaceReferencedValueOperation
        @test pick.document === settings
        evaluate_operation(nothing, pick)
        @test settings.style === :c
    end

    @testset "a text writes the field and moves its caret after each key" begin
        settings = _slot_settings()
        editor, backend = _slot_editor(WidgetText(ObjectField(settings, "name")))
        _slot_press!(editor, backend, _slot_click_text(backend, "gateway"))
        _slot_press!(editor, backend, KeyPress('X', "X", ModifierKeys(); time = 0.0))
        _slot_press!(editor, backend, KeyPress('Y', "Y", ModifierKeys(); time = 0.0))
        @test settings.name == "XYgateway"
        @test any(entry -> entry[1] == "XYgateway", _slot_drawn(_slot_frame(backend)))
    end

    @testset "a number field takes the number of its text" begin
        settings = _slot_settings()
        editor, backend = _slot_editor(WidgetText(ObjectField(settings, "count")))
        _slot_press!(editor, backend, _slot_click_text(backend, "4"))
        _slot_press!(editor, backend, KeyPress('2', "2", ModifierKeys(); time = 0.0))
        @test settings.count isa Int
        @test settings.count in (24, 42)
    end

    @testset "a TextBlock in a text still draws as text" begin
        editor, backend = _slot_editor(WidgetText(TextBlock(TextString("hello", StyleText(StyleFont("Ubuntu Mono", 20), color_default)))))
        @test any(entry -> entry[1] == "hello", _slot_drawn(_slot_frame(backend)))
    end

    @testset "a slot with a plain value has no child" begin
        projection = _slot_projection()
        checkbox = WidgetCheckbox(true)
        iomap = print_document(projection, projection, checkbox, PrinterContext())
        @test iomap.child_iomap isa WidgetValueIoMap
        @test iomap.child_iomap.value_iomap === nothing
        store = make_slot_store_operation(checkbox, :content, nothing, false)
        @test store.document === checkbox
        @test get_reference_head(store.reference) == FieldReferenceStep("content")
        @test store.value === false
    end

    @testset "a child that does not take a value sends no edit" begin
        checkbox = WidgetCheckbox(true)
        child = print_document(IdentityProjection(), nothing, TextBlock(TextString("x", StyleText(StyleFont("Ubuntu Mono", 20), color_default))), nothing)
        @test make_slot_store_operation(checkbox, :content, child, false) === nothing
    end

end
end # test_widget_value_slot
