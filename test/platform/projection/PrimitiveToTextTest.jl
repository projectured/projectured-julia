
_value_range(start::Int, stop::Int) =
    ConcreteReference(FieldReferenceStep("value"),
        ConcreteReference(RangeReferenceStep(start, stop), EmptyReference()))

# The structural place `.elements[1].elements[1].content{k}`: character `k` of the
# one run of the one line.
_line_content_pos(char_idx::Int) =
    ConcreteReference(FieldReferenceStep("elements"),
        ConcreteReference(ElementReferenceStep(1),
            ConcreteReference(FieldReferenceStep("elements"),
                ConcreteReference(ElementReferenceStep(1),
                    ConcreteReference(FieldReferenceStep("content"),
                        ConcreteReference(PositionReferenceStep(char_idx), EmptyReference()))))))

# The one run of the one line of a printed primitive.
_run(out::TextBlock) = out.elements[1].elements[1]

function test_primitive_to_text()
@testset "PrimitiveToText" begin

# ── PrimitiveBoolToText ──────────────────────────────────────────────────────

@testset "bool prints one line of one run" begin
    b = PrimitiveBool(true)
    p = PrimitiveBoolToText()
    out = print_document(p, nothing, b, nothing).output
    @test out isa TextBlock
    @test length(out.elements) == 1
    @test _run(out).content == "true"
    @test _run(out).font == StyleFont("Ubuntu Mono", 14)
    @test _run(out).font_color == resolve_theme_color(ColorRole(:boolean_literal), Appearance())
end

@testset "bool reacts to value change" begin
    b = PrimitiveBool(true)
    p = PrimitiveBoolToText()
    out = print_document(p, nothing, b, nothing).output
    @test _run(out).content == "true"
    b.value = false
    @test _run(out).content == "false"
end

# ── PrimitiveNumberToText ────────────────────────────────────────────────────

@testset "number prints one line of one run" begin
    n = PrimitiveNumber(42)
    p = PrimitiveNumberToText()
    out = print_document(p, nothing, n, nothing).output
    @test length(out.elements) == 1
    @test _run(out).content == "42"
    @test _run(out).font_color == resolve_theme_color(ColorRole(:number_literal), Appearance())
end

@testset "number nothing prints empty" begin
    n = PrimitiveNumber(nothing)
    p = PrimitiveNumberToText()
    out = print_document(p, nothing, n, nothing).output
    @test _run(out).content == ""
end

# ── PrimitiveStringToTextBlock ────────────────────────────────────────────────────

@testset "string prints one line of one run (no quotes)" begin
    s = PrimitiveString("hi")
    p = PrimitiveStringToTextBlock()
    out = print_document(p, nothing, s, nothing).output
    @test length(out.elements) == 1
    @test _run(out).content == "hi"
    @test _run(out).font_color == resolve_theme_color(ColorRole(:string_literal), Appearance())
end

@testset "string reacts to value change" begin
    s = PrimitiveString("hi")
    p = PrimitiveStringToTextBlock()
    out = print_document(p, nothing, s, nothing).output
    @test _run(out).content == "hi"
    s.value = "world"
    @test _run(out).content == "world"
end

@testset "a string with a break prints a line for each line, and no run holds the break" begin
    s = PrimitiveString("x = 1\nx + 1")
    p = PrimitiveStringToTextBlock()
    out = print_document(p, nothing, s, nothing).output
    @test [line.elements[1].content for line in out.elements] == ["x = 1", "x + 1"]
    s.value = "x = 1"
    @test [line.elements[1].content for line in out.elements] == ["x = 1"]
end

# ── Selection forward ────────────────────────────────────────────────────────

@testset "selection forward .value[k] → the flat caret {k}" begin
    s = PrimitiveString("abc")
    set_selection!(s, _value_range(2, 2))
    p = PrimitiveStringToTextBlock()
    out = print_document(p, nothing, s, nothing).output
    sel = strip_reference_types(out.selection)
    @test sel isa ConcreteReference
    @test sel.head isa TextRangeReferenceStep
    @test (sel.head.start, sel.head.stop) == (2, 2)
end

# ── Reference mapping ────────────────────────────────────────────────────────

@testset "map_reference_forward .value[k]" begin
    s = PrimitiveString("abc")
    p = PrimitiveStringToTextBlock()
    iomap = print_document(p, nothing, s, nothing)
    out = map_reference_forward(p, iomap, _value_range(2, 2))
    @test out isa ConcreteReference
    @test out.head isa TextRangeReferenceStep && (out.head.start, out.head.stop) == (2, 2)
end

@testset "map_reference_backward .elements[1].elements[1].content[k]" begin
    s = PrimitiveString("abc")
    p = PrimitiveStringToTextBlock()
    iomap = print_document(p, nothing, s, nothing)
    inp = map_reference_backward(p, iomap, _line_content_pos(2))
    @test inp isa ConcreteReference
    @test inp.head isa FieldReferenceStep && inp.head.name == "value"
    @test inp.tail.head isa RangeReferenceStep
    @test inp.tail.head.start == 2 && inp.tail.head.stop == 2
end

