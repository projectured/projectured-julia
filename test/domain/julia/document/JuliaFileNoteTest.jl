# A Julia file says what a call is: the signature of the function of the same name
# in the file, and its docstring when it has one. The part under the pointer is the
# end of the mouse target of the file; with no pointer, the end of its selection.

# The note that the file answers to a dwell, or `nothing`.
function _jfln_read_note(file)
    operation = read_gesture(file, MouseDwell(0, 0; time = 0.0))
    operation === nothing ? nothing : only(get_wrapped_operation(operation).layers)[2]
end

# The path from `file` to its part that `found` names.
_jfln_path(file, found) = only(search_references(file, node -> found(node)))

function test_julia_file_note()
@testset "a Julia file says the function that a call names" begin
    source = "\"\"\"\nAdd two numbers.\n\"\"\"\nfunction add(a, b)\n    a + b\nend\n\nfunction twice(x)\n    x * 2\nend\n\ntotal = add(1, 2)\nother = twice(3)\nmissing_one = nothing_here(4)\n"
    file = JuliaFile("a.jl", parse_julia(source))
    @test _jfln_read_note(file) === nothing
    # A documented function: the signature as code and the docstring as text.
    call = _jfln_path(file, node -> node isa JuliaCall && node.callee isa JuliaIdentifier && node.callee.name == "add")
    replace_mouse_target!(file, call)
    note = _jfln_read_note(file)
    @test note.title == "add"
    @test note.code == "add(a, b)"
    @test occursin("Add two numbers.", note.text)
    # The pointer on the callee is on the call as well.
    replace_mouse_target!(file, extend_reference(call, FieldReferenceStep("callee")))
    @test _jfln_read_note(file).title == "add"
    # A function with no docstring says its signature alone.
    twice = _jfln_path(file, node -> node isa JuliaCall && node.callee isa JuliaIdentifier && node.callee.name == "twice")
    replace_mouse_target!(file, twice)
    note = _jfln_read_note(file)
    @test (note.title, note.code, note.text) == ("twice", "twice(x)", nothing)
    # A call of a function that the file does not define says nothing.
    unknown = _jfln_path(file, node -> node isa JuliaCall && node.callee isa JuliaIdentifier && node.callee.name == "nothing_here")
    replace_mouse_target!(file, unknown)
    @test _jfln_read_note(file) === nothing
    # With no pointer on the file, the note is about the selected call.
    selected = JuliaFile("b.jl", parse_julia("function f(x)\n    x\nend\ny = f(1)\n"))
    replace_selection!(selected, _jfln_path(selected, node -> node isa JuliaCall && node.callee isa JuliaIdentifier && node.callee.name == "f"))
    @test _jfln_read_note(selected).code == "f(x)"
end
end
