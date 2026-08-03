function test_json_to_syntax()
@testset "JsonToSyntax" begin

j2s = RecursiveProjection(JsonToSyntax())
@test render(print_document(j2s, JsonNull()).output) == "null"
@test render(print_document(j2s, JsonBool(true)).output) == "true"
@test render(print_document(j2s, JsonBool(false)).output) == "false"
@test render(print_document(j2s, JsonNumber(42)).output) == "42"
@test render(print_document(j2s, JsonString("hi")).output) == "\"hi\""
@test render(print_document(j2s, JsonString("a\"b")).output) == "\"a\\\"b\""

# array
ja = JsonArray([JsonNumber(1), JsonNumber(2)])
@test render(print_document(j2s, ja).output) == "[1, 2]"

# object (order-independent check)
jo = JsonObject("a" => JsonNumber(1))
rendered_obj = render(print_document(j2s, jo).output)
@test occursin("\"a\": 1", rendered_obj)

# incremental: value change propagates through syntax tree
jdoc = JsonObject("x" => JsonNumber(10))
jtree = print_document(j2s, jdoc).output
jout = ComputedCell(() -> render(jtree))
@test occursin("10", jout[])

jdoc["x"].value = 99
@test !is_cell_up_to_date(jout)
@test occursin("99", jout[])

# structural change
push!(JsonArray([JsonNumber(1)]).elements, JsonNumber(2))

end # @testset "JsonToSyntax"
end # test_json_to_syntax

# A minimal stand-in for the Editor that the operation evaluators mutate.
mutable struct _JsonReaderEditor
    document::Any
    iomap::Any
end

# Drive the JSON reader command set (the Lisp `json/read-command` plus the
# array/object insert and Tab readers). Each JSON projection must work as the
# whole document on its own, so the cursor is placed with a whole-element
# selection and a raw key gesture is fed straight to the root JSON reader.
function test_json_to_syntax_reader()
@testset "JsonToSyntax reader commands" begin

j2s = RecursiveProjection(JsonToSyntax())
whole = EmptyReference()
selof(x) = getfield(x, :selection)[]

read_key(doc, sel, evt) = begin
    set_selection!(doc, sel)
    iomap = print_document(j2s, doc)
    read_intent(j2s, iomap, evt)
end

# A type-to-replace gesture now returns the folded `replace_document` compound:
# CompoundOperation([ReplaceReferencedValueOperation(writes the new doc), ReplaceSelection]).
# `_written` pulls out the document that the first member writes.
_written(op) = op.operations[1].value

@testset "type-to-replace builds the right document" begin
    for (ch, T) in (('n', JsonNull), ('f', JsonBool), ('t', JsonBool),
                    ('"', JsonString), ('[', JsonArray), (':', JsonObjectEntry),
                    ('{', JsonObject))
        op = read_key(JsonInsertion(), whole, KeyPress(ch))
        @test op isa CompoundOperation
        @test _written(op) isa T
    end
    # Booleans carry the literal the key names.
    @test _written(read_key(JsonInsertion(), whole, KeyPress('t'))).value === true
    @test _written(read_key(JsonInsertion(), whole, KeyPress('f'))).value === false
    # A digit on a non-number builds a number whose cursor sits after the digit.
    op = read_key(JsonInsertion(), whole, KeyPress('5'))
    @test op isa CompoundOperation
    @test _written(op) isa JsonNumber
    @test _written(op).value == 5
end

@testset "replacing the whole root swaps editor.document" begin
    doc = JsonInsertion()
    op = read_key(doc, whole, KeyPress('['))
    ed = _JsonReaderEditor(doc, nothing)
    evaluate_operation(ed, op)
    @test ed.document isa JsonArray
    @test ed.iomap === nothing            # forced reprint on a root swap
    @test length(ed.document.elements) == 1
    @test ed.document[1] isa JsonInsertion
end

@testset "replacing a nested element writes the slot in place" begin
    arr = JsonArray([JsonInsertion()])
    op = read_key(arr, @reference(arr, elements[1]), KeyPress('5'))
    @test op isa CompoundOperation
    @test _written(op) isa JsonNumber
    ed = _JsonReaderEditor(arr, nothing)
    evaluate_operation(ed, op)
    @test ed.document === arr              # root untouched: incremental write
    @test arr[1] isa JsonNumber
    @test arr[1].value == 5
    # Cursor landed inside the new number's text.
    @test selof(arr[1]) isa ConcreteReference
end

@testset "digit gating: the chain gates the digit, not the domain" begin
    # On its own the domain replaces the number: a gesture that reconstructs what the
    # text layer *would have* done in order to decline is exactly what reading
    # last-to-first removes. The gating is real, but it belongs to the chain — the text
    # layer claims a digit first, so the domain never sees one mid-number.
    num = JsonNumber(42)
    @test read_key(num, @reference(num, value{1}), KeyPress('5')) isa CompoundOperation

    chain = ChainingProjection(RecursiveProjection(JsonToSyntax()),
                               RecursiveProjection(SyntaxToText()),
                               TextToGraphics(measure = truetype_measure_text))
    n = JsonNumber(42)
    set_selection!(n, @reference(n, value{1}))
    @test read_intent(chain, print_document(chain, n), KeyPress('5')) isa ReplaceNumberRangeOperation
