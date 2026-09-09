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

    @testset "a docstring is the interface, and it is readable" begin
        set = ToolSet(; api = Module[ToyApi])
        doc = read_function_documentation("ToyApi", "toy_verb"; modules = set.api)
        @test occursin("Answer the word", doc)
    end

end
end # test_declared_api
