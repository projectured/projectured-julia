# Form widgets: WidgetSpinBox steppers, WidgetList selection, the toggle, the
# toggle group and the radio group, and the numeric validator. A control writes
# its own value with a ReplaceReferencedValueOperation; the list reports selection
# as a ReplaceSelectionOperation like every other widget; the validator is an
# acceptor the editable text reader consults.

function test_widget_forms()
@testset "WidgetSpinBox / WidgetList / toggles / validator" begin

proj = make_widget_projection_example()

# Where each drawn text starts, in the frame the widget is placed in. A test
# presses a control where it draws a word, and repeats none of its arithmetic.
function _drawn_text_positions(canvas, ox = 0, oy = 0, found = Dict{String,Tuple{Int,Int}}())
    x = ox + Int(canvas.x); y = oy + Int(canvas.y)
    for element in canvas.elements
        if element isa GraphicsText
            found[String(element.text)] = (x + Int(element.x), y + Int(element.y))
        elseif element isa GraphicsCanvas
            _drawn_text_positions(element, x, y, found)
        end
    end
    found
end

# A layout whose selection names its second child as a whole: the focus, so a key
# reaches that child.
function _focus_second(control)
    layout = VerticalLayout(Any[WidgetLabel("Label"), control]; gap = 8)
    getfield(layout, :selection)[] = ConcreteReference(FieldReferenceStep("children"),
        ConcreteReference(RangeReferenceStep(1, 2), EmptyReference()))
    layout
end
_key(k; modifiers...) = KeyDown(k, ModifierKeys(; modifiers...))

@testset "spin box steps up/down and clamps to [min, max]" begin
    s = WidgetSpinBox(5; min=0, max=10, step=2)
    io = print_document(proj, s)
    cw = Int(io.output.w[]); ch = Int(io.output.h[])
    up   = read_intent(proj, io, MousePress(:left, cw - 2, 2, ModifierKeys()))           # top stepper
    down = read_intent(proj, io, MousePress(:left, cw - 2, ch - 2, ModifierKeys()))       # bottom stepper
    @test up isa ReplaceReferencedValueOperation && up.value == 7
    @test down isa ReplaceReferencedValueOperation && down.value == 3
    # A click in the field area (left of the steppers) does not step.
    @test read_intent(proj, io, MousePress(:left, 2, 2, ModifierKeys())) === nothing

    # Clamp: stepping past max stays at max; past min stays at min.
    hi = print_document(proj, WidgetSpinBox(10; min=0, max=10, step=5))
    @test read_intent(proj, hi, MousePress(:left, Int(hi.output.w[]) - 2, 2, ModifierKeys())).value == 10
    lo = print_document(proj, WidgetSpinBox(0; min=0, max=10, step=5))
    @test read_intent(proj, lo, MousePress(:left, Int(lo.output.w[]) - 2, Int(lo.output.h[]) - 2, ModifierKeys())).value == 0

    # Disabled is inert.
    dis = print_document(proj, WidgetSpinBox(5; enabled=false))
    @test read_intent(proj, dis, MousePress(:left, Int(dis.output.w[]) - 2, 2, ModifierKeys())) === nothing
end

@testset "list click + arrow keys move the selection" begin
    l  = WidgetList(["Alpha", "Beta", "Gamma"]; selected=1)
    io = print_document(proj, l)
    rh = Int(io.output.h[]) ÷ 3
    # Selection is reported the way every widget reports selection: a
    # ReplaceSelectionOperation carrying an `items[i-1:i]` reference, so an
    # enclosing projection can map it into its own domain (and back when
    # printing). It is NOT a write to a private index field.
    pick2 = read_intent(proj, io, MousePress(:left, 5, rh + 2, ModifierKeys()))           # row 2
    @test pick2 isa ReplaceSelectionOperation
    @test pick2.path == make_widget_list_selection(2)
    @test read_intent(proj, io, KeyDown(:down, ModifierKeys(), false)).path ==
          make_widget_list_selection(2)                                                         # 1 → 2
    @test read_intent(proj, io, KeyDown(:up, ModifierKeys(), false)).path ==
          make_widget_list_selection(1)                                                         # 1 → 1 (floor)
    # `selected=` sugar and `get_widget_list_selected` are inverses; 0 = none.
    @test get_widget_list_selected(l) == 1
    @test get_widget_list_selected(WidgetList(["Alpha", "Beta"])) == 0
    # An empty list is inert.
    @test read_intent(proj, print_document(proj, WidgetList(String[])),
                          MousePress(:left, 2, 2, ModifierKeys())) === nothing
end