end

@testset "array insert appends an insertion and selects it" begin
    arr = JsonArray([JsonNumber(1)])
    op = read_key(arr, whole, KeyPress(','))
    @test op isa CompoundOperation                       # splice + select-new
    @test op.operations[1] isa ReplaceReferencedValueOperation
    ed = _JsonReaderEditor(arr, nothing)
    evaluate_operation(ed, op)
    @test length(arr.elements) == 2
    @test arr[2] isa JsonInsertion
    @test selof(arr[2]) isa EmptyReference   # new element wholly selected
end

@testset "object insert appends an entry and selects its key" begin
    obj = JsonObject("a" => JsonNumber(1))
    op = read_key(obj, whole, KeyPress(','))
    @test op isa CompoundOperation
    ed = _JsonReaderEditor(obj, nothing)
    evaluate_operation(ed, op)
    @test length(obj.entries) == 2
    new_entry = obj.entries[2]
    @test new_entry isa JsonObjectEntry
    @test new_entry.key == ""
    @test selof(new_entry) isa ConcreteReference   # cursor in the key
end

@testset "Tab moves from an entry key to its value" begin
    obj = JsonObject("a" => JsonNumber(1))
    op = read_key(obj, @reference(obj, entries[1].key{0}), KeyDown(:tab, ModifierKeys()))
    @test op isa ReplaceSelectionOperation
    # The Tab op selects the entry's value whole, carrying its folded types. The
    # terminal checkpoint is the value's *concrete* type, not the declared `Document`
    # field type — that is the canonical annotated form, and what `set_selection!`
    # stores for this path either way.
    @test is_reference_equal(op.path,
          @reference ::JsonObject.entries::CellVector[1]::JsonObjectEntry.value::JsonNumber)
    # Tab outside a key does nothing.
    @test read_key(obj, whole, KeyDown(:tab, ModifierKeys())) === nothing
end

@testset "empty values render a muted placeholder hint" begin
    rp = RecursiveProjection(JsonToSyntax())
    rendr(d) = render(print_document(rp, d).output)
    @test rendr(JsonString("")) == "\"enter json string\""
    emptynum = JsonNumber(0); emptynum.value = nothing
    @test rendr(emptynum) == "enter json number"
    @test occursin("enter key", rendr(JsonObject("" => JsonInsertion())))
    # The hint is just content — a real value replaces it entirely.
    @test rendr(JsonString("hi")) == "\"hi\""
    @test rendr(JsonNumber(7)) == "7"
end

end # @testset "JsonToSyntax reader commands"
end # test_json_to_syntax_reader

# The contextual collector: collect_gesture_bindings walks the projection chain to the
# reified JSON tables, and get_applicable_gesture_bindings reflects the current selection —
# the data-driven dual of what the reader could fire.
function test_json_gesture_collection()
@testset "JsonToSyntax gesture collection" begin

    j2s = RecursiveProjection(JsonToSyntax())
    collect_for(doc, sel) = begin
        set_selection!(doc, sel)
        iomap = print_document(j2s, doc)
        bindings = collect_gesture_bindings(j2s, nothing, iomap)
        (bindings, get_applicable_gesture_bindings(doc, bindings))
    end

    @testset "root scalar exposes the type-to-replace set" begin
        all, app = collect_for(JsonNull(), EmptyReference())
        @test length(all) == 8                       # n f t " [ : { digit
        @test length(app) == 8                        # whole value → all replaceable
        @test "n" in [describe_event_pattern(b.pattern) for b in all]
        # No selection greys the whole set.
        _, none = collect_for(JsonNull(), nothing)
        @test isempty(none)
    end

    @testset "array adds comma-insert; element selection stays replaceable" begin
        whole_all, whole_app = collect_for(JsonArray([JsonNumber(1)]), EmptyReference())
        @test length(whole_all) == 9                  # 8 inherited + , insert
        @test length(whole_app) == 9
        @test "," in [describe_event_pattern(b.pattern) for b in whole_all]
        # Selecting an element keeps the type-to-replace set applicable (it
        # targets the element) plus the always-on comma.
        arr2 = JsonArray([JsonNumber(1)])
        _, elem_app = collect_for(arr2, @reference(arr2, elements[1]))
        @test length(elem_app) == 9
    end

    @testset "whole object entry greys type-to-replace, keeps comma + Tab" begin
        obj2 = JsonObject("a" => JsonNumber(1))
        all, app = collect_for(obj2, @reference(obj2, entries[1]))
        @test length(all) == 10                       # 8 inherited + , insert + Tab
        # A whole entry is a key/value wrapper, not a replaceable value — the
        # type-to-replace set is greyed (its `applicable` precondition fails on a
        # JsonObjectEntry target); only the two always-on object gestures remain.
        descs = sort([describe_event_pattern(b.pattern) for b in app])
        @test descs == [",", "Tab"]
    end

end # @testset "JsonToSyntax gesture collection"
end # test_json_gesture_collection
