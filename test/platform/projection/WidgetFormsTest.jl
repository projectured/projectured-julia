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
_key(k; modifiers...) = KeyDown(k, ModifierKeys(; modifiers...); time = 0.0)

@testset "spin box steps up/down and clamps to [min, max]" begin
    s = WidgetSpinBox(5; min=0, max=10, step=2)
    io = print_document(proj, s)
    cw = Int(io.output.w[]); ch = Int(io.output.h[])
    up   = read_intent(proj, io, MouseClick(:left, cw - 2, 2, ModifierKeys(); time = 0.0))           # top stepper
    down = read_intent(proj, io, MouseClick(:left, cw - 2, ch - 2, ModifierKeys(); time = 0.0))       # bottom stepper
    @test up isa ReplaceReferencedValueOperation && up.value == 7
    @test down isa ReplaceReferencedValueOperation && down.value == 3
    # A click in the field area (left of the steppers) does not step.
    @test read_intent(proj, io, MouseClick(:left, 2, 2, ModifierKeys(); time = 0.0)) === nothing

    # Clamp: stepping past max stays at max; past min stays at min.
    hi = print_document(proj, WidgetSpinBox(10; min=0, max=10, step=5))
    @test read_intent(proj, hi, MouseClick(:left, Int(hi.output.w[]) - 2, 2, ModifierKeys(); time = 0.0)).value == 10
    lo = print_document(proj, WidgetSpinBox(0; min=0, max=10, step=5))
    @test read_intent(proj, lo, MouseClick(:left, Int(lo.output.w[]) - 2, Int(lo.output.h[]) - 2, ModifierKeys(); time = 0.0)).value == 0

    # Disabled is inert.
    dis = print_document(proj, WidgetSpinBox(5; enabled=false))
    @test read_intent(proj, dis, MouseClick(:left, Int(dis.output.w[]) - 2, 2, ModifierKeys(); time = 0.0)) === nothing
end

@testset "list click + arrow keys move the selection" begin
    l  = WidgetList(["Alpha", "Beta", "Gamma"]; selected=1)
    io = print_document(proj, l)
    rh = Int(io.output.h[]) ÷ 3
    # Selection is reported the way every widget reports selection: a
    # ReplaceSelectionOperation carrying an `items[i-1:i]` reference, so an
    # enclosing projection can map it into its own domain (and back when
    # printing). It is NOT a write to a private index field.
    pick2 = read_intent(proj, io, MouseClick(:left, 5, rh + 2, ModifierKeys(); time = 0.0))           # row 2
    @test pick2 isa ReplaceSelectionOperation
    @test pick2.path == make_widget_list_selection(2)
    @test read_intent(proj, io, KeyDown(:down, ModifierKeys(); time = 0.0)).path ==
          make_widget_list_selection(2)                                                         # 1 → 2
    @test read_intent(proj, io, KeyDown(:up, ModifierKeys(); time = 0.0)).path ==
          make_widget_list_selection(1)                                                         # 1 → 1 (floor)
    # `selected=` sugar and `get_widget_list_selected` are inverses; 0 = none.
    @test get_widget_list_selected(l) == 1
    @test get_widget_list_selected(WidgetList(["Alpha", "Beta"])) == 0
    # An empty list is inert.
    @test read_intent(proj, print_document(proj, WidgetList(String[])),
                          MouseClick(:left, 2, 2, ModifierKeys(); time = 0.0)) === nothing
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
    first = read_intent(proj, io, MouseClick(:left, left, 4, ModifierKeys(); time = 0.0))
    @test first isa ReplaceReferencedValueOperation
    @test first.document === g
    @test first.value == 1
    @test read_intent(proj, io, MouseClick(:left, right, 4, ModifierKeys(); time = 0.0)).value == 3

    # The segment already on is not a change, so there is no edit to report.
    on_first = print_document(proj, WidgetToggleGroup(["Run", "Fast", "Express"]; selected=1))
    @test read_intent(proj, on_first, MouseClick(:left, left, 4, ModifierKeys(); time = 0.0)) === nothing

    # Past the right edge is outside the control, which every widget declines.
    @test read_intent(proj, io, MouseClick(:left, w + 5, 4, ModifierKeys(); time = 0.0)) === nothing

    # With a target, the pick names what it changes: a group that is *for*
    # something writes that thing's field, and `values` says what a segment means.
    # This is what keeps an enclosing projection from having to guess which
    # control was pressed.
    holder = WidgetLabel("")          # any document will do as a target
    aimed  = WidgetToggleGroup(["Run", "Fast", "Express"]; selected=2,
                               values = [:run, :fast, :express],
                               target = holder, field = "text")
    aimed_io = print_document(proj, aimed)
    picked = read_intent(proj, aimed_io, MouseClick(:left, 2, 4, ModifierKeys(); time = 0.0))
    @test picked isa ReplaceReferencedValueOperation
    @test picked.document === holder
    @test picked.value === :run

    # A right press is not a pick, and a disabled group is inert.
    @test read_intent(proj, io, MouseClick(:right, left, 4, ModifierKeys(); time = 0.0)) === nothing
    dis = WidgetToggleGroup(["Run", "Fast"]; selected=2, enabled=false)
    @test read_intent(proj, print_document(proj, dis),
                      MouseClick(:left, 4, 4, ModifierKeys(); time = 0.0)) === nothing
    # An invisible one draws nothing and answers nothing.
    inv = WidgetToggleGroup(["Run", "Fast"]; visible=false)
    @test read_intent(proj, print_document(proj, inv),
                      MouseClick(:left, 4, 4, ModifierKeys(); time = 0.0)) === nothing
