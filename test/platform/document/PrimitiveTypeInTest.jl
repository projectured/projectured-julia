# The type-in of a number: a key whose text the number can not show replaces the
# number with a `PrimitiveInsertion` of that text, and the type-in becomes a number
# again at the key whose text a number shows exactly, and at Enter. The tests type
# through a real editor on the natural renderer, which prints a number with
# `PrimitiveToSyntax`.

# An editor on `document` with no window and no feature of a window, after its
# first frame.
function _ti_editor(document; keywords...)
    backend = HeadlessBackend()
    editor = build_editor(document, NaturalToGraphics(measure = FontFileMeasure());
                          backend, devices = ProjecturedKernel.DeviceModule.Device[Keyboard(), Mouse(), Display()],
                          window = false, appearance = false, settings = false, tabs = false,
                          focus_cycling = false, keywords...)
    run_frame!(editor)
    (editor, backend)
end

_ti_press!(editor, backend, events...) =
    (foreach(event -> push_event!(backend, event), events); run_frame!(editor))

_ti_key(character) = KeyPress(character; time = 0.0)
_ti_down(key; ctrl = false) = KeyDown(key, ModifierKeys(ctrl = ctrl); time = 0.0)

# The caret at `k` in the value of the first element of a list, after `prefix`.
_ti_caret(k; prefix = ()) =
    Reference(prefix..., RangeReferenceStep(0, 1), FieldReferenceStep("value"), RangeReferenceStep(k, k))

_ti_selection(editor) = repr(strip_reference_types(get_selection(editor.document)))

# A list of two numbers, with the caret at `k` in the first, in an editor.
function _ti_list_editor(k; keywords...)
    list = CellVector(Any[PrimitiveNumber(12), PrimitiveNumber(7)])
    editor, backend = _ti_editor(list; keywords...)
    root = editor.document
    prefix = root === list ? () : (FieldReferenceStep("content"),)
    set_selection!(root, annotate_reference_types(root, _ti_caret(k; prefix)))
    run_frame!(editor)
    (editor, backend, list)
end

function test_primitive_type_in()
@testset "the type-in of a number" begin

@testset "a text parses as a primitive, and a number shows a text exactly or not" begin
    @test parse_primitive_document(PrimitiveNumber, "12").value === 12
    @test parse_primitive_document(PrimitiveNumber, "1.5").value === 1.5
    @test parse_primitive_document(PrimitiveNumber, "1e") === nothing
    @test parse_primitive_document(PrimitiveNumber, "") === nothing
    @test parse_primitive_document(PrimitiveBool, "true").value === true
    @test parse_primitive_document(PrimitiveBool, "yes") === nothing
    @test parse_primitive_document(PrimitiveString, "yes").value == "yes"
    @test find_exact_primitive_document((PrimitiveNumber,), "-5").value === -5
    @test find_exact_primitive_document((PrimitiveNumber,), "12.") === nothing
    @test find_exact_primitive_document((PrimitiveNumber,), "1.50") === nothing
    @test find_exact_primitive_document((PrimitiveNumber,), "007") === nothing
    @test find_primitive_document((PrimitiveNumber,), "1.50").value === 1.5
    @test get_primitive_text(PrimitiveNumber(nothing)) == ""
end

@testset "keys that a number can not show make a type-in, and a number comes back" begin
    editor, backend, list = _ti_list_editor(2)
    steps = [(_ti_down(:backspace), PrimitiveNumber,    1,       "[1].value{1}"),
             (_ti_down(:backspace), PrimitiveInsertion, "",      "[1].value{0}"),
             (_ti_key('-'),         PrimitiveInsertion, "-",     "[1].value{1}"),
             (_ti_key('5'),         PrimitiveNumber,    -5,      "[1].value{2}"),
             (_ti_key('.'),         PrimitiveInsertion, "-5.",   "[1].value{3}"),
             (_ti_key('2'),         PrimitiveNumber,    -5.2,    "[1].value{4}"),
             (_ti_key('e'),         PrimitiveInsertion, "-5.2e", "[1].value{5}"),
             (_ti_key('3'),         PrimitiveInsertion, "-5.2e3", "[1].value{6}"),
             (_ti_down(:return),    PrimitiveNumber,    -5200.0, "[1].value{7}")]
    for (event, type, value, selection) in steps
        _ti_press!(editor, backend, event)
        @test list[1] isa type
        @test isequal(list[1].value, value)
        @test _ti_selection(editor) == selection
    end
    @test list[2].value === 7
    @test list[1] isa PrimitiveNumber
end

@testset "a type-in in a number is limited to a number" begin
    editor, backend, list = _ti_list_editor(2)
    _ti_press!(editor, backend, _ti_key('.'))
    @test list[1] isa PrimitiveInsertion
    @test list[1].allowed_types == (PrimitiveNumber,)
    leaf = PrimitiveInsertionToSyntaxLeaf()
    @test leaf.commit(list[1], "abc") === nothing
    @test leaf.commit(PrimitiveInsertion(), "true").value === true
    @test leaf.commit(PrimitiveInsertion(), "abc").value == "abc"
end

@testset "a letter changes no number" begin
    editor, backend, list = _ti_list_editor(2)
    _ti_press!(editor, backend, _ti_key('x'))
    @test list[1] isa PrimitiveNumber && list[1].value === 12
end

@testset "the text of a type-in is green when it parses and red when it does not" begin
    leaf = PrimitiveInsertionToSyntaxLeaf()
    limited(text) = PrimitiveInsertion(; value = text, allowed_types = (PrimitiveNumber,))
    @test leaf.completion(limited("")).state === :empty
    @test leaf.completion(limited("-")).state === :invalid
    @test leaf.completion(limited("1.50")).state === :unambiguous
end

@testset "Escape in a type-in puts an empty number, which takes a digit" begin
    editor, backend, list = _ti_list_editor(2)
    _ti_press!(editor, backend, _ti_key('e'))
    @test list[1] isa PrimitiveInsertion
    _ti_press!(editor, backend, _ti_down(:escape))
    @test list[1] isa PrimitiveNumber && list[1].value === nothing
    @test _ti_selection(editor) == "[1].value{0}"
    _ti_press!(editor, backend, _ti_key('5'))
    @test list[1] isa PrimitiveNumber && list[1].value === 5
end

@testset "undo takes back the key that made a type-in" begin
    editor, backend, list = _ti_list_editor(2; undo = true)
    _ti_press!(editor, backend, _ti_key('.'))
    @test list[1] isa PrimitiveInsertion
    _ti_press!(editor, backend, _ti_down(:z; ctrl = true))
    @test list[1] isa PrimitiveNumber && list[1].value === 12
end

@testset "only a dispatch that prints the type-in turns it on" begin
    @test !PrimitiveNumberToSyntaxLeaf().allows_type_in
    @test PrimitiveNumberToSyntaxLeaf(; allows_type_in = true).allows_type_in
end

end # @testset
end
