# Form widgets (Qt-gap Parts C/D/E): WidgetSpinBox steppers, WidgetList selection,
# and the numeric validator. Steppers emit ReplaceReferencedValueOperation(value);
# the list reports selection as a ReplaceSelectionOperation like every other
# widget; the validator is an acceptor the editable text reader consults.

function test_widget_forms()
@testset "WidgetSpinBox / WidgetList / validator" begin

proj = make_widget_projection_example()

@testset "spin box steps up/down and clamps to [min, max]" begin
    s = WidgetSpinBox(Point2D(0, 0), 5; min=0, max=10, step=2)
    io = print_document(proj, s)
    cw = Int(io.output.w[]); ch = Int(io.output.h[])
    up   = read_intent(proj, io, MousePress(:left, cw - 2, 2, ModifierKeys()))           # top stepper
    down = read_intent(proj, io, MousePress(:left, cw - 2, ch - 2, ModifierKeys()))       # bottom stepper
    @test up isa ReplaceReferencedValueOperation && up.value == 7
    @test down isa ReplaceReferencedValueOperation && down.value == 3
    # A click in the field area (left of the steppers) does not step.
    @test read_intent(proj, io, MousePress(:left, 2, 2, ModifierKeys())) === nothing

    # Clamp: stepping past max stays at max; past min stays at min.
    hi = print_document(proj, WidgetSpinBox(Point2D(0, 0), 10; min=0, max=10, step=5))
    @test read_intent(proj, hi, MousePress(:left, Int(hi.output.w[]) - 2, 2, ModifierKeys())).value == 10
    lo = print_document(proj, WidgetSpinBox(Point2D(0, 0), 0; min=0, max=10, step=5))
    @test read_intent(proj, lo, MousePress(:left, Int(lo.output.w[]) - 2, Int(lo.output.h[]) - 2, ModifierKeys())).value == 0

    # Disabled is inert.
    dis = print_document(proj, WidgetSpinBox(Point2D(0, 0), 5; enabled=false))
    @test read_intent(proj, dis, MousePress(:left, Int(dis.output.w[]) - 2, 2, ModifierKeys())) === nothing
end

@testset "list click + arrow keys move the selection" begin
    l  = WidgetList(Point2D(0, 0), ["Alpha", "Beta", "Gamma"]; selected=1)
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
    @test get_widget_list_selected(WidgetList(Point2D(0, 0), ["Alpha", "Beta"])) == 0
    # An empty list is inert.
    @test read_intent(proj, print_document(proj, WidgetList(Point2D(0, 0), String[])),
                          MousePress(:left, 2, 2, ModifierKeys())) === nothing
end

@testset "toggle group picks the segment under the press" begin
    g  = WidgetToggleGroup(Point2D(0, 0), ["Run", "Fast", "Express"]; selected=2)
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
    on_first = print_document(proj, WidgetToggleGroup(Point2D(0, 0),
                                                      ["Run", "Fast", "Express"]; selected=1))
    @test read_intent(proj, on_first, MousePress(:left, left, 4, ModifierKeys())) === nothing

    # Past the right edge is outside the control, which every widget declines.
    @test read_intent(proj, io, MousePress(:left, w + 5, 4, ModifierKeys())) === nothing

    # With a target, the pick names what it changes: a group that is *for*
    # something writes that thing's field, and `values` says what a segment means.
    # This is what keeps an enclosing projection from having to guess which
    # control was pressed.
    holder = WidgetLabel(Point2D(0, 0), "")          # any document will do as a target
    aimed  = WidgetToggleGroup(Point2D(0, 0), ["Run", "Fast", "Express"]; selected=2,
                               values = [:run, :fast, :express],
                               target = holder, field = "text")
    aimed_io = print_document(proj, aimed)
    picked = read_intent(proj, aimed_io, MousePress(:left, 2, 4, ModifierKeys()))
    @test picked isa ReplaceReferencedValueOperation
    @test picked.document === holder
    @test picked.value === :run

    # A right press is not a pick, and a disabled group is inert.
    @test read_intent(proj, io, MousePress(:right, left, 4, ModifierKeys())) === nothing
    dis = WidgetToggleGroup(Point2D(0, 0), ["Run", "Fast"]; selected=2, enabled=false)
    @test read_intent(proj, print_document(proj, dis),
                      MousePress(:left, 4, 4, ModifierKeys())) === nothing
    # An invisible one draws nothing and answers nothing.
    inv = WidgetToggleGroup(Point2D(0, 0), ["Run", "Fast"]; visible=false)
    @test read_intent(proj, print_document(proj, inv),
                      MousePress(:left, 4, 4, ModifierKeys())) === nothing
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
    t = WidgetText(Point2D(0, 0), "x"; validator=v)
    @test t.validator === v
end

end # @testset
end # function
