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
        # A short answer ends with its hits.
        @test !occursin("Read one in full", answer)
        # A verb without a docstring shows its name and says so.
        verbs = search_api("verb"; api = api)
        @test occursin("- `bare_verb` — function in AnswerToy\n  (no documentation)", verbs)
    end

    @testset "a long answer ends with what to do next, and the detail says how much" begin
        long = search_api("make")
        @test length(long) > 600
        @test occursin("Read one in full: `read_resource(\"resource://", long)
        @test occursin("Narrow the search with +word or -word", long)
        # Names: one line per hit, up to 25, and no sentence under it.
        names = search_api("make"; detail = "names")
        hits = [line for line in split(names, '\n') if startswith(line, "- `")]
        @test 8 < length(hits) <= 25
        @test !any(line -> startswith(line, "  "), split(names, '\n'))
        # Full: the whole docstring of each, and a limit given replaces the count.
        full = search_api("make"; detail = "full", limit = 2)
        @test count("## `", full) == 2
        @test length(full) > length(search_api("make"; limit = 2))
        @test startswith(search_api("make"; detail = "everything"), "Unknown search detail \"everything\"")
        # The guides: the same levels, and a hit carries its section's URI.
        summary = search_guides("selection")
        @test occursin(r"^## resource://guide/\S+#\S+"m, summary)
        @test occursin("Read a section in full: `read_resource(\"resource://guide/", summary)
        guide_names = search_guides("selection"; detail = "names")
        @test all(line -> startswith(line, "- resource://guide/") || !startswith(line, "- "),
                  split(guide_names, '\n'))
        @test count("- resource://guide/", guide_names) > 8
        @test count("## resource://guide/", search_guides("selection"; detail = "full", limit = 1)) == 1
        # A miss names the other search.
        @test occursin("A guide may say it: `search_guides`", search_api("zzzznotarealword"; api = api))
        @test occursin("A verb may do it: `search_api`", search_guides("zzzznotarealword"))
    end

    @testset "a limit below one answers a sentence, and a real limit is rounded" begin
        for limit in (0, -1)
            @test startswith(search_guides("selection"; limit = limit),
                             "A limit of $limit shows no hit.")
            @test startswith(search_api("box"; api = api, limit = limit),
                             "A limit of $limit shows no hit.")
        end
        @test count("## resource://guide/", search_guides("selection"; limit = 2.5)) == 2
        @test count("\n- `", search_api("verb"; api = api, limit = 2.5)) == 2
    end

    @testset "a line that starts with # inside a code fence is no heading" begin
        sections = _AnswerTools._guide_index()
        @test !any(section -> startswith(section.heading, "@broken:") ||
                              startswith(section.heading, "Fragment of"), sections)
        marker = only(section for section in sections
                      if section.guide == "guide/testing-guide" &&
                         section.heading == "Marker format")
        @test occursin("# @broken: <one-line reason>", marker.body)
    end

    @testset "a file directly in the package folder is a guide" begin
        documentation = _AnswerTools._get_documentation_directory()
        readme = joinpath(documentation, "package", "README.md")
        @test read_guide("package/README") == read(readme, String)
        @test count("**package/README**", list_guides()) == 1
    end

    @testset "a section and a function are read by the shape of their URI" begin
        set = register_default_tools!(ToolSet())
        section = read_resource(set, "resource://guide/kernel/cell#invalidation")
        @test startswith(section, "## Invalidation")
        @test length(section) < length(read_resource(set, "resource://guide/kernel/cell"))
        @test startswith(read_resource(set, "resource://guide/kernel/cell#nothing-here"),
                         "Section 'nothing-here' not found in guide 'kernel/cell'. Its sections:")
        @test read_resource(set, "resource://guide/no/such#x") == "Documentation 'no/such' not found."
        @test occursin("Search modules", read_resource(set, "resource://function/ToolModule/search_api"))
        declared = register_default_tools!(ToolSet(; api = Module[AnswerToy]))
        @test occursin("Close the box", read_resource(declared, "resource://function/AnswerToy/fenced_verb"))
        @test occursin("not found", read_resource(declared, "resource://function/ToolModule/search_api"))
        # A whole guide that is long ends with its sections.
        whole = read_resource(set, "resource://guide/kernel/cell")
        @test occursin("\nSections: ", whole)
        @test occursin("Read one with `read_resource(\"resource://guide/kernel/cell#", whole)
        # The resource list is six lines by kind, and the tool answers the same.
        kinds = describe_resources(set)
        @test occursin("guides: `resource://guide/<name>`", kinds)
        @test occursin("`resource://function/<module>/<name>`", kinds)
        @test count('\n', kinds) == 7
        listing = only(t for t in list_tools(set) if t.name == "list_resources")
        @test listing.handler(nothing, Dict{String,Any}()) == kinds
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

    @testset "a module two entries name is one hit, and gives the names of both" begin
        twice = ToolSet(; api = [AnswerToy => (:fenced_verb,), AnswerToy => (:bare_verb, :AnswerBox)])
        entries = _AnswerTools._api_index(twice.api)
        @test count(entry -> entry.kind == "module", entries) == 1
        @test count(entry -> entry.kind == "function", entries) == 2
        # A name of the second entry is declared: its type has a resource, and
        # its verb is read.
        register_default_tools!(twice)
        @test occursin("A box with a lid", read_resource(twice, "resource://type/AnswerToy/AnswerBox"))
        @test occursin("Close the box", read_resource(twice, "resource://function/AnswerToy/fenced_verb"))
        @test !occursin("not one of the names", read_function_documentation("AnswerToy", "bare_verb"; api = twice.api))
    end

    @testset "a search on a tool set answers what its tool answers" begin
        set = register_default_tools!(ToolSet(; api = Module[AnswerToy]))
        search = only(t for t in list_tools(set) if t.name == "search_api")
        @test search_api(set, "box") == search.handler(nothing, Dict("query" => "box"))
        @test search_api(set, "box"; kind = "type") ==
              search.handler(nothing, Dict("query" => "box", "kind" => "type"))
        guides = only(t for t in list_tools(set) if t.name == "search_guides")
        @test search_guides(set, "selection"; limit = 2) ==
              guides.handler(nothing, Dict("query" => "selection", "limit" => 2))
        @test search_api(set, "box"; detail = "names") ==
              search.handler(nothing, Dict("query" => "box", "detail" => "names"))
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

    @testset "a documentation tool says that its answer is Markdown" begin
        set = register_default_tools!(ToolSet())
        mime_type = name -> find_tool(set, name).result_mime_type
        for name in ("list_resources", "read_resource", "search_guides", "search_api",
                     "read_function_documentation")
            @test mime_type(name) == "text/markdown"
        end
        @test mime_type("execute_julia_code") == "text/plain"
        # A tool that names no media type answers plain text.
        plain = Tool("plain";
                     description = "Answers a word.",
                     parameters = NamedTuple[],
                     handler = (target, args) -> "word")
        @test plain.result_mime_type == "text/plain"
    end

end
end # test_search_answer
