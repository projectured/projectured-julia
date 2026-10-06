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

# The part under the pointer reaches the syntax node of each array through the
# forward map of the rule template: the pointer on the `2` of `[1, [2, 3]]`.
nested = JsonArray([JsonNumber(1), JsonArray([JsonNumber(2), JsonNumber(3)])])
nested_syntax = print_document(j2s, nested).output
_step(name, index, tail) =
    ConcreteReference(FieldReferenceStep(name), ConcreteReference(ElementReferenceStep(index), tail))
replace_mouse_target!(nested, _step("elements", 2, _step("elements", 1, EmptyReference())))
outer_target = strip_reference_types(getfield(nested_syntax, :mouse_target)[])
inner_target = strip_reference_types(getfield(nested_syntax.children[2], :mouse_target)[])
@test get_reference_head(outer_target) == FieldReferenceStep("children")
@test get_reference_head(inner_target) == FieldReferenceStep("children")
@test getfield(nested_syntax.children[1], :mouse_target)[] === nothing
replace_mouse_target!(nested, nothing)
@test getfield(nested_syntax.children[2], :mouse_target)[] === nothing

# object (order-independent check)
jo = JsonObject("a" => JsonNumber(1))
rendered_obj = render(print_document(j2s, jo).output)
@test occursin("\"a\": 1", rendered_obj)

# incremental: value change propagates through syntax tree
jdoc = JsonObject("x" => JsonNumber(10))
jtree = print_document(j2s, jdoc).output
jout = Cell(@computation render(jtree))
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

# A type-to-replace gesture now returns the folded `make_replace_document_operation`
# compound: CompoundOperation([ReplaceReferencedValueOperation(writes the new doc),
# ReplaceSelection]). `_written` pulls out the document that the first member writes.
_written(op) = op.operations[1].value

@testset "type-to-replace builds the right document" begin
    for (ch, T) in (('n', JsonNull), ('f', JsonBool), ('t', JsonBool),
                    ('"', JsonString), ('[', JsonArray), (':', JsonObjectEntry),
                    ('{', JsonObject))
        op = read_key(JsonInsertion(), whole, KeyPress(ch; time = 0.0))
        @test op isa CompoundOperation
        @test _written(op) isa T
    end
    # Booleans carry the literal the key names.
    @test _written(read_key(JsonInsertion(), whole, KeyPress('t'; time = 0.0))).value === true
    @test _written(read_key(JsonInsertion(), whole, KeyPress('f'; time = 0.0))).value === false
    # A digit on a non-number builds a number whose cursor sits after the digit.
    op = read_key(JsonInsertion(), whole, KeyPress('5'; time = 0.0))
    @test op isa CompoundOperation
    @test _written(op) isa JsonNumber
    @test _written(op).value == 5
end

@testset "replacing the whole root swaps editor.document" begin
    doc = JsonInsertion()
    op = read_key(doc, whole, KeyPress('['; time = 0.0))
    ed = _JsonReaderEditor(doc, nothing)
    evaluate_operation(ed, op)
    @test ed.document isa JsonArray
    @test ed.iomap === nothing            # forced reprint on a root swap
    @test length(ed.document.elements) == 1
    @test ed.document[1] isa JsonInsertion
end

@testset "replacing a nested element writes the slot in place" begin
    arr = JsonArray([JsonInsertion()])
    op = read_key(arr, @reference(arr, elements[1]), KeyPress('5'; time = 0.0))
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
    @test read_key(num, @reference(num, value{1}), KeyPress('5'; time = 0.0)) isa CompoundOperation

    chain = ChainingProjection(RecursiveProjection(JsonToSyntax()),
                               RecursiveProjection(SyntaxToText()),
                               TextToGraphics(measure = FontFileMeasure()))
    n = JsonNumber(42)
    set_selection!(n, @reference(n, value{1}))
    @test read_intent(chain, print_document(chain, n), KeyPress('5'; time = 0.0)) isa ReplaceNumberRangeOperation
end

