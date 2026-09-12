"""
The declared API — what a model may write, and what it may find.

A `ToolSet` that names modules gets those and nothing else, in both directions:
`execute_julia_code` resolves their names and no others, and the documentation
tools offer their names and no others. The two are one list, because a model that
finds a function it cannot call wastes a round.
"""

using Test
using ProjecturedKernel.ToolModule

# A module of the kind a caller declares: a few verbs and nothing more. Julia
# allows `module` only at the top level, so the fixture lives here rather than
# inside the testset.
module ToyApi
export toy_verb, toy_count
"""Answer the word this verb is named after."""
toy_verb() = "toy"
"""Count what it is given."""
toy_count(xs) = length(xs)
end

# A docstring shaped the way this repository writes one: an indented signature
# block, a blank line, then the sentence that says what the thing does. Julia
# strips a docstring's common indentation before storing it, so that block
# arrives flush left — which is what made every entry index its signature and
# nothing else.
module ToyShaped
export toy_arrange
"""
    toy_arrange(window) -> String

Put every pane where the person asked for it.
"""
toy_arrange(window) = "arranged"
end

# A second one, to prove that two declared modules both arrive.
module ToyExtra
export toy_extra
"""A verb from a second declared module."""
toy_extra() = 7
end

function test_declared_api()
@testset "Declared API" begin

    @testset "an empty declaration is the whole surface" begin
        set = ToolSet()
        @test isempty(set.api)
        # `Cell` is a kernel name, so it resolves through the default gathering.
        @test occursin("Cell", execute_julia_code(set, nothing, "string(Cell)"))
    end

    @testset "a call with no code answers that, rather than answering nothing" begin
        # Empty source evaluates to nothing and prints nothing, so the tool used to
        # answer an empty string — which a model reads as a broken tool rather than
        # as its own mistake, and then it stops writing code at all.
        set = ToolSet()
        for blank in ("", "\n", "   \n  ")
            answer = execute_julia_code(set, nothing, blank)
            @test occursin("No code was given", answer)
            @test occursin("`code`", answer)
        end
        # And a real call still runs.
        @test strip(execute_julia_code(set, nothing, "1 + 1")) == "2"
    end

    @testset "a function's documentation is reachable as a tool" begin
        # `search_api` answers a `read_function_documentation(…)` call for every
        # function it finds, and a module or a type has a resource:// URI. A
        # function has none, so without this tool the only way to a docstring is
        # to write Julia — and a model told to "call read_function_documentation"
        # looks for a tool of that name, finds none, and sends an empty call.
        set = ToolSet(; api = Module[ToyApi])
        register_default_tools!(set)
        tool = only([t for t in set.tools if t.name == "read_function_documentation"])
        answer = tool.handler(nothing, Dict("module_name" => "ToyApi",
                                            "function_name" => "toy_verb"))
        @test occursin("Answer the word this verb is named after", answer)
    end

    # A model looks for a verb by what it does, and the words for that are in the
    # description. Scored on the signature alone, `search_api` could answer a name
    # and never a sentence: `show_layout`'s docstring said "Which panes are open"
    # and a search for "panes" answered nothing at all.
    @testset "a verb is found by its description, not only by its name" begin
        set = ToolSet(; api = Module[ToyShaped])
        register_default_tools!(set)
        search = only([t for t in set.tools if t.name == "search_api"])

        # Each of these words is in the description and nowhere else — not in the
        # verb's name, not in its module's, not in its signature.
        for word in ("pane", "person", "asked")
            @test occursin("toy_arrange", search.handler(nothing, Dict("query" => word)))
        end

        # What a hit SHOWS is still the signature. The prompt promises one, and a
        # model calls a verb off it without reading the documentation.
        @test occursin("toy_arrange(window) -> String",
                       search.handler(nothing, Dict("query" => "toy_arrange")))
    end

    @testset "a declared module is what resolves" begin
        set = ToolSet(; api = Module[ToyApi])
        @test execute_julia_code(set, nothing, "toy_verb()") |> strip == "\"toy\""
        @test strip(execute_julia_code(set, nothing, "toy_count([1, 2, 3])")) == "3"
    end

    @testset "a name outside the declaration fails in the round that used it" begin
        set = ToolSet(; api = Module[ToyApi])
        answer = execute_julia_code(set, nothing, "Cell(1)")
        @test occursin("UndefVarError", answer)
        @test occursin("Cell", answer)
    end

    # The declaration opens as much as it narrows. The default gathering collects
    # modules by PACKAGE name, so a module in a package not called `Projectured…`
    # — every module of every other repository — is unreachable until a `ToolSet`
    # names it. This fixture cannot show that half: it lives inside
    # `ProjecturedKernelTest`, which the default gathering does reach. What it can
    # show is the narrowing, and that a declaration is what carries a module in.
    @testset "the declaration decides, in both directions" begin
        wide = ToolSet()
        narrow = ToolSet(; api = Module[ToyApi])
        @test occursin("Cell", execute_julia_code(wide, nothing, "string(Cell)"))
        @test occursin("UndefVarError", execute_julia_code(narrow, nothing, "string(Cell)"))
        @test strip(execute_julia_code(narrow, nothing, "toy_verb()")) == "\"toy\""
    end

    @testset "two declared modules both arrive" begin
        set = ToolSet(; api = Module[ToyApi, ToyExtra])
        @test strip(execute_julia_code(set, nothing, "toy_verb()")) == "\"toy\""
        @test strip(execute_julia_code(set, nothing, "string(toy_extra())")) == "\"7\""
    end

    @testset "state still survives between calls" begin
        set = ToolSet(; api = Module[ToyApi])
        execute_julia_code(set, nothing, "kept = toy_count([1, 2])")
        @test strip(execute_julia_code(set, nothing, "string(kept)")) == "\"2\""
    end

    @testset "the target is still bound as editor" begin
        set = ToolSet(; api = Module[ToyApi])
        @test strip(execute_julia_code(set, (name = "a",), "editor.name")) == "\"a\""
    end

    # Both directions of the invariant. Every name the tools offer resolves, and
    # nothing else does.
    @testset "what is discoverable is what is callable" begin
        set = ToolSet(; api = Module[ToyApi])
        found = search_api("toy"; modules = set.api)
        @test occursin("toy_verb", found)
        @test occursin("toy_count", found)
        # A name of the wider surface is not offered. The answer echoes the query,
        # so the assertion is that nothing was found, not that the word is absent.
        @test occursin("No API matches", search_api("CellVector"; modules = set.api))
        # And every name that IS offered resolves in the scratch module.
        for verb in ("toy_verb", "toy_count")
            @test !occursin("UndefVarError",
                            execute_julia_code(set, nothing, "string(" * verb * ")"))
        end
    end

    # The resources a declared set publishes are its own modules, and the guides
    # are withheld: they describe the whole editor, and would send the model to
    # read about a surface it cannot reach.
    @testset "the resources are the declared modules, and no guides" begin
        set = register_default_tools!(ToolSet(; api = Module[ToyApi]))
        uris = [r.uri for r in list_resources(set)]
        @test "resource://module/ToyApi" in uris
        @test "resource://modules" in uris
        @test !any(u -> startswith(u, "resource://guide"), uris)
        @test occursin("ToyApi", read_resource(set, "resource://modules"))
        @test occursin("Answer the word", read_resource(set, "resource://module/ToyApi")) ||
              occursin("ToyApi", read_resource(set, "resource://module/ToyApi"))

        wide = register_default_tools!(ToolSet())
        wide_uris = [r.uri for r in list_resources(wide)]
        @test any(u -> startswith(u, "resource://guide"), wide_uris)
    end

    # The description the model reads names the modules it may call, so it is not
    # sent to read five guides about a surface it does not have.
    @testset "the tool description follows the declaration" begin
        set = register_default_tools!(ToolSet(; api = Module[ToyApi]))
        tool = only(t for t in list_tools(set) if t.name == "execute_julia_code")
        @test occursin("ToyApi", tool.description)
        @test !occursin("resource://guide/getting-started", tool.description)

        wide = only(t for t in list_tools(register_default_tools!(ToolSet()))
                    if t.name == "execute_julia_code")
        @test occursin("Projectured", wide.description)
    end

    # A declaration that arrives after the namespace was built must still take
    # effect, so it drops the namespace.
    @testset "declaring after the first evaluation still takes effect" begin
        set = ToolSet()
        @test occursin("Cell", execute_julia_code(set, nothing, "string(Cell)"))
        declare_api!(set, Module[ToyApi])
        @test occursin("UndefVarError", execute_julia_code(set, nothing, "string(Cell)"))
        @test strip(execute_julia_code(set, nothing, "toy_verb()")) == "\"toy\""
        declare_api!(set, Module[])
        @test occursin("Cell", execute_julia_code(set, nothing, "string(Cell)"))
    end

    # How to look is always in scope, and it looks only at what was declared.
    @testset "the model can look things up from the code it writes" begin
        set = ToolSet(; api = Module[ToyApi])
        found = execute_julia_code(set, nothing, "search_api(\"toy\")")
        @test occursin("toy_verb", found)
        doc = execute_julia_code(set, nothing,
                                 "read_function_documentation(\"ToyApi\", \"toy_verb\")")
        @test occursin("Answer the word", doc)
        # It cannot widen its own view: the declaration is applied for it.
        @test occursin("No API matches", execute_julia_code(set, nothing, "search_api(\"Cell\")"))
    end

    @testset "a docstring is the interface, and it is readable" begin
        set = ToolSet(; api = Module[ToyApi])
        doc = read_function_documentation("ToyApi", "toy_verb"; modules = set.api)
        @test occursin("Answer the word", doc)
    end

end
end # test_declared_api
