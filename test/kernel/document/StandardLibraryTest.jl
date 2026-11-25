"""
`DocumentModule` — the standard libraries of Julia that the editor loads by name.

Covers:
- `LOADABLE_STANDARD_LIBRARIES` names Dates, Statistics, Printf and Random, each
  with the package id of its own name,
- `load_standard_library!` gives the module of a library on the list, by a
  symbol or a string, and `nothing` for each other name,
- the load works in a process whose load path has no `@stdlib`, where a plain
  `using Statistics` fails.
"""

using Test
using ProjecturedKernel.DocumentModule: LOADABLE_STANDARD_LIBRARIES, load_standard_library!

function test_standard_library()
    @testset "the standard libraries that the editor loads by name" begin
        @testset "the list" begin
            @test collect(keys(LOADABLE_STANDARD_LIBRARIES)) == [:Dates, :Statistics, :Printf, :Random]
            for (name, id) in pairs(LOADABLE_STANDARD_LIBRARIES)
                @test id.name == String(name)
                @test id.uuid !== nothing
            end
        end

        @testset "a library of the list loads; another name gives nothing" begin
            random = load_standard_library!(:Random)
            @test random isa Module
            @test nameof(random) === :Random
            @test load_standard_library!("Random") === random
            @test load_standard_library!(:Plots) === nothing
            @test load_standard_library!(:Pkg) === nothing
            @test load_standard_library!("Base") === nothing
        end

        @testset "the load needs no @stdlib in the load path" begin
            # A process of its own, so that Statistics is not loaded yet, with the
            # load path of a window that has no `@stdlib`.
            code = """
                using ProjecturedKernel.DocumentModule: load_standard_library!
                id = Base.PkgId(Base.UUID("10745b16-79ce-11e8-11f9-7d13ad32a3b2"), "Statistics")
                before = Base.root_module_exists(id)
                plain = try
                    Core.eval(Module(:Scratch), :(using Statistics))
                    "works"
                catch exception
                    "fails"
                end
                statistics = load_standard_library!(:Statistics)
                println(before, " ", plain, " ", nameof(statistics), " ", statistics.mean([1, 2, 6]))
                """
            command = addenv(`$(Base.julia_cmd()) --startup-file=no --project=$(Base.active_project()) -e $code`,
                             "JULIA_LOAD_PATH" => "@")
            answer = strip(read(command, String))
            @test answer == "false fails Statistics 3.0"
        end
    end
end
