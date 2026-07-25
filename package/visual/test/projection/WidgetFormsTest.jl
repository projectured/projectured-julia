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
    @test pick2.path == widget_list_selection(2)
    @test read_intent(proj, io, KeyDown(:down, ModifierKeys(), false)).path ==
          widget_list_selection(2)                                                         # 1 → 2
    @test read_intent(proj, io, KeyDown(:up, ModifierKeys(), false)).path ==
          widget_list_selection(1)                                                         # 1 → 1 (floor)
    # `selected=` sugar and `widget_list_selected` are inverses; 0 = none.
    @test widget_list_selected(l) == 1
    @test widget_list_selected(WidgetList(Point2D(0, 0), ["Alpha", "Beta"])) == 0
    # An empty list is inert.
    @test read_intent(proj, print_document(proj, WidgetList(Point2D(0, 0), String[])),
                          MousePress(:left, 2, 2, ModifierKeys())) === nothing
end

@testset "numeric_validator accepts digits, rejects letters" begin
    v = numeric_validator()
    @test v("123") === true
    @test v("") === true            # a deletion
    @test v("12") === true
    @test v("a") === false
    @test v("1a") === false
    @test numeric_validator()(".") === true        # decimal allowed by default
    @test numeric_validator(; integer=true)(".") === false
    # The field carries the validator.
    t = WidgetText(Point2D(0, 0), "x"; validator=v)
    @test t.validator === v
end

end # @testset
end # function