@testset "toggle group picks the segment under the press" begin
    g  = WidgetToggleGroup(["Run", "Fast", "Express"]; selected=2)
    io = print_document(proj, g)
    w  = Int(io.output.w[])
    # Positions are taken from the control's own edges rather than from segment
    # widths the test computes for itself: the far left is the first segment and
    # the far right is the last, whatever the font measures them at.
    left, right = 2, w - 3

    # The answer is a value write, the way a select's picked option answers — a
    # segment is a control's value, not a place in a document.
    first = read_intent(proj, io, MousePress(:left, left, 4, ModifierKeys()))
    @test first isa ReplaceReferencedValueOperation
    @test first.document === g
    @test first.value == 1
    @test read_intent(proj, io, MousePress(:left, right, 4, ModifierKeys())).value == 3

    # The segment already on is not a change, so there is no edit to report.
    on_first = print_document(proj, WidgetToggleGroup(["Run", "Fast", "Express"]; selected=1))
    @test read_intent(proj, on_first, MousePress(:left, left, 4, ModifierKeys())) === nothing

    # Past the right edge is outside the control, which every widget declines.
    @test read_intent(proj, io, MousePress(:left, w + 5, 4, ModifierKeys())) === nothing

    # With a target, the pick names what it changes: a group that is *for*
    # something writes that thing's field, and `values` says what a segment means.
    # This is what keeps an enclosing projection from having to guess which
    # control was pressed.
    holder = WidgetLabel("")          # any document will do as a target
    aimed  = WidgetToggleGroup(["Run", "Fast", "Express"]; selected=2,
                               values = [:run, :fast, :express],
                               target = holder, field = "text")
    aimed_io = print_document(proj, aimed)
    picked = read_intent(proj, aimed_io, MousePress(:left, 2, 4, ModifierKeys()))
    @test picked isa ReplaceReferencedValueOperation
    @test picked.document === holder
    @test picked.value === :run

    # A right press is not a pick, and a disabled group is inert.
    @test read_intent(proj, io, MousePress(:right, left, 4, ModifierKeys())) === nothing
    dis = WidgetToggleGroup(["Run", "Fast"]; selected=2, enabled=false)
    @test read_intent(proj, print_document(proj, dis),
                      MousePress(:left, 4, 4, ModifierKeys())) === nothing
    # An invisible one draws nothing and answers nothing.
    inv = WidgetToggleGroup(["Run", "Fast"]; visible=false)
    @test read_intent(proj, print_document(proj, inv),
                      MousePress(:left, 4, 4, ModifierKeys())) === nothing
end

@testset "a toggle flips from a press, and from Return and Space with the focus" begin
    t  = WidgetToggle("Bold")
    io = print_document(proj, t)
    x, y = _drawn_text_positions(io.output)["Bold"]
    press = read_intent(proj, io, MousePress(:left, x + 2, y + 2, ModifierKeys()))
    @test press isa ReplaceReferencedValueOperation
    @test press.document === t && press.value === true
    @test read_intent(proj, io, MousePress(:right, x + 2, y + 2, ModifierKeys())) === nothing
    # A released toggle draws its outline, and a pressed one does not.
    @test Int(io.output.elements[1].border_width) > 0
    evaluate_operation(nothing, press)
    @test t.pressed === true
    @test Int(io.output.elements[1].border_width) == 0

    # A key reaches the toggle only through the selection of its container.
    layout = VerticalLayout(Any[WidgetLabel("Label"), t]; gap = 8)
    @test read_intent(proj, print_document(proj, layout), _key(:space)) === nothing
    focused = print_document(proj, _focus_second(t))
    for key in (:space, :return)
        op = read_intent(proj, focused, _key(key))
        @test op isa ReplaceReferencedValueOperation && op.document === t && op.value === false
    end
    @test read_intent(proj, focused, _key(:space; ctrl = true)) === nothing

    off = WidgetToggle("Bold"; enabled = false)
    off_io = print_document(proj, off)
    @test read_intent(proj, off_io, MousePress(:left, x + 2, y + 2, ModifierKeys())) === nothing
    @test read_intent(proj, print_document(proj, _focus_second(off)), _key(:space)) === nothing
end

