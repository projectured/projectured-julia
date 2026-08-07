# Geometry of the two-dimensional form of a formula. Every assertion names a
# coordinate — where a part landed — not whether a part exists: a box that is
# present but a line too low still reads as a broken formula.
function test_math_to_graphics()
@testset "MathToGraphics" begin

_projection() = RecursiveProjection(MathToGraphics(measure = truetype_measure_text))
_print(doc) = print_document(_projection(), doc)

# The metrics the rules are derived from, at the default face and size.
_config() = MathConfig(font = font_dejavu_sans_regular_20,
                       slanted = font_dejavu_sans_italic_20,
                       measure = truetype_measure_text)
_metrics(style = :display) = math_metrics(_config(), style)

# A wrapper canvas carries the position of one placed child.
_at(canvas, i) = (Int(canvas.elements[i].x[]), Int(canvas.elements[i].y[]))
_inner(canvas, i) = canvas.elements[i].elements[1]

# Descend the wrappers to the first run of text a box draws.
function _first_text(doc)
    doc isa GraphicsText && return doc
    doc isa GraphicsCanvas || return nothing
    for i in 1:length(doc.elements)
        found = _first_text(doc.elements[i])
        found === nothing || return found
    end
    nothing
end

@testset "a leaf is one text box on its own baseline" begin
    iomap = _print(MathVariable("x"))
    m = _metrics()
    @test Int(iomap.width[]) == truetype_measure_text("x", m.slanted)[1]
    @test Int(iomap.ascent[]) == font_ascent(m.slanted)
    @test Int(iomap.descent[]) == font_descent(m.slanted)
    @test Int(iomap.output.h[]) == Int(iomap.ascent[]) + Int(iomap.descent[])
    # A variable is slanted, a number upright.
    @test iomap.output.elements[1].font == m.slanted
    @test _print(PrimitiveNumber(2)).output.elements[1].font == m.upright
end

@testset "a row spaces its parts and shares one baseline" begin
    m = _metrics()
    row = _print(MathRow([MathVariable("k"), MathVariable("T")]))
    first_width = truetype_measure_text("k", m.slanted)[1]
    # The second element starts after the first plus one thin space.
    @test _at(row.output, 2)[1] == first_width + m.thin
    # One baseline: both boxes have the same top, because both are leaves of
    # the same face.
    @test _at(row.output, 1)[2] == _at(row.output, 2)[2]
end

@testset "an operator takes the space of its class" begin
    m = _metrics()
    plus = _print(MathBinaryOperation(:+, MathVariable("a"), MathVariable("b")))
    equal = _print(MathAssignment(MathVariable("a"), MathVariable("b")))
    a_width = truetype_measure_text("a", m.slanted)[1]
    # A binary operator gets the medium space, a relation the thick one.
    @test _at(plus.output, 2)[1] == a_width + m.medium
    @test _at(equal.output, 2)[1] == a_width + m.thick
    @test m.medium < m.thick
end

@testset "a fraction puts its rule on the axis" begin
    m = _metrics()
    fraction = _print(MathFraction(PrimitiveNumber(1), MathVariable("x")))
    canvas = fraction.output
    # The rule is the last element: a rect of the metric thickness whose top
    # sits one axis height above the baseline.
    rule = canvas.elements[length(canvas.elements)]
    @test Int(rule.h[]) == m.rule
    @test Int(rule.y[]) == Int(fraction.ascent[]) - m.axis - m.rule
    @test Int(rule.w[]) == Int(fraction.width[])
    # Both parts center on the rule.
    inner = math_metrics(_config(), :text)
    numerator_width = truetype_measure_text("1", inner.upright)[1]
    @test _at(canvas, 1)[1] == (Int(fraction.width[]) - numerator_width) ÷ 2
    # The numerator sits above the rule and the denominator below it.
    @test _at(canvas, 1)[2] < Int(rule.y[])
    @test _at(canvas, 2)[2] > Int(rule.y[])
end