@testset "a letter typed into a number is ignored" begin
    chain = ChainingProjection(RecursiveProjection(JsonToSyntax()),
                               RecursiveProjection(SyntaxToText()),
                               TextToGraphics(measure = FontFileMeasure()))
    # Type `key` at the caret `caret`, and evaluate what the chain reads.
    function type_key!(document, caret, key)
        set_selection!(document, caret)
        op = read_intent(chain, print_document(chain, document), KeyPress(key; time = 0.0))
        op === nothing || evaluate_operation(_JsonReaderEditor(document, nothing), op)
        op
    end
    # The number is the document: the reader declines the key.
    for key in ('a', ',', ' ', 'x')
        n = JsonNumber(42)
        @test type_key!(n, @reference(n, value{2}), key) === nothing
        @test n.value === 42
        @test render(print_document(RecursiveProjection(JsonToSyntax()), n).output) == "42"
    end
    # A key that can be part of a number, and makes a text that no number shows,
    # replaces the number with an insertion of that text, so the text stays.
    n = JsonNumber(42)
    @test type_key!(n, @reference(n, value{2}), 'e') isa CompoundOperation
    typed = JsonArray([JsonNumber(42)])
    type_key!(typed, @reference(typed, elements[1].value{2}), '.')
    @test typed[1] isa JsonInsertion
    @test typed[1].value == "42."
    # The key that makes a text that a number shows exactly turns it into the number.
    type_key!(typed, @reference(typed, elements[1].value{3}), '5')
    @test typed[1] isa JsonNumber
    @test typed[1].value === 42.5
    @test length(typed.elements) == 1
    # The number is in an array: the edit keeps the value, and the array its length.
    arr = JsonArray([JsonNumber(42)])
    type_key!(arr, @reference(arr, elements[1].value{2}), 'a')
    @test arr[1].value === 42
    @test length(arr.elements) == 1
    type_key!(arr, @reference(arr, elements[1].value{2}), '5')
    @test arr[1].value === 425
    # A bool takes no text edit: a key inside it makes no edit, and the key of a
    # gesture of the domain still reaches the gesture.
    flag = JsonArray([JsonBool(true)])
    type_key!(flag, @reference(flag, elements[1].value{2}), 'x')
    @test flag[1] isa JsonBool
    @test flag[1].value === true
    type_key!(flag, @reference(flag, elements[1].value{2}), 'f')
    @test flag[1] isa JsonBool
    @test flag[1].value === false
end

@testset "a digit typed into a cleared number in a container makes a number" begin
    chain = ChainingProjection(RecursiveProjection(JsonToSyntax()),
                               RecursiveProjection(SyntaxToText()),
                               TextToGraphics(measure = FontFileMeasure()))
    function type_key!(document, caret, key)
        set_selection!(document, caret)
        op = read_intent(chain, print_document(chain, document), KeyPress(key; time = 0.0))
        op === nothing || evaluate_operation(_JsonReaderEditor(document, nothing), op)
        op
    end
    # The number leaf retypes the edit also when a container holds it.
    arr = JsonArray([JsonNumber(nothing)])
    @test type_key!(arr, @reference(arr, elements[1].value{0}), '5') isa ReplaceNumberRangeOperation
    @test arr[1].value === 5
    @test type_key!(arr, @reference(arr, elements[1].value{1}), 'a') === nothing
    @test arr[1].value === 5
    obj = JsonObject("k" => JsonNumber(nothing))
    @test type_key!(obj, @reference(obj, entries[1].value.value{0}), '7') isa ReplaceNumberRangeOperation
    @test obj.entries[1].value.value === 7
    # A string in a container stays a string edit.
    strings = JsonArray([JsonString("ab")])
    @test type_key!(strings, @reference(strings, elements[1].value{2}), '5') isa ReplaceStringRangeOperation
    @test strings[1].value == "ab5"
end

