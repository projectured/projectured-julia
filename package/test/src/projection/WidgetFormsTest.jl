# Form widgets (Qt-gap Parts C/D/E): WidgetSpinBox steppers, WidgetList selection,
# and the numeric validator. Steppers/list clicks emit ReplaceReferencedValueOperation(value
# / selected); the validator is an acceptor the editable text reader consults.

function test_widget_forms()
@testset "WidgetSpinBox / WidgetList / validator" begin

proj = make_widget_projection_example()

@testset "spin box steps up/down and clamps to [min, max]" begin
    s = WidgetSpinBox(Point2D(0, 0), 5; min=0, max=10, step=2)
    io = projection_print(proj, s)
    cw = Int(io.output.w[]); ch = Int(io.output.h[])
    up   = projection_read(proj, io, MousePress(:left, cw - 2, 2, Modifiers()))           # top stepper
    down = projection_read(proj, io, MousePress(:left, cw - 2, ch - 2, Modifiers()))       # bottom stepper
    @test up isa ReplaceReferencedValueOperation && up.value == 7
    @test down isa ReplaceReferencedValueOperation && down.value == 3
    # A click in the field area (left of the steppers) does not step.
    @test projection_read(proj, io, MousePress(:left, 2, 2, Modifiers())) === nothing

    # Clamp: stepping past max stays at max; past min stays at min.
    hi = projection_print(proj, WidgetSpinBox(Point2D(0, 0), 10; min=0, max=10, step=5))
    @test projection_read(proj, hi, MousePress(:left, Int(hi.output.w[]) - 2, 2, Modifiers())).value == 10
    lo = projection_print(proj, WidgetSpinBox(Point2D(0, 0), 0; min=0, max=10, step=5))
    @test projection_read(proj, lo, MousePress(:left, Int(lo.output.w[]) - 2, Int(lo.output.h[]) - 2, Modifiers())).value == 0

    # Disabled is inert.
    dis = projection_print(proj, WidgetSpinBox(Point2D(0, 0), 5; enabled=false))
    @test projection_read(proj, dis, MousePress(:left, Int(dis.output.w[]) - 2, 2, Modifiers())) === nothing
end

@testset "list click + arrow keys move the selection" begin
    l  = WidgetList(Point2D(0, 0), ["Alpha", "Beta", "Gamma"]; selected=1)
    io = projection_print(proj, l)
    rh = Int(io.output.h[]) ÷ 3
    pick2 = projection_read(proj, io, MousePress(:left, 5, rh + 2, Modifiers()))           # row 2
    @test pick2 isa ReplaceReferencedValueOperation && pick2.value == 2
    @test projection_read(proj, io, KeyDown(:down, Modifiers(), false)).value == 2          # 1 → 2
    @test projection_read(proj, io, KeyDown(:up, Modifiers(), false)).value == 1            # 1 → 1 (floor)
    # An empty list is inert.
    @test projection_read(proj, projection_print(proj, WidgetList(Point2D(0, 0), String[])),
                          MousePress(:left, 2, 2, Modifiers())) === nothing
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
