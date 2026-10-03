# AutoIntegrations loads a candidate when its triggers are loaded and its state
# is "auto". Each case is a new Julia process in a scratch environment of small
# packages, which names AutoIntegrations by its folder. The process sees only the
# scratch environment and the standard library, and it writes its cache files
# into a scratch depot.

const _SCRATCH_UUIDS = Dict(
    "TriggerA"   => "10000000-0000-0000-0000-0000000000a1",
    "TriggerB"   => "10000000-0000-0000-0000-0000000000a2",
    "TriggerC"   => "10000000-0000-0000-0000-0000000000a3",
    "GlueAB"     => "10000000-0000-0000-0000-0000000000b1",
    "GlueManual" => "10000000-0000-0000-0000-0000000000b2",
    "GlueChain"  => "10000000-0000-0000-0000-0000000000b3",
    "GlueBroken" => "10000000-0000-0000-0000-0000000000b4",
    "HiddenGlue" => "10000000-0000-0000-0000-0000000000b5")

# The packages that only AutoIntegrations loads.
const _GLUES = ("GlueAB", "GlueManual", "GlueChain", "GlueBroken", "HiddenGlue")

# A package in `folder` with the dependencies `deps` (the packages of `sources` by
# their folders), the table `[auto-integration]` when it has `triggers`, and
# `body` in its module.
function _make_scratch_package(folder, name; deps = String[], sources = String[],
                               triggers = String[], default = nothing, body = "")
    root = joinpath(folder, name)
    mkpath(joinpath(root, "src"))
    project = """
        name = "$name"
        uuid = "$(_SCRATCH_UUIDS[name])"
        version = "0.1.0"
        """
    isempty(deps) || (project *= "\n[deps]\n" *
                      join(["$dep = \"$(_SCRATCH_UUIDS[dep])\"\n" for dep in deps]))
    isempty(sources) || (project *= "\n[sources]\n" *
                         join(["$source = {path = \"../$source\"}\n" for source in sources]))
    if !isempty(triggers)
        project *= "\n[auto-integration]\n"
        default === nothing || (project *= "default = \"$default\"\n")
        project *= "\n[auto-integration.triggers]\n" *
                   join(["$trigger = \"$(_SCRATCH_UUIDS[trigger])\"\n" for trigger in triggers])
    end
    write(joinpath(root, "Project.toml"), project)
    write(joinpath(root, "src", "$name.jl"), "module $name\n$body\nend\n")
    root
end

_scratch_environment_variables(depot) =
    ("JULIA_LOAD_PATH" => "@" * (Sys.iswindows() ? ";" : ":") * "@stdlib",
     "JULIA_DEPOT_PATH" => depot * (Sys.iswindows() ? ";" : ":"),
     "JULIA_PKG_OFFLINE" => "true", "JULIA_PKG_PRECOMPILE_AUTO" => "0")

# A scratch environment that names AutoIntegrations and the scratch packages,
# except `HiddenGlue`, which only `TriggerB` depends on. It answers the folder of
# the environment and the folder of the scratch depot.
function _make_scratch_environment()
    folder = mktempdir()
    packages = [
        _make_scratch_package(folder, "TriggerA"),
        _make_scratch_package(folder, "TriggerB"; deps = ["HiddenGlue"],
                              sources = ["HiddenGlue"]),
        _make_scratch_package(folder, "TriggerC"),
        _make_scratch_package(folder, "GlueAB"; triggers = ["TriggerA", "TriggerB"],
                              default = "auto"),
        _make_scratch_package(folder, "GlueManual"; triggers = ["TriggerA"]),
        _make_scratch_package(folder, "GlueChain"; triggers = ["GlueAB"], default = "auto"),
        _make_scratch_package(folder, "GlueBroken"; triggers = ["TriggerC"], default = "auto",
                              body = "error(\"GlueBroken does not load\")")]
    _make_scratch_package(folder, "HiddenGlue"; triggers = ["TriggerA"], default = "auto")
    environment = mkpath(joinpath(folder, "environment"))
    depot = mkpath(joinpath(folder, "depot"))
    paths = [pkgdir(AutoIntegrations); packages]
    code = "using Pkg; Pkg.develop([PackageSpec(path = path) for path in $(repr(paths))]; io = devnull)"
    run(addenv(`$(Base.julia_cmd()) --startup-file=no --project=$environment -e $code`,
               _scratch_environment_variables(depot)...))
    environment, depot
end

