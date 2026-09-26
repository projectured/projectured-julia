# A document that holds a string, as a container on the path of a caret does.
@document struct _PrimitiveEditHolder <: Document
    text::Any
end

function _value_range_ref(start::Int, stop::Int)
    ConcreteReference(FieldReferenceStep("value"),
        ConcreteReference(RangeReferenceStep(start, stop), EmptyReference()))
end

function _cursor_at(s)
    # Selections are canonical (carry TypeReferenceStep checkpoints); strip them to
    # match the plain `.value{k}` navigation skeleton this helper asserts on.
    sel = strip_reference_types(getfield(s, :selection)[])
    @assert sel isa ConcreteReference
    @assert sel.head isa FieldReferenceStep && sel.head.name == "value"
    inner = sel.tail
    @assert inner isa ConcreteReference && inner.head isa RangeReferenceStep
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

@testset "a string edit moves the caret in place" begin
    # Only the terminal step of the caret moves: the selection of the container
    # above the string is not written again, so what reads it — as a tabbed pane
    # reads its selection for its active tab — is not computed again, as it is
    # after a clear and a set.
    holder = _PrimitiveEditHolder(PrimitiveString("ab"))
    at(k) = ConcreteReference(FieldReferenceStep("text"), _value_range_ref(k, k))
    replace_selection!(holder, at(1))
    reader = Cell(@computation getfield(holder, :selection)[])
    reader[]
    evaluate_operation((document = holder,), ReplaceStringRangeOperation(at(1), "x"))
    @test holder.text.value == "axb"
    @test is_cell_up_to_date(reader)
    range = _cursor_at(holder.text)
    @test range.start == 2 && range.stop == 2
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

@testset "a character that can not be part of a number leaves the number" begin
    # The value, its text and the caret stay where they were.
    for replacement in ("x", ",", " ", "1x")
        doc = PrimitiveNumber(1)
        set_selection!(doc, _value_range_ref(1, 1))
        op = ReplaceNumberRangeOperation(_value_range_ref(1, 1), replacement)
        evaluate_operation((document=doc,), op)
        @test doc.value === 1
        range = _cursor_at(doc)
        @test range.start == 1 && range.stop == 1
    end
end

@testset "a string edit of a number leaves it for such a character too" begin
    # A text layer edits the field of a number with a string edit.
    doc = PrimitiveNumber(42)
    set_selection!(doc, _value_range_ref(2, 2))
    evaluate_operation((document=doc,), ReplaceStringRangeOperation(_value_range_ref(2, 2), "a"))
    @test doc.value === 42
    range = _cursor_at(doc)
    @test range.start == 2 && range.stop == 2
    evaluate_operation((document=doc,), ReplaceStringRangeOperation(_value_range_ref(2, 2), "5"))
    @test doc.value === 425
end

@testset "a prefix of a number that does not parse yet stays an edit" begin
    # `1e` and `-` are on the way to a number, so the key is not ignored. The
    # value is `nothing` until the text parses again.
    for (start, stop, replacement) in ((1, 1, "e"), (0, 1, "-"), (0, 1, "."), (1, 1, "+"))
        doc = PrimitiveNumber(1)
        op = ReplaceNumberRangeOperation(_value_range_ref(start, stop), replacement)
        evaluate_operation((document=doc,), op)
        @test doc.value === nothing
    end
    doc = PrimitiveNumber(1)
    evaluate_operation((document=doc,), ReplaceNumberRangeOperation(_value_range_ref(1, 1), "e3"))
    @test doc.value == 1000.0
end

@testset "a letter typed into a number through the text chain is ignored" begin
    chain = ChainingProjection(PrimitiveToText(), TextToGraphics(measure = FontFileMeasure()))
    doc = PrimitiveNumber(42)
    set_selection!(doc, _value_range_ref(2, 2))
    op = read_intent(chain, print_document(chain, doc), KeyPress('a'; time = 0.0))
    op === nothing || evaluate_operation((document=doc,), op)
    @test doc.value === 42
    @test _cursor_at(doc).start == 2
    op = read_intent(chain, print_document(chain, doc), KeyPress('5'; time = 0.0))
    evaluate_operation((document=doc,), op)
    @test doc.value === 425