@testset "array insert appends an insertion and selects it" begin
    arr = JsonArray([JsonNumber(1)])
    op = read_key(arr, whole, KeyPress(','; time = 0.0))
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
    op = read_key(obj, whole, KeyPress(','; time = 0.0))
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
    op = read_key(obj, @reference(obj, entries[1].key{0}), KeyDown(:tab, ModifierKeys(); time = 0.0))
    @test op isa ReplaceSelectionOperation
    # The Tab op selects the entry's value whole, carrying its folded types. The
    # terminal checkpoint is the value's *concrete* type, not the declared `Document`
    # field type — that is the canonical annotated form, and what `set_selection!`
    # stores for this path either way.
    @test is_reference_equal(op.path,
          @reference ::JsonObject.entries::CellVector[1]::JsonObjectEntry.value::JsonNumber)
    # Tab outside a key does nothing.
    @test read_key(obj, whole, KeyDown(:tab, ModifierKeys(); time = 0.0)) === nothing
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
# reified JSON tables, and compute_applicable_gesture_bindings reflects the current
# selection — the data-driven dual of what the reader could fire.
# How a collected intent renders its key; empty when the rule has no gesture.
_gesture_of(intent) = intent.gesture === nothing ? "" : describe_gesture_pattern(intent.gesture)

function test_json_gesture_collection()
@testset "JsonToSyntax gesture collection" begin

    j2s = RecursiveProjection(JsonToSyntax())
    # Ask the reader what is available, the way the help window and the palette do.
    # `all` is every row offered; `app` is the subset that could fire right now,
    # which is exactly the subset carrying a built operation.
    collect_for(doc, sel) = begin
        set_selection!(doc, sel)
        iomap = print_document(j2s, doc)
        answer = read_intent(j2s, nothing, Intent(CollectIntents()), iomap)
        intents = (answer isa Intent ? answer.operation : answer).intents
        (intents, [i for i in intents if i.operation !== nothing])
    end

    @testset "root scalar exposes the type-to-replace set" begin
        all, app = collect_for(JsonNull(), EmptyReference())
        @test length(all) == 8                       # n f t " [ : { digit
        # Seven, not eight: "Replace with a number" needs the digit the user typed,
        # and no operation can be built without the keystroke that carries it.
        @test length(app) == 7
        @test "n" in [_gesture_of(b) for b in all]
        # No selection greys the whole set.
        _, none = collect_for(JsonNull(), nothing)
        @test isempty(none)
    end

    @testset "array adds comma-insert; element selection stays replaceable" begin
        whole_all, whole_app = collect_for(JsonArray([JsonNumber(1)]), EmptyReference())
        @test length(whole_all) == 9                  # 8 inherited + , insert
        @test length(whole_app) == 8                  # minus the digit rule
        @test "," in [_gesture_of(b) for b in whole_all]
        # Selecting an element keeps the type-to-replace set applicable (it
        # targets the element) plus the always-on comma.
        arr2 = JsonArray([JsonNumber(1)])
        _, elem_app = collect_for(arr2, @reference(arr2, elements[1]))
        @test length(elem_app) == 8
    end

    @testset "whole object entry greys what cannot fire, keeps the comma" begin
        obj2 = JsonObject("a" => JsonNumber(1))
        all, app = collect_for(obj2, @reference(obj2, entries[1]))
        # 8 inherited + , insert + Tab + the two commands (value-to-key, sort by
        # key), which have no gesture and are reached by name from the command
        # palette.
        @test length(all) == 12
        # A whole entry is a key/value wrapper, not a replaceable value, so the
        # type-to-replace set builds no operation. What remains is the always-on
        # comma and the sort command (no keystroke, so an empty gesture column).
        #
        # Tab and "Move from value to key" are absent, and that is the point of
        # asking the reader: both call `move_to_field`, which declines when the
        # cursor is not in the field it moves from. The old `applicable`-only answer
        # listed them as available when pressing them would have done nothing.
        descs = sort([_gesture_of(b) for b in app])
        @test descs == ["", ","]
    end

end # @testset "JsonToSyntax gesture collection"
end # test_json_gesture_collection