@testset "a range maps both ways" begin
    s = PrimitiveString("hello")
    p = PrimitiveStringToTextBlock()
    iomap = print_document(p, nothing, s, nothing)
    # The block has one line of one run, so the value's range is the flat range.
    forward = map_reference_forward(p, iomap, _value_range(1, 4))
    @test forward.head isa TextRangeReferenceStep
    @test (forward.head.start, forward.head.stop) == (1, 4)
    backward = map_reference_backward(p, iomap, TextModule.make_flat_range_reference(1, 4))
    @test backward.head == FieldReferenceStep("value")
    @test (backward.tail.head.start, backward.tail.head.stop) == (1, 4)
    # A flat caret still maps to a caret.
    caret = map_reference_backward(p, iomap, TextModule.make_flat_caret_reference(2))
    @test (caret.tail.head.start, caret.tail.head.stop) == (2, 2)
end

@testset "an edit that holds a break is no edit of a value" begin
    # The value of a primitive is one line: Enter, which the text domain reads as a
    # break, goes on to the bindings around the text.
    caret = TextModule.make_flat_caret_reference(1)
    for (p, d) in ((PrimitiveStringToTextBlock(), PrimitiveString("ab")),
                   (PrimitiveNumberToText(), PrimitiveNumber(12)),
                   (PrimitiveInsertionToText(), PrimitiveInsertion(; value = "ab")))
        iomap = print_document(p, nothing, d, nothing)
        @test read_intent(p, iomap, ReplaceTextRangeOperation(caret, "\n")) === nothing
        typed = read_intent(p, iomap, ReplaceTextRangeOperation(caret, "x"))
        @test typed !== nothing
    end
end

# ── KeyPress / KeyDown producers ─────────────────────────────────────────────

@testset "string KeyPress produces ReplaceStringRangeOperation" begin
    s = PrimitiveString("ab")
    set_selection!(s, _value_range(0, 0))
    p = PrimitiveStringToTextBlock()
    iomap = SimpleIoMap(p, s, nothing)
    op = read_intent(p, iomap, KeyPress('x'; time = 0.0))
    @test op isa ReplaceStringRangeOperation
    @test op.replacement == "x"
    @test op.reference.head isa FieldReferenceStep && op.reference.head.name == "value"
    @test op.reference.tail.head isa RangeReferenceStep
    @test op.reference.tail.head.start == 0 && op.reference.tail.head.stop == 0
end

@testset "string KeyDown backspace produces op" begin
    s = PrimitiveString("ab")
    set_selection!(s, _value_range(2, 2))
    p = PrimitiveStringToTextBlock()
    iomap = SimpleIoMap(p, s, nothing)
    op = read_intent(p, iomap, KeyDown(:backspace, ModifierKeys(); time = 0.0))
    @test op isa ReplaceStringRangeOperation
    @test op.replacement == ""
    @test op.reference.tail.head.start == 1 && op.reference.tail.head.stop == 2
end

@testset "string KeyDown delete produces op" begin
    s = PrimitiveString("ab")
    set_selection!(s, _value_range(0, 0))
    p = PrimitiveStringToTextBlock()
    iomap = SimpleIoMap(p, s, nothing)
    op = read_intent(p, iomap, KeyDown(:delete, ModifierKeys(); time = 0.0))
    @test op isa ReplaceStringRangeOperation
    @test op.reference.tail.head.start == 0 && op.reference.tail.head.stop == 1
end

@testset "string KeyPress inserts (KeyPress ignores modifiers)" begin
    # Reified as document-level `@gestures PrimitiveString` reached via the generic
    # `read_gesture` fallback: KeyPress patterns ignore modifiers (a real Ctrl-combo
    # is a KeyDown, never a KeyPress), so a printable inserts regardless of a stray
    # ctrl flag — the old defensive `ctrl` reject is intentionally gone (matches Text/JSON).
    s = PrimitiveString("ab")
    set_selection!(s, _value_range(0, 0))
    p = PrimitiveStringToTextBlock()
    iomap = SimpleIoMap(p, s, nothing)
    evt = KeyPress('x', "x", ModifierKeys(ctrl = true); time = 0.0)
    op = read_intent(p, iomap, evt)
    @test op isa ReplaceStringRangeOperation
    @test op.replacement == "x"
end

@testset "string backspace at start returns nothing" begin
    s = PrimitiveString("ab")
    set_selection!(s, _value_range(0, 0))
    p = PrimitiveStringToTextBlock()
    iomap = SimpleIoMap(p, s, nothing)
    @test read_intent(p, iomap, KeyDown(:backspace, ModifierKeys(); time = 0.0)) === nothing
end

@testset "string delete at end returns nothing" begin
    s = PrimitiveString("ab")
    set_selection!(s, _value_range(2, 2))
    p = PrimitiveStringToTextBlock()
    iomap = SimpleIoMap(p, s, nothing)
    @test read_intent(p, iomap, KeyDown(:delete, ModifierKeys(); time = 0.0)) === nothing
end

# ── Composite constructor ────────────────────────────────────────────────────

@testset "PrimitiveToText composite dispatches per type" begin
    p = PrimitiveToText()
    @test print_document(p, nothing, PrimitiveBool(true), nothing).output isa TextBlock
    @test print_document(p, nothing, PrimitiveNumber(7), nothing).output isa TextBlock
    @test print_document(p, nothing, PrimitiveString("x"), nothing).output isa TextBlock
end

end # @testset
end # function
