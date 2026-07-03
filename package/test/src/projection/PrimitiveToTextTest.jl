using Projectured: PrimitiveBool, PrimitiveNumber, PrimitiveString,
                    PrimitiveBoolToText, PrimitiveNumberToText, PrimitiveStringToTextText,
                    PrimitiveToText, TextText, TextString,
                    projection_print, projection_read,
                    map_reference_forward, map_reference_backward,
                    SimpleIoMap, ReplaceSelectionOperation,
                    ReplaceStringRangeOperation,
                    KeyPress, KeyDown, Modifiers,
                    ConcreteReferencePath, EmptyReferencePath,
                    FieldReference, RangeReference, ElementReference, PositionReference,
                    set_selection!,
                    color_solarized_cyan, color_solarized_magenta, color_solarized_green,
                    font_ubuntu_monospace_regular_20

_value_range(start::Int, stop::Int) =
    ConcreteReferencePath(FieldReference("value"),
        ConcreteReferencePath(RangeReference(start, stop), EmptyReferencePath()))

_elem_content_pos(span_idx::Int, char_idx::Int) =
    ConcreteReferencePath(FieldReference("elements"),
        ConcreteReferencePath(ElementReference(span_idx),
            ConcreteReferencePath(FieldReference("content"),
                ConcreteReferencePath(PositionReference(char_idx), EmptyReferencePath()))))

function test_primitive_to_text()
@testset "PrimitiveToText" begin

# ── PrimitiveBoolToText ──────────────────────────────────────────────────────

@testset "bool prints single span" begin
    b = PrimitiveBool(true)
    p = PrimitiveBoolToText()
    out = projection_print(p, nothing, b, nothing).output
    @test out isa TextText
    @test length(out.elements) == 1
    @test out.elements[1].content == "true"
    @test out.elements[1].font == font_ubuntu_monospace_regular_20
    @test out.elements[1].font_color == color_solarized_cyan
end

@testset "bool reacts to value change" begin
    b = PrimitiveBool(true)
    p = PrimitiveBoolToText()
    out = projection_print(p, nothing, b, nothing).output
    @test out.elements[1].content == "true"
    b.value = false
    @test out.elements[1].content == "false"
end

# ── PrimitiveNumberToText ────────────────────────────────────────────────────

@testset "number prints single span" begin
    n = PrimitiveNumber(42)
    p = PrimitiveNumberToText()
    out = projection_print(p, nothing, n, nothing).output
    @test length(out.elements) == 1
    @test out.elements[1].content == "42"
    @test out.elements[1].font_color == color_solarized_magenta
end

@testset "number nothing prints empty" begin
    n = PrimitiveNumber(nothing)
    p = PrimitiveNumberToText()
    out = projection_print(p, nothing, n, nothing).output
    @test out.elements[1].content == ""
end

# ── PrimitiveStringToTextText ────────────────────────────────────────────────────

@testset "string prints single span (no quotes)" begin
    s = PrimitiveString("hi")
    p = PrimitiveStringToTextText()
    out = projection_print(p, nothing, s, nothing).output
    @test length(out.elements) == 1
    @test out.elements[1].content == "hi"
    @test out.elements[1].font_color == color_solarized_green
end

@testset "string reacts to value change" begin
    s = PrimitiveString("hi")
    p = PrimitiveStringToTextText()
    out = projection_print(p, nothing, s, nothing).output
    @test out.elements[1].content == "hi"
    s.value = "world"
    @test out.elements[1].content == "world"
end

# ── Selection forward ────────────────────────────────────────────────────────

@testset "selection forward .value[k] → .elements[1].content[k]" begin
    s = PrimitiveString("abc")
    set_selection!(s, _value_range(2, 2))
    p = PrimitiveStringToTextText()
    out = projection_print(p, nothing, s, nothing).output
    sel = out.selection
    @test sel isa ConcreteReferencePath
    @test sel.head isa FieldReference && sel.head.name == "elements"
    elt = sel.tail.head
    @test elt isa RangeReference
    @test elt.start == 0 && elt.stop == 1
    content_step = sel.tail.tail.head
    @test content_step isa FieldReference && content_step.name == "content"
    pos = sel.tail.tail.tail.head
    @test pos isa RangeReference
    @test pos.start == 2 && pos.stop == 2
end

# ── Reference mapping ────────────────────────────────────────────────────────

