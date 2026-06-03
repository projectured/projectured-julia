using Projectured: PositionReference, ConcreteReferencePath, EmptyReferencePath,
                    FieldReference, RangeReference,
                    PrimitiveString, PrimitiveNumber,
                    StringReplaceRangeOperation, NumberReplaceRangeOperation,
                    PrimitiveStringToSyntaxLeaf, SimpleIoMap, KeyPress, KeyDown,
                    Modifiers, evaluate_operation, projection_read, set_selection!,
                    @reference

function _value_range_ref(start::Int, stop::Int)
    ConcreteReferencePath(FieldReference("value"),
        ConcreteReferencePath(RangeReference(start, stop), EmptyReferencePath()))
end

function _cursor_at(s)
    sel = getfield(s, :selection)[]
    @assert sel isa ConcreteReferencePath
    @assert sel.head isa FieldReference && sel.head.name == "value"
    inner = sel.tail
    @assert inner isa ConcreteReferencePath && inner.head isa RangeReference
    inner.head
end

function test_primitive()
@testset "PrimitiveReplaceRange" begin

# ── StringReplaceRangeOperation ─────────────────────────────────────────

@testset "string insert at cursor" begin
    doc = PrimitiveString("ab")
    op = StringReplaceRangeOperation(_value_range_ref(0, 0), "x")
    evaluate_operation((document=doc,), op)
    @test doc.value == "xab"
    range = _cursor_at(doc)
    @test range.start == 1 && range.stop == 1
end

@testset "string insert in middle" begin
    doc = PrimitiveString("ac")
    op = StringReplaceRangeOperation(_value_range_ref(1, 1), "b")
    evaluate_operation((document=doc,), op)
    @test doc.value == "abc"
    range = _cursor_at(doc)
    @test range.start == 2 && range.stop == 2
end

@testset "string backspace deletes char to left" begin
    doc = PrimitiveString("abc")
    # backspace at cursor position 2 deletes char at position 2 (1-based: 'b')
    op = StringReplaceRangeOperation(_value_range_ref(1, 2), "")
    evaluate_operation((document=doc,), op)
    @test doc.value == "ac"
    range = _cursor_at(doc)
    @test range.start == 1 && range.stop == 1
end

@testset "string delete removes char to right, cursor stays" begin
    doc = PrimitiveString("abc")
    # delete at cursor position 1 removes char at index 2 ('b'); cursor stays at 1
    op = StringReplaceRangeOperation(_value_range_ref(1, 2), "")
    evaluate_operation((document=doc,), op)
    @test doc.value == "ac"
    range = _cursor_at(doc)
    @test range.start == 1 && range.stop == 1
end

@testset "string range replace substitutes selection" begin
    doc = PrimitiveString("abcdef")
    op = StringReplaceRangeOperation(_value_range_ref(1, 4), "XY")
    evaluate_operation((document=doc,), op)
    @test doc.value == "aXYef"
    range = _cursor_at(doc)
    @test range.start == 3 && range.stop == 3
end

@testset "string range delete with empty replacement" begin
    doc = PrimitiveString("abcdef")
    op = StringReplaceRangeOperation(_value_range_ref(2, 5), "")
    evaluate_operation((document=doc,), op)
    @test doc.value == "abf"
    range = _cursor_at(doc)
    @test range.start == 2 && range.stop == 2
end

# ── NumberReplaceRangeOperation ─────────────────────────────────────────

@testset "number insert digit" begin
    doc = PrimitiveNumber(12)
    op = NumberReplaceRangeOperation(_value_range_ref(2, 2), "3")
    evaluate_operation((document=doc,), op)
    @test doc.value == 123.0
    range = _cursor_at(doc)
    @test range.start == 3 && range.stop == 3
end

@testset "number empty result becomes nothing" begin
    doc = PrimitiveNumber(9)
    # delete the only digit
    op = NumberReplaceRangeOperation(_value_range_ref(0, 1), "")
    evaluate_operation((document=doc,), op)
    @test doc.value === nothing
end

@testset "number non-parseable result becomes nothing" begin
    doc = PrimitiveNumber(1)
    op = NumberReplaceRangeOperation(_value_range_ref(1, 1), "x")
    evaluate_operation((document=doc,), op)
    @test doc.value === nothing
end

# ── projection_read producer ────────────────────────────────────────────

@testset "PrimitiveStringToSyntaxLeaf produces operation for printable key" begin
    s = PrimitiveString("ab")
    set_selection!(s, _value_range_ref(0, 0))
    p = PrimitiveStringToSyntaxLeaf()
    iomap = SimpleIoMap(p, s, nothing)
    evt = KeyPress('x')
    op = projection_read(p, iomap, evt)
    @test op isa StringReplaceRangeOperation
    @test op.replacement == "x"
    pref = op.reference
    @test pref isa ConcreteReferencePath
    @test pref.head isa FieldReference && pref.head.name == "value"
    @test pref.tail isa ConcreteReferencePath
    @test pref.tail.head isa RangeReference
    @test pref.tail.head.start == 0 && pref.tail.head.stop == 0
end

@testset "PrimitiveStringToSyntaxLeaf produces backspace op" begin
    s = PrimitiveString("ab")
    set_selection!(s, _value_range_ref(2, 2))
    p = PrimitiveStringToSyntaxLeaf()
    iomap = SimpleIoMap(p, s, nothing)
    evt = KeyDown(:backspace, Modifiers())
    op = projection_read(p, iomap, evt)
    @test op isa StringReplaceRangeOperation
    @test op.replacement == ""
    @test op.reference.tail.head.start == 1 && op.reference.tail.head.stop == 2
end

@testset "PrimitiveStringToSyntaxLeaf produces delete op" begin
    s = PrimitiveString("ab")
    set_selection!(s, _value_range_ref(0, 0))
    p = PrimitiveStringToSyntaxLeaf()
    iomap = SimpleIoMap(p, s, nothing)
    evt = KeyDown(:delete, Modifiers())
    op = projection_read(p, iomap, evt)
    @test op isa StringReplaceRangeOperation
    @test op.replacement == ""
    @test op.reference.tail.head.start == 0 && op.reference.tail.head.stop == 1
end

@testset "PrimitiveStringToSyntaxLeaf rejects ctrl-printable" begin
    s = PrimitiveString("ab")
    set_selection!(s, _value_range_ref(0, 0))
    p = PrimitiveStringToSyntaxLeaf()
    iomap = SimpleIoMap(p, s, nothing)
    evt = KeyPress('x', "x", Modifiers(true, false, false, false))
    @test projection_read(p, iomap, evt) === nothing
end

@testset "PrimitiveStringToSyntaxLeaf backspace at start returns nothing" begin
    s = PrimitiveString("ab")
    set_selection!(s, _value_range_ref(0, 0))
    p = PrimitiveStringToSyntaxLeaf()
    iomap = SimpleIoMap(p, s, nothing)
    evt = KeyDown(:backspace, Modifiers())
    @test projection_read(p, iomap, evt) === nothing
end

@testset "PrimitiveStringToSyntaxLeaf delete at end returns nothing" begin
    s = PrimitiveString("ab")
    set_selection!(s, _value_range_ref(2, 2))
    p = PrimitiveStringToSyntaxLeaf()
    iomap = SimpleIoMap(p, s, nothing)
    evt = KeyDown(:delete, Modifiers())
    @test projection_read(p, iomap, evt) === nothing
end

end # @testset
end # function
