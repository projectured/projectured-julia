"""
    test_autointegrations_layering()

AutoIntegrations names no ProjecturEd package: its only dependency is the TOML
standard library, and its source loads no other package.
"""
function test_autointegrations_layering()
    @testset "AutoIntegrations depends on TOML alone" begin
        root = pkgdir(AutoIntegrations)
        project = TOML.parsefile(joinpath(root, "Project.toml"))
        @test collect(keys(get(project, "deps", Dict()))) == ["TOML"]
        code = read(pathof(AutoIntegrations), String)
        @test [m.captures[1] for m in eachmatch(r"^\s*(?:using|import)\s+(\w+)"m, code)] == ["TOML"]
        @test !occursin(r"^\s*include\("m, code)
    end
end

"Run the suite of AutoIntegrations."
function test_autointegrations()
    @testset "AutoIntegrations" begin
        test_autointegrations_layering()
        test_automatic_load()
        test_set_auto_integration()
    end
end

export test_autointegrations, test_autointegrations_layering, test_automatic_load,
       test_set_auto_integration
