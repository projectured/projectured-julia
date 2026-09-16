"""
The answer of `search_api`: how a docstring is read into what a hit shows, the
two lines of a hit, the line that says how to read one in full, and the searches
on a tool set.
"""

using Test
using ProjecturedKernel.ToolModule

const _AnswerTools = ProjecturedKernel.ToolModule

# Docstrings in the shapes a hit must read: a fenced signature with bold prose
# and an abbreviation, two signatures in one paragraph, no docstring, a type
# with a field list, and a verb a declaration renames.
module AnswerToy
export fenced_verb, overloaded_verb, bare_verb, AnswerBox, renamed_verb
"""
```julia
fenced_verb(box; force = false) -> Nothing
```

**Close the box** so that e.g. its lid stays shut. Then it waits.
"""
fenced_verb(box; force = false) = nothing
"""
    overloaded_verb(x) -> Int
    overloaded_verb(x, y) -> Int

Add what it is given.
"""
overloaded_verb(x, y = 0) = 0
bare_verb() = nothing
"""
    AnswerBox(; lid)

A box with a lid.

# Fields
- `lid`: whether it is shut.
"""
struct AnswerBox
    lid::Bool
end
"""
    renamed_verb(box) -> Bool

Say whether the box is shut.
"""
renamed_verb(box) = true
end

function test_search_answer()
@testset "Search answer" begin

    @testset "a docstring is read into a signature and a sentence" begin
        read = _AnswerTools._read_doc_heading
        doc = name -> _AnswerTools._binding_doc(AnswerToy, name)
        signature, summary = read(doc(:fenced_verb), "fenced_verb")
        @test signature == "fenced_verb(box; force = false) -> Nothing"
        # The bold is removed, "e.g." ends no sentence, and the second one is
        # not shown.
        @test summary == "Close the box so that e.g. its lid stays shut."
        signature, summary = read(doc(:overloaded_verb), "overloaded_verb")
        @test signature == "overloaded_verb(x) -> Int"
        @test summary == "Add what it is given."
        signature, summary = read(doc(:AnswerBox), "AnswerBox")
        @test signature == "AnswerBox(; lid)"
        @test summary == "A box with a lid."
        # A renamed verb shows the name the model writes.
        signature, _ = read(doc(:renamed_verb), "renamed_verb", "shut_verb")
        @test signature == "shut_verb(box) -> Bool"
        @test read("", "bare_verb") == ("", "")
        # A docstring without a signature has a summary and no signature.
        @test read("Just a sentence. And another.", "x") == ("", "Just a sentence.")
    end

    api = ApiEntry[ApiEntry(AnswerToy, nothing)]

    @testset "a hit is two lines, and the footer says how to read one" begin
        answer = search_api("box"; api = api)
        lines = split(answer, '\n')
        @test "- `fenced_verb(box; force = false) -> Nothing` — function in AnswerToy" in lines
        @test "  Close the box so that e.g. its lid stays shut." in lines
        @test "- `AnswerBox(; lid)` — type in AnswerToy" in lines
        @test "  A box with a lid." in lines
        # The name is written once, in the signature; nothing is bold.
        @test !occursin("`fenced_verb` ", answer)
        @test !occursin("**", answer)
        @test !occursin("→ read full", answer)
        # One footer, for the kinds the answer holds.
        @test count("Read a function with `read_function_documentation(module, name)`", answer) == 1
        @test occursin("a type with `read_resource(\"resource://type/<module>/<name>\")`", answer)
        # An answer of functions alone says nothing about a type.
        verbs = search_api("verb"; api = api)
        @test occursin("Read a function with", verbs)
        @test !occursin("a type with", verbs)
        # A verb without a docstring shows its name and says so.
        @test occursin("- `bare_verb` — function in AnswerToy\n  (no documentation)", verbs)
    end

    @testset "a declared name is shown as the model writes it" begin
        renamed = ApiEntry[ApiEntry(AnswerToy, [:renamed_verb => :shut_verb])]
        # One clear hit prints the whole docstring, and its signature says the
        # name the model writes; the prose keeps its own words.
        answer = search_api("shut"; api = renamed)
        @test occursin("the one API match", answer)
        @test occursin("shut_verb(box) -> Bool", answer)
        @test !occursin("renamed_verb(", answer)
        @test occursin("Say whether the box is shut.", answer)
        # In a list beside another hit, the same signature shows the same name.
        two = ApiEntry[ApiEntry(AnswerToy, [:renamed_verb => :shut_verb, :fenced_verb])]
        listed = search_api("box"; api = two)
        @test occursin("`shut_verb(box) -> Bool` — function in AnswerToy", listed)
        @test occursin("`fenced_verb(box; force = false) -> Nothing`", listed)
        # The declaration lines show one signature each, the first of a paragraph.
        described = describe_api([AnswerToy => (:overloaded_verb,)])
        @test occursin("overloaded_verb(x) -> Int", described)
        @test !occursin("overloaded_verb(x, y)", described)
    end

    @testset "a module two entries name is one hit" begin
        twice = ToolSet(; api = [AnswerToy => (:fenced_verb,), AnswerToy => (:bare_verb,)])
        entries = _AnswerTools._api_index(twice.api)
        @test count(entry -> entry.kind == "module", entries) == 1
        @test count(entry -> entry.kind == "function", entries) == 2
    end

    @testset "a search on a tool set answers what its tool answers" begin
        set = register_default_tools!(ToolSet(; api = Module[AnswerToy]))
        search = only(t for t in list_tools(set) if t.name == "search_api")
        @test search_api(set, "box") == search.handler(nothing, Dict("query" => "box"))
        @test search_api(set, "box"; kind = "type") ==
              search.handler(nothing, Dict("query" => "box", "kind" => "type"))
        guides = only(t for t in list_tools(set) if t.name == "search_documentation")
        @test search_documentation(set, "selection"; limit = 2) ==
              guides.handler(nothing, Dict("query" => "selection", "limit" => 2))
        # Without a meaning model, a description says so and never "this editor".
        note = first(split(search_api(set, "shut the box"; mode = "description"), '\n'))
        @test startswith(note, "No meaning model was given")
        @test occursin("mode \"keywords\"", note)
        @test !occursin("editor", note)
    end

    @testset "a catalogue line shows the description and not the signature" begin
        listed = list_modules(; api = api)
        @test occursin("Types: AnswerBox", listed)
        @test !occursin("Classes:", listed)
    end

end
end # test_search_answer
