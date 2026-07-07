
function _value_range_ref(start::Int, stop::Int)
    ConcreteReferencePath(FieldReference("value"),
        ConcreteReferencePath(RangeReference(start, stop), EmptyReferencePath()))
end

function _cursor_at(s)
    # Selections are canonical (carry TypeReference checkpoints); strip them to
    # match the plain `.value{k}` navigation skeleton this helper asserts on.
    sel = strip_reference_types(getfield(s, :selection)[])
    @assert sel isa ConcreteReferencePath
    @assert sel.head isa FieldReference && sel.head.name == "value"
    inner = sel.tail
    @assert inner isa ConcreteReferencePath && inner.head isa RangeReference
    inner.head
end

function test_primitive()
@testset "PrimitiveReplaceRange" begin

# ── ReplaceStringRangeOperation ─────────────────────────────────────────

@testset "string insert at cursor" begin
    doc = PrimitiveString("ab")
    op = ReplaceStringRangeOperation(_value_range_ref(0, 0), "x")
    evaluate_operation((document=doc,), op)
    @test doc.value == "xab"
    range = _cursor_at(doc)
    @test range.start == 1 && range.stop == 1
end

@testset "string insert in middle" begin
    doc = PrimitiveString("ac")
    op = ReplaceStringRangeOperation(_value_range_ref(1, 1), "b")
    evaluate_operation((document=doc,), op)
    @test doc.value == "abc"
    range = _cursor_at(doc)
    @test range.start == 2 && range.stop == 2
end

@testset "string backspace deletes char to left" begin
    doc = PrimitiveString("abc")
    # backspace at cursor position 2 deletes char at position 2 (1-based: 'b')
    op = ReplaceStringRangeOperation(_value_range_ref(1, 2), "")
    evaluate_operation((document=doc,), op)
    @test doc.value == "ac"
    range = _cursor_at(doc)
    @test range.start == 1 && range.stop == 1
end

@testset "string delete removes char to right, cursor stays" begin
    doc = PrimitiveString("abc")
    # delete at cursor position 1 removes char at index 2 ('b'); cursor stays at 1
    op = ReplaceStringRangeOperation(_value_range_ref(1, 2), "")
    evaluate_operation((document=doc,), op)
    @test doc.value == "ac"
    range = _cursor_at(doc)
    @test range.start == 1 && range.stop == 1
end

@testset "string range replace substitutes selection" begin
    doc = PrimitiveString("abcdef")
    op = ReplaceStringRangeOperation(_value_range_ref(1, 4), "XY")
    evaluate_operation((document=doc,), op)
    @test doc.value == "aXYef"
    range = _cursor_at(doc)
    @test range.start == 3 && range.stop == 3
end

@testset "string range delete with empty replacement" begin
    doc = PrimitiveString("abcdef")
    op = ReplaceStringRangeOperation(_value_range_ref(2, 5), "")
    evaluate_operation((document=doc,), op)
    @test doc.value == "abf"
    range = _cursor_at(doc)
    @test range.start == 2 && range.stop == 2
end

# ── ReplaceNumberRangeOperation ─────────────────────────────────────────

@testset "number insert digit" begin
    doc = PrimitiveNumber(12)
    op = ReplaceNumberRangeOperation(_value_range_ref(2, 2), "3")
    evaluate_operation((document=doc,), op)
    @test doc.value == 123.0
    range = _cursor_at(doc)
    @test range.start == 3 && range.stop == 3
end

@testset "number empty result becomes nothing" begin
    doc = PrimitiveNumber(9)
    # delete the only digit
    op = ReplaceNumberRangeOperation(_value_range_ref(0, 1), "")
    evaluate_operation((document=doc,), op)
    @test doc.value === nothing
end

@testset "number non-parseable result becomes nothing" begin
    doc = PrimitiveNumber(1)
    op = ReplaceNumberRangeOperation(_value_range_ref(1, 1), "x")
    evaluate_operation((document=doc,), op)
    @test doc.value === nothing
end

# ── read_intent producer ────────────────────────────────────────────

@testset "PrimitiveStringToSyntaxLeaf produces operation for printable key" begin
    s = PrimitiveString("ab")
    set_selection!(s, _value_range_ref(0, 0))
    p = PrimitiveStringToSyntaxLeaf()
    iomap = SimpleIoMap(p, s, nothing)
    evt = KeyPress('x')
    op = read_intent(p, iomap, evt)
    @test op isa ReplaceStringRangeOperation
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
    op = read_intent(p, iomap, evt)
    @test op isa ReplaceStringRangeOperation
    @test op.replacement == ""
    @test op.reference.tail.head.start == 1 && op.reference.tail.head.stop == 2
end

@testset "PrimitiveStringToSyntaxLeaf produces delete op" begin
    s = PrimitiveString("ab")
    set_selection!(s, _value_range_ref(0, 0))
    p = PrimitiveStringToSyntaxLeaf()
    iomap = SimpleIoMap(p, s, nothing)
    evt = KeyDown(:delete, Modifiers())
    op = read_intent(p, iomap, evt)
    @test op isa ReplaceStringRangeOperation
    @test op.replacement == ""
    @test op.reference.tail.head.start == 0 && op.reference.tail.head.stop == 1
end

@testset "PrimitiveStringToSyntaxLeaf inserts a printable (KeyPress ignores modifiers)" begin
    # String editing is now reified as document-level `@gestures PrimitiveString`,
    # reached through the generic `read_gesture` fallback. Per the reification
    # convention (shared with Text/JSON), KeyPress patterns ignore modifiers — a real
    # Ctrl-combo arrives as a KeyDown, never a KeyPress — so a printable KeyPress
    # inserts regardless of a stray ctrl flag; the old per-projection defensive
    # `ctrl` reject is intentionally gone.
    s = PrimitiveString("ab")
    set_selection!(s, _value_range_ref(0, 0))
    p = PrimitiveStringToSyntaxLeaf()
    iomap = SimpleIoMap(p, s, nothing)
    evt = KeyPress('x', "x", Modifiers(true, false, false, false))
    op = read_intent(p, iomap, evt)
    @test op isa ReplaceStringRangeOperation
    @test op.replacement == "x"
end

@testset "PrimitiveStringToSyntaxLeaf backspace at start returns nothing" begin
    s = PrimitiveString("ab")
    set_selection!(s, _value_range_ref(0, 0))
    p = PrimitiveStringToSyntaxLeaf()
    iomap = SimpleIoMap(p, s, nothing)
    evt = KeyDown(:backspace, Modifiers())
    @test read_intent(p, iomap, evt) === nothing
end

@testset "PrimitiveStringToSyntaxLeaf delete at end returns nothing" begin
    s = PrimitiveString("ab")
    set_selection!(s, _value_range_ref(2, 2))
    p = PrimitiveStringToSyntaxLeaf()
    iomap = SimpleIoMap(p, s, nothing)
    evt = KeyDown(:delete, Modifiers())
    @test read_intent(p, iomap, evt) === nothing
end

end # @testset
end # function