end

@testset "a string edit of a cleared number keeps a number" begin
    # A cleared number holds `nothing`; its declared type says that a digit makes
    # a number of it, and a letter is ignored.
    doc = PrimitiveNumber(nothing)
    evaluate_operation((document=doc,), ReplaceStringRangeOperation(_value_range_ref(0, 0), "5"))
    @test doc.value === 5
    @test _cursor_at(doc).start == 1
    doc = PrimitiveNumber(nothing)
    evaluate_operation((document=doc,), ReplaceStringRangeOperation(_value_range_ref(0, 0), "a"))
    @test doc.value === nothing
    # Through the text chain.
    chain = ChainingProjection(PrimitiveToText(), TextToGraphics(measure = FontFileMeasure()))
    doc = PrimitiveNumber(nothing)
    set_selection!(doc, _value_range_ref(0, 0))
    evaluate_operation((document=doc,), read_intent(chain, print_document(chain, doc), KeyPress('5'; time = 0.0)))
    @test doc.value === 5
    # A cleared string, and a field that holds any value, take the text.
    doc = PrimitiveString(nothing)
    evaluate_operation((document=doc,), ReplaceStringRangeOperation(_value_range_ref(0, 0), "5"))
    @test doc.value == "5"
    doc = PrimitiveInsertion()
    evaluate_operation((document=doc,), ReplaceStringRangeOperation(_value_range_ref(0, 0), "5"))
    @test doc.value == "5"
end

# ── read_intent producer ────────────────────────────────────────────

@testset "PrimitiveStringToSyntaxLeaf produces operation for printable key" begin
    s = PrimitiveString("ab")
    set_selection!(s, _value_range_ref(0, 0))
    p = PrimitiveStringToSyntaxLeaf()
    iomap = SimpleIoMap(p, s, nothing)
    evt = KeyPress('x'; time = 0.0)
    op = read_intent(p, iomap, evt)
    @test op isa ReplaceStringRangeOperation
    @test op.replacement == "x"
    pref = op.reference
    @test pref isa ConcreteReference
    @test pref.head isa FieldReferenceStep && pref.head.name == "value"
    @test pref.tail isa ConcreteReference
    @test pref.tail.head isa RangeReferenceStep
    @test pref.tail.head.start == 0 && pref.tail.head.stop == 0
end

@testset "PrimitiveStringToSyntaxLeaf produces backspace op" begin
    s = PrimitiveString("ab")
    set_selection!(s, _value_range_ref(2, 2))
    p = PrimitiveStringToSyntaxLeaf()
    iomap = SimpleIoMap(p, s, nothing)
    evt = KeyDown(:backspace, ModifierKeys(); time = 0.0)
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
    evt = KeyDown(:delete, ModifierKeys(); time = 0.0)
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
    evt = KeyPress('x', "x", ModifierKeys(true, false, false, false); time = 0.0)
    op = read_intent(p, iomap, evt)
    @test op isa ReplaceStringRangeOperation
    @test op.replacement == "x"
end

@testset "PrimitiveStringToSyntaxLeaf backspace at start returns nothing" begin
    s = PrimitiveString("ab")
    set_selection!(s, _value_range_ref(0, 0))
    p = PrimitiveStringToSyntaxLeaf()
    iomap = SimpleIoMap(p, s, nothing)
    evt = KeyDown(:backspace, ModifierKeys(); time = 0.0)
    @test read_intent(p, iomap, evt) === nothing
end

@testset "PrimitiveStringToSyntaxLeaf delete at end returns nothing" begin
    s = PrimitiveString("ab")
    set_selection!(s, _value_range_ref(2, 2))
    p = PrimitiveStringToSyntaxLeaf()
    iomap = SimpleIoMap(p, s, nothing)
    evt = KeyDown(:delete, ModifierKeys(); time = 0.0)
    @test read_intent(p, iomap, evt) === nothing
end

end # @testset
end # function
