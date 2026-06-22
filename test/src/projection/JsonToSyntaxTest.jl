function test_json_to_syntax()
@testset "JsonToSyntax" begin

j2s = RecursiveProjection(JsonToSyntax())
@test render(projection_print(j2s, JsonNull()).output) == "null"
@test render(projection_print(j2s, JsonBool(true)).output) == "true"
@test render(projection_print(j2s, JsonBool(false)).output) == "false"
@test render(projection_print(j2s, JsonNumber(42)).output) == "42"
@test render(projection_print(j2s, JsonString("hi")).output) == "\"hi\""
@test render(projection_print(j2s, JsonString("a\"b")).output) == "\"a\\\"b\""

# array
ja = JsonArray([JsonNumber(1), JsonNumber(2)])
@test render(projection_print(j2s, ja).output) == "[1, 2]"

# object (order-independent check)
jo = JsonObject("a" => 1)
rendered_obj = render(projection_print(j2s, jo).output)
@test occursin("\"a\": 1", rendered_obj)

# incremental: value change propagates through syntax tree
jdoc = JsonObject("x" => 10)
jtree = projection_print(j2s, jdoc).output
jout = Cell(() -> render(jtree))
@test occursin("10", jout[])

jdoc["x"][] = 99
@test !isuptodate(jout)
@test occursin("99", jout[])

# structural change
push!(JsonArray([JsonNumber(1)]), JsonNumber(2))

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
whole = EmptyReferencePath()
selof(x) = getfield(x, :selection)[]

read_key(doc, sel, evt) = begin
    set_selection!(doc, sel)
    iomap = projection_print(j2s, doc)
    projection_read(j2s, iomap, evt)
end

@testset "type-to-replace builds the right document" begin
    for (ch, T) in (('n', JsonNull), ('f', JsonBool), ('t', JsonBool),
                    ('"', JsonString), ('[', JsonArray), (':', JsonObjectEntry),
                    ('{', JsonObject))
        op = read_key(JsonInsertion(), whole, KeyPress(ch))
        @test op isa ReplaceDocumentOperation
        @test op.document isa T
    end
    # Booleans carry the literal the key names.
    @test read_key(JsonInsertion(), whole, KeyPress('t')).document[] === true
    @test read_key(JsonInsertion(), whole, KeyPress('f')).document[] === false
    # A digit on a non-number builds a number whose cursor sits after the digit.
    op = read_key(JsonInsertion(), whole, KeyPress('5'))
    @test op isa ReplaceDocumentOperation
    @test op.document isa JsonNumber
    @test op.document[] == 5
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
    op = read_key(arr, (@reference elements[1]), KeyPress('5'))
    @test op isa ReplaceDocumentOperation
    @test op.document isa JsonNumber
    ed = _JsonReaderEditor(arr, nothing)
    evaluate_operation(ed, op)
    @test ed.document === arr              # root untouched: incremental write
    @test arr[1] isa JsonNumber
    @test arr[1][] == 5
    # Cursor landed inside the new number's text.
    @test selof(arr[1]) isa ConcreteReferencePath
end

@testset "digit gating: a character cursor in a number declines" begin
    num = JsonNumber(42)
    @test read_key(num, (@reference value{1}), KeyPress('5')) === nothing
end

@testset "array insert appends an insertion and selects it" begin
    arr = JsonArray([JsonNumber(1)])
    op = read_key(arr, whole, KeyPress(','))
    @test op isa CollectionInsertOperation
    @test op.index == 1
    ed = _JsonReaderEditor(arr, nothing)
    evaluate_operation(ed, op)
    @test length(arr.elements) == 2
    @test arr[2] isa JsonInsertion
    @test selof(arr[2]) isa EmptyReferencePath   # new element wholly selected
end

@testset "object insert appends an entry and selects its key" begin
    obj = JsonObject("a" => 1)
    op = read_key(obj, whole, KeyPress(','))
    @test op isa CollectionInsertOperation
    ed = _JsonReaderEditor(obj, nothing)
    evaluate_operation(ed, op)
    @test length(obj.entries) == 2
    new_entry = entries(obj)[2]
    @test new_entry isa JsonObjectEntry
    @test new_entry.key == ""
    @test selof(new_entry) isa ConcreteReferencePath   # cursor in the key
end

@testset "Tab moves from an entry key to its value" begin
    obj = JsonObject("a" => 1)
    op = read_key(obj, (@reference entries[1].key{0}), KeyDown(:tab, Modifiers()))
    @test op isa ReplaceSelectionOperation
    @test reference_equal(op.path, @reference entries[1].value)
    # Tab outside a key does nothing.
    @test read_key(obj, whole, KeyDown(:tab, Modifiers())) === nothing
end

@testset "empty values render a muted placeholder hint" begin
    rp = RecursiveProjection(JsonToSyntax())
    rendr(d) = render(projection_print(rp, d).output)
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