end

@testset "a toggle group of the step look shows one option and steps through them" begin
    step_group(selected) = WidgetToggleGroup(["A", "Longer", "Mid"]; selected, look = :step)
    io = print_document(proj, step_group(1))
    drawn = keys(_drawn_text_positions(io.output))
    @test "A" in drawn && !("Longer" in drawn) && !("Mid" in drawn)
    # The control is as wide as its widest option, whichever option it shows.
    @test Int(io.output.w[]) == Int(print_document(proj, step_group(2)).output.w[])
    # A press anywhere on it picks the next option, and with Shift the one before;
    # the ends wrap.
    press(io, modifiers) = read_intent(proj, io, MouseClick(:left, 3, 4, modifiers; time = 0.0))
    @test press(io, ModifierKeys()).value == 2
    @test press(io, ModifierKeys(shift = true)).value == 3
    @test press(print_document(proj, step_group(3)), ModifierKeys()).value == 1
    # Return and Space with no modifier step too; another key does nothing.
    key(k, modifiers = ModifierKeys()) = read_intent(proj, io, KeyDown(k, modifiers; time = 0.0))
    @test key(:return).value == 2
    @test key(:space).value == 2
    @test key(:return, ModifierKeys(ctrl = true)) === nothing
    @test key(:a) === nothing
    # A group of one option has nothing to step to.
    @test press(print_document(proj, WidgetToggleGroup(["Only"]; look = :step)), ModifierKeys()) === nothing
end

@testset "a toggle flips from a press, and from Return and Space with the focus" begin
    t  = WidgetToggle("Bold")
    io = print_document(proj, t)
    x, y = _drawn_text_positions(io.output)["Bold"]
    press = read_intent(proj, io, MouseClick(:left, x + 2, y + 2, ModifierKeys(); time = 0.0))
    @test press isa ReplaceReferencedValueOperation
    @test press.document === t && press.value === true
    @test read_intent(proj, io, MouseClick(:right, x + 2, y + 2, ModifierKeys(); time = 0.0)) === nothing
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
    @test read_intent(proj, off_io, MouseClick(:left, x + 2, y + 2, ModifierKeys(); time = 0.0)) === nothing
    @test read_intent(proj, print_document(proj, _focus_second(off)), _key(:space)) === nothing
end

@testset "a radio group selects the option under a press, and the arrows move it" begin
    r  = WidgetRadioGroup(["Default", "Comfortable", "Compact"]; selected = 1)
    io = print_document(proj, r)
    at = _drawn_text_positions(io.output)
    compact = at["Compact"]; comfortable = at["Comfortable"]; default = at["Default"]
    pick = read_intent(proj, io, MouseClick(:left, compact[1] + 2, compact[2] + 2, ModifierKeys(); time = 0.0))
    @test pick isa ReplaceReferencedValueOperation
    @test pick.document === r && pick.value == 3
    # The circle of a row is part of its target, left of the word.
    @test read_intent(proj, io, MouseClick(:left, 2, comfortable[2] + 2, ModifierKeys(); time = 0.0)).value == 2
    # The option that is on is not a change, and a right press is not a pick.
    @test read_intent(proj, io, MouseClick(:left, default[1] + 2, default[2] + 2, ModifierKeys(); time = 0.0)) === nothing
    @test read_intent(proj, io, MouseClick(:right, compact[1] + 2, compact[2] + 2, ModifierKeys(); time = 0.0)) === nothing

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
    @test read_intent(proj, off_io, MouseClick(:left, lx + 2, ly + 2, ModifierKeys(); time = 0.0)) === nothing
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
        @test read_intent(proj, control_io, MouseClick(:left, 2, 2, ModifierKeys(); time = 0.0)) !== nothing
        @test read_intent(proj, control_io, MouseClick(:right, 2, 2, ModifierKeys(); time = 0.0)) === nothing
        @test read_intent(proj, control_io, MouseClick(:middle, 2, 2, ModifierKeys(); time = 0.0)) === nothing
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