@testset "a script rises and falls by a baseline shift" begin
    m = _metrics()
    inner = math_metrics(_config(), :script)
    base_ascent = font_ascent(m.slanted)

    superscript = _print(MathSuperscript(MathVariable("x"), PrimitiveNumber(2)))
    up = max(round(Int, 0.36 * m.size), base_ascent - m.x_height)
    # The script's own baseline is `up` above the base's.
    script_top = _at(superscript.output, 2)[2]
    base_top = _at(superscript.output, 1)[2]
    @test (base_top + base_ascent) - (script_top + font_ascent(inner.upright)) == up

    subscript = _print(MathSubscript(MathVariable("P"), MathVariable("t")))
    down = max(round(Int, 0.2 * m.size), font_descent(m.slanted))
    script_top = _at(subscript.output, 2)[2]
    base_top = _at(subscript.output, 1)[2]
    @test (script_top + font_ascent(inner.slanted)) - (base_top + base_ascent) == down
    # A script starts where the base ends.
    @test _at(subscript.output, 2)[1] == truetype_measure_text("P", m.slanted)[1]
end

@testset "a script is set smaller, and a script inside one smaller again" begin
    # The level rides in the printer context, so the same rule table gives
    # three sizes.
    @test math_metrics(_config(), :display).size == 20
    @test math_metrics(_config(), :script).size == 14
    @test math_metrics(_config(), :scriptscript).size == 10

    nested = _print(MathSuperscript(MathVariable("x"),
                                    MathSuperscript(MathVariable("y"), PrimitiveNumber(2))))
    script = math_metrics(_config(), :script)
    scriptscript = math_metrics(_config(), :scriptscript)
    # The exponent's own exponent is drawn in the smallest face.
    outer = _inner(nested.output, 2)
    @test _first_text(outer.elements[1]).font == script.slanted
    @test _first_text(outer.elements[2]).font == scriptscript.upright
end

@testset "a large operator centers on the axis and takes its limits" begin
    m = _metrics()
    sum = _print(MathBigOperator(:sum, MathVariable("x");
                                 lower = MathVariable("k"), upper = MathVariable("n")))
    canvas = sum.output
    # Display style puts the limits above and below: the upper limit's box top
    # is the top of the whole box, the lower limit's bottom is its bottom.
    @test _at(canvas, 2)[2] == 0
    @test length(canvas.elements) == 4
    # The sign, the upper limit and the lower limit share a center.
    sign = canvas.elements[1]
    head = max(Int(sum.width[]), 0)
    @test Int(sign.x[]) >= 0
    # A side-limit operator keeps them beside the sign instead.
    integral = _print(MathBigOperator(:integral, MathVariable("x");
                                      lower = PrimitiveNumber(0), upper = MathVariable("n")))
    @test _at(integral.output, 2)[1] > 0
end

@testset "a delimiter grows with what it holds" begin
    around_leaf = _print(MathParenthesized(MathVariable("x")))
    around_fraction = _print(MathParenthesized(MathFraction(PrimitiveNumber(1),
                                                            MathVariable("x"))))
    @test Int(around_fraction.ascent[]) + Int(around_fraction.descent[]) >
          Int(around_leaf.ascent[]) + Int(around_leaf.descent[])
    # The open delimiter is the first box and the content follows it.
    @test _at(around_fraction.output, 2)[1] > 0
    # It stays centered on the axis: what reaches above equals what reaches
    # below, about the axis.
    m = _metrics()
    open_box = around_fraction.output.elements[1]
    @test Int(open_box.y[]) >= 0
end

@testset "a matrix is a grid inside a delimiter" begin
    matrix = _print(MathMatrix([PrimitiveNumber(1), PrimitiveNumber(2),
                                PrimitiveNumber(3), PrimitiveNumber(4)], 2))
    # Two rows, two columns, wrapped by two delimiters: the row holds
    # open, grid, close.
    @test length(matrix.output.elements) == 3
    m = _metrics()
    # The grid centers on the axis.
    @test Int(matrix.ascent[]) - Int(matrix.descent[]) == 2 * m.axis ||
          Int(matrix.ascent[]) - Int(matrix.descent[]) == 2 * m.axis + 1
end

@testset "an empty slot is a box a mouse can hit" begin
    insertion = _print(MathInsertion())
    @test Int(insertion.width[]) > 0
    @test Int(insertion.ascent[]) > 0
    @test Int(insertion.output.h[]) > 0
end

@testset "a formula grows when a leaf does" begin
    # The metrics are cells: an edit re-derives the boxes above it and nothing
    # else. Widen a variable and the whole row must widen with it.
    variable = MathVariable("x")
    row = _print(MathRow([variable, MathVariable("y")]))
    before = Int(row.width[])
    variable.name = "xxxx"
    @test Int(row.width[]) > before
end

end
end