@testset "map_reference_forward .value[k]" begin
    s = PrimitiveString("abc")
    p = PrimitiveStringToTextText()
    iomap = projection_print(p, nothing, s, nothing)
    out = map_reference_forward(p, iomap, _value_range(2, 2))
    @test out isa ConcreteReferencePath
    @test out.head isa FieldReference && out.head.name == "elements"
end

@testset "map_reference_backward .elements[1].content[k]" begin
    s = PrimitiveString("abc")
    p = PrimitiveStringToTextText()
    iomap = projection_print(p, nothing, s, nothing)
    inp = map_reference_backward(p, iomap, _elem_content_pos(1, 2))
    @test inp isa ConcreteReferencePath
    @test inp.head isa FieldReference && inp.head.name == "value"
    @test inp.tail.head isa RangeReference
    @test inp.tail.head.start == 2 && inp.tail.head.stop == 2
end

# ── KeyPress / KeyDown producers ─────────────────────────────────────────────

@testset "string KeyPress produces ReplaceStringRangeOperation" begin
    s = PrimitiveString("ab")
    set_selection!(s, _value_range(0, 0))
    p = PrimitiveStringToTextText()
    iomap = SimpleIoMap(p, s, nothing)
    op = projection_read(p, iomap, KeyPress('x'))
    @test op isa ReplaceStringRangeOperation
    @test op.replacement == "x"
    @test op.reference.head isa FieldReference && op.reference.head.name == "value"
    @test op.reference.tail.head isa RangeReference
    @test op.reference.tail.head.start == 0 && op.reference.tail.head.stop == 0
end

@testset "string KeyDown backspace produces op" begin
    s = PrimitiveString("ab")
    set_selection!(s, _value_range(2, 2))
    p = PrimitiveStringToTextText()
    iomap = SimpleIoMap(p, s, nothing)
    op = projection_read(p, iomap, KeyDown(:backspace, Modifiers()))
    @test op isa ReplaceStringRangeOperation
    @test op.replacement == ""
    @test op.reference.tail.head.start == 1 && op.reference.tail.head.stop == 2
end

@testset "string KeyDown delete produces op" begin
    s = PrimitiveString("ab")
    set_selection!(s, _value_range(0, 0))
    p = PrimitiveStringToTextText()
    iomap = SimpleIoMap(p, s, nothing)
    op = projection_read(p, iomap, KeyDown(:delete, Modifiers()))
    @test op isa ReplaceStringRangeOperation
    @test op.reference.tail.head.start == 0 && op.reference.tail.head.stop == 1
end

@testset "string KeyPress inserts (KeyPress ignores modifiers)" begin
    # Reified as document-level `@gestures PrimitiveString` reached via the generic
    # `document_read` fallback: KeyPress patterns ignore modifiers (a real Ctrl-combo
    # is a KeyDown, never a KeyPress), so a printable inserts regardless of a stray
    # ctrl flag — the old defensive `ctrl` reject is intentionally gone (matches Text/JSON).
    s = PrimitiveString("ab")
    set_selection!(s, _value_range(0, 0))
    p = PrimitiveStringToTextText()
    iomap = SimpleIoMap(p, s, nothing)
    evt = KeyPress('x', "x", Modifiers(true, false, false, false))
    op = projection_read(p, iomap, evt)
    @test op isa ReplaceStringRangeOperation
    @test op.replacement == "x"
end

@testset "string backspace at start returns nothing" begin
    s = PrimitiveString("ab")
    set_selection!(s, _value_range(0, 0))
    p = PrimitiveStringToTextText()
    iomap = SimpleIoMap(p, s, nothing)
    @test projection_read(p, iomap, KeyDown(:backspace, Modifiers())) === nothing
end

@testset "string delete at end returns nothing" begin
    s = PrimitiveString("ab")
    set_selection!(s, _value_range(2, 2))
    p = PrimitiveStringToTextText()
    iomap = SimpleIoMap(p, s, nothing)
    @test projection_read(p, iomap, KeyDown(:delete, Modifiers())) === nothing
end

# ── Composite constructor ────────────────────────────────────────────────────

@testset "PrimitiveToText composite dispatches per type" begin
    p = PrimitiveToText()
    @test projection_print(p, nothing, PrimitiveBool(true), nothing).output isa TextText
    @test projection_print(p, nothing, PrimitiveNumber(7), nothing).output isa TextText
    @test projection_print(p, nothing, PrimitiveString("x"), nothing).output isa TextText
end

end # @testset
end # function
