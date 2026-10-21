# A YAML file says what the pointer is on: the path of the part from the root of
# the file, its type, and its length, its value or its count. The part under the
# pointer is the end of the mouse target of the file; with no pointer, the end of
# its selection.

# The note that the file answers to a dwell, or `nothing`.
function _yfn_read_note(file)
    operation = read_gesture(file, MouseDwell(0, 0; time = 0.0))
    operation === nothing ? nothing : only(get_wrapped_operation(operation).layers)[2]
end

# The path from `file` to its part that `found` names.
_yfn_path(file, found) = only(search_references(file, node -> found(node)))

function test_yaml_file_note()
@testset "a JSON file says the path of the part under the pointer" begin
    file = YamlFile("a.yaml", parse_yaml("users:\n  - name: Alice\nmy key: 2\n"))
    @test _yfn_read_note(file) === nothing
    alice = _yfn_path(file, node -> node isa YamlString && node.value == "Alice")
    # The pointer rests in the text of the string: the note is about the string.
    replace_mouse_target!(file, extend_reference(alice, FieldReferenceStep("value")))
    note = _yfn_read_note(file)
    @test note.title == "a.yaml"
    @test note.facts == ["Path" => "users[1].name", "Type" => "String", "Length" => "5"]
    # A key that is not a plain name stands in brackets, and a number says its value.
    two = _yfn_path(file, node -> node isa YamlNumber && node.value == 2)
    replace_mouse_target!(file, two)
    @test _yfn_read_note(file).facts == ["Path" => "[\"my key\"]", "Type" => "Number", "Value" => "2"]
    # A sequence says how many elements it holds.
    users = _yfn_path(file, node -> node isa YamlSequence)
    replace_mouse_target!(file, users)
    @test _yfn_read_note(file).facts == ["Path" => "users", "Type" => "Sequence", "Elements" => "1"]
    # With no pointer on the file, the note is about the selected part.
    selected = YamlFile("b.yaml", parse_yaml("name: Bob\n"))
    replace_selection!(selected, _yfn_path(selected, node -> node isa YamlString))
    @test _yfn_read_note(selected).facts == ["Path" => "name", "Type" => "String", "Length" => "3"]
end
end