# The packages of `_GLUES` that a new process of `environment` has loaded after
# `code`, and the text of its standard error.
function _read_loaded_glues(environment, depot, code)
    report = """
        $code
        print(join(sort([package.name for package in keys(Base.loaded_modules)
                         if package.name in $(_GLUES)]), " "))
        """
    output = IOBuffer()
    errors = IOBuffer()
    command = addenv(`$(Base.julia_cmd()) --startup-file=no --project=$environment -e $report`,
                     _scratch_environment_variables(depot)...)
    run(pipeline(command; stdout = output, stderr = errors))
    split(String(take!(output))), String(take!(errors))
end

_write_preferences(environment, text) =
    write(joinpath(environment, "LocalPreferences.toml"), text)

_remove_preferences(environment) =
    rm(joinpath(environment, "LocalPreferences.toml"); force = true)

function test_automatic_load()
    @testset "AutoIntegrations loads a candidate when its triggers are loaded" begin
        environment, depot = _make_scratch_environment()
        read_loaded(code) = first(_read_loaded_glues(environment, depot, code))

        # GlueAB loads with its two triggers, and GlueChain with GlueAB. GlueManual
        # has no default, so it stays. HiddenGlue is no direct dependency of the
        # environment, so it stays.
        @test read_loaded("using AutoIntegrations, TriggerA, TriggerB") == ["GlueAB", "GlueChain"]
        # The order of the `using` lines does not matter, and triggers that loaded
        # before AutoIntegrations count.
        @test read_loaded("using TriggerA; using AutoIntegrations; using TriggerB") ==
              ["GlueAB", "GlueChain"]
        @test read_loaded("using TriggerA, TriggerB; using AutoIntegrations") ==
              ["GlueAB", "GlueChain"]
        # One trigger is not enough.
        @test read_loaded("using AutoIntegrations, TriggerA") == String[]
        # Without AutoIntegrations nothing loads by itself.
        @test read_loaded("using TriggerA, TriggerB") == String[]
        # A loaded candidate binds no name in `Main`.
        @test read_loaded("using AutoIntegrations, TriggerA, TriggerB; " *
                          "isdefined(Main, :GlueAB) && error(\"GlueAB is bound in Main\")") ==
              ["GlueAB", "GlueChain"]

        # A candidate that fails to load gives a warning, and the others load.
        loaded, errors = _read_loaded_glues(environment, depot,
                                            "using AutoIntegrations, TriggerC, TriggerA, TriggerB")
        @test loaded == ["GlueAB", "GlueChain"]
        @test occursin("GlueBroken failed to load", errors)

        # The environment of the user sets the state, over the default.
        _write_preferences(environment, """
            [AutoIntegrations]
            GlueAB = "manual"
            GlueManual = "auto"
            """)
        @test read_loaded("using AutoIntegrations, TriggerA, TriggerB") == ["GlueManual"]
        # A state that is not "auto" or "manual" gives a warning and the default.
        _write_preferences(environment, "[AutoIntegrations]\nGlueAB = \"sometimes\"\n")
        loaded, errors = _read_loaded_glues(environment, depot,
                                            "using AutoIntegrations, TriggerA, TriggerB")
        @test loaded == ["GlueAB", "GlueChain"]
        @test occursin("not \"sometimes\"", errors)
        _remove_preferences(environment)
    end
end

function test_set_auto_integration()
    @testset "set_auto_integration! writes the state into the active project" begin
        environment, depot = _make_scratch_environment()
        preferences = joinpath(environment, "LocalPreferences.toml")
        read_loaded(code) = first(_read_loaded_glues(environment, depot, code))

        @test read_loaded("using AutoIntegrations; set_auto_integration!(\"GlueAB\", :manual); " *
                          "set_auto_integration!(\"GlueManual\", :auto)") == String[]
        @test TOML.parsefile(preferences) ==
              Dict("AutoIntegrations" => Dict("GlueAB" => "manual", "GlueManual" => "auto"))
        @test read_loaded("using AutoIntegrations, TriggerA, TriggerB") == ["GlueManual"]

        # `nothing` removes an entry, and the last one removes the table.
        read_loaded("using AutoIntegrations; set_auto_integration!(\"GlueAB\", nothing)")
        @test TOML.parsefile(preferences) == Dict("AutoIntegrations" => Dict("GlueManual" => "auto"))
        read_loaded("using AutoIntegrations; set_auto_integration!(\"GlueManual\", nothing)")
        @test TOML.parsefile(preferences) == Dict{String,Any}()

        @test_throws ArgumentError AutoIntegrations.set_auto_integration!("GlueAB", :sometimes)
    end
end