@testset "a radio group selects the option under a press, and the arrows move it" begin
    r  = WidgetRadioGroup(["Default", "Comfortable", "Compact"]; selected = 1)
    io = print_document(proj, r)
    at = _drawn_text_positions(io.output)
    compact = at["Compact"]; comfortable = at["Comfortable"]; default = at["Default"]
    pick = read_intent(proj, io, MousePress(:left, compact[1] + 2, compact[2] + 2, ModifierKeys()))
    @test pick isa ReplaceReferencedValueOperation
    @test pick.document === r && pick.value == 3
    # The circle of a row is part of its target, left of the word.
    @test read_intent(proj, io, MousePress(:left, 2, comfortable[2] + 2, ModifierKeys())).value == 2
    # The option that is on is not a change, and a right press is not a pick.
    @test read_intent(proj, io, MousePress(:left, default[1] + 2, default[2] + 2, ModifierKeys())) === nothing
    @test read_intent(proj, io, MousePress(:right, compact[1] + 2, compact[2] + 2, ModifierKeys())) === nothing

    # The dot is drawn in the row of the option that is on.
    evaluate_operation(nothing, pick)
    @test r.selected == 3
    circles = [e for e in io.output.elements if e isa GraphicsCircle]
    dot = circles[argmin([Int(c.radius) for c in circles])]
    @test abs(Int(dot.cy) - compact[2]) < abs(Int(dot.cy) - comfortable[2])

    # The arrows move the selection around the ends while the group has the focus.
    moved(key; modifiers...) = read_intent(proj, print_document(proj, _focus_second(r)), _key(key; modifiers...))
    @test moved(:down).value == 1
    @test moved(:right).value == 1
    @test moved(:up).value == 2
    @test moved(:left).value == 2
    @test moved(:space) === nothing
    @test moved(:down; alt = true) === nothing
    @test read_intent(proj, print_document(proj, VerticalLayout(Any[r])), _key(:down)) === nothing
    # With no option on, Return and Space select the first one.
    none = WidgetRadioGroup(["a", "b"]; selected = 0)
    none_io = print_document(proj, _focus_second(none))
    @test read_intent(proj, none_io, _key(:space)).value == 1
    @test read_intent(proj, none_io, _key(:return)).value == 1

    off = WidgetRadioGroup(["Default", "Compact"]; selected = 1, enabled = false)
    off_io = print_document(proj, off)
    lx, ly = _drawn_text_positions(off_io.output)["Compact"]
    @test read_intent(proj, off_io, MousePress(:left, lx + 2, ly + 2, ModifierKeys())) === nothing
    @test read_intent(proj, print_document(proj, _focus_second(off)), _key(:down)) === nothing
end

@testset "a control takes its keys with no modifier and its press from the left button" begin
    # Alt and an arrow walk the selection, so a control that takes the arrows
    # takes them bare. The spin box and the list step with the focus.
    s = WidgetSpinBox(5; min = 0, max = 10)
    spin(key; modifiers...) = read_intent(proj, print_document(proj, _focus_second(s)), _key(key; modifiers...))
    @test spin(:up).value == 6
    @test spin(:down).value == 4
    @test spin(:up; alt = true) === nothing
    @test spin(:down; ctrl = true) === nothing
    l = WidgetList(["Alpha", "Beta", "Gamma"]; selected = 1)
    io = print_document(proj, l)
    @test read_intent(proj, io, _key(:down)).path == make_widget_list_selection(2)
    @test read_intent(proj, io, _key(:down; alt = true)) === nothing
    @test read_intent(proj, io, _key(:up; shift = true)) === nothing

    # A check box and a switch flip from a left press, and from Return and
    # Space with no modifier.
    for control in (WidgetCheckbox(false), WidgetSwitch(; checked = false))
        control_io = print_document(proj, control)
        @test read_intent(proj, control_io, MousePress(:left, 2, 2, ModifierKeys())) !== nothing
        @test read_intent(proj, control_io, MousePress(:right, 2, 2, ModifierKeys())) === nothing
        @test read_intent(proj, control_io, MousePress(:middle, 2, 2, ModifierKeys())) === nothing
        focused = print_document(proj, _focus_second(control))
        @test read_intent(proj, focused, _key(:space)) !== nothing
        @test read_intent(proj, focused, _key(:return)) !== nothing
        @test read_intent(proj, focused, _key(:space; ctrl = true)) === nothing
        @test read_intent(proj, focused, _key(:return; alt = true)) === nothing
    end
    # A button takes Return and Space with no modifier too.
    button = print_document(proj, _focus_second(WidgetButton("Go"; size = Point2D(60, 24))))
    @test read_intent(proj, button, _key(:return)) isa InvokeActionOperation
    @test read_intent(proj, button, _key(:return; ctrl = true)) === nothing
    @test read_intent(proj, button, _key(:space; shift = true)) === nothing
end

@testset "make_numeric_validator accepts digits, rejects letters" begin
    v = make_numeric_validator()
    @test v("123") === true
    @test v("") === true            # a deletion
    @test v("12") === true
    @test v("a") === false
    @test v("1a") === false
    @test make_numeric_validator()(".") === true        # decimal allowed by default
    @test make_numeric_validator(; integer=true)(".") === false
    # The field carries the validator.
    t = WidgetText("x"; validator=v)
    @test t.validator === v
end

end # @testset
end # function
