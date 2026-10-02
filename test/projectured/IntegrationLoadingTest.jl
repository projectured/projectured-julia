# The umbrella loads an installed integration when its trigger is loaded, in either
# order, and each installed model adapter with no trigger; a session without the
# umbrella loads only what it names. Each case is
# a new Julia process in the development environment, which names every trigger and
# every integration; one case uses an environment that names the trigger and not
# the integration.

const _INTEGRATION_NAMES = ("Projectured", "ProjecturedAnthropic", "ProjecturedDataFrames",
                            "ProjecturedMCP", "ProjecturedODBC", "ProjecturedOllama",
                            "ProjecturedOpenRouter", "ProjecturedSDL", "ProjecturedTulip",
                            "ProjecturedVideo", "ProjecturedWeb")

# The ProjecturEd packages of `_INTEGRATION_NAMES` that a new process with
# `environment` has loaded after `code`.
function _read_loaded_integrations(environment, code)
    report = """
        $code
        print(join(sort([package.name for package in keys(Base.loaded_modules)
                         if package.name in $(_INTEGRATION_NAMES)]), " "))
        """
    command = addenv(`$(Base.julia_cmd()) --startup-file=no --project=$environment -e $report`,
                     "SDL_VIDEODRIVER" => "offscreen", "JULIA_PKG_OFFLINE" => "true")
    split(read(command, String))
end

# An environment that names the umbrella and the trigger of SDL, and not
# `ProjecturedSDL`: the manifest of the development environment, with its paths
# made absolute.
function _make_environment_without_sdl(repository)
    folder = mktempdir()
    manifest = read(joinpath(repository, "environment", "all", "Manifest.toml"), String)
    write(joinpath(folder, "Manifest.toml"),
          replace(manifest, "path = \"../../package/" =>
                            "path = \"" * joinpath(repository, "package") * "/"))
    write(joinpath(folder, "Project.toml"), """
        [deps]
        Projectured = "92922de3-b970-4d9a-8b2a-9d6f361397b5"
        SimpleDirectMediaLayer = "98e33af6-2ee5-5afd-9e75-cbc738b767c4"
        """)
    folder
end

function test_umbrella_loads_integrations()
    @testset "the umbrella loads the installed integration of each trigger" begin
        repository = normpath(joinpath(@__DIR__, "..", ".."))
        environment = joinpath(repository, "environment", "all")
        # The model adapters load with the umbrella when they are installed.
        with_umbrella(names...) = sort!(["Projectured", "ProjecturedAnthropic",
                                         "ProjecturedOllama", "ProjecturedOpenRouter",
                                         names...])
        both = with_umbrella("ProjecturedDataFrames", "ProjecturedSDL")
        @test _read_loaded_integrations(environment,
            "using SimpleDirectMediaLayer, DataFrames, Projectured") == both
        # The order of the `using` lines does not matter.
        @test _read_loaded_integrations(environment,
            "using Projectured; using SimpleDirectMediaLayer; using DataFrames") == both
        # Without the umbrella, a session loads what it names and nothing more.
        @test _read_loaded_integrations(environment,
            "using SimpleDirectMediaLayer, DataFrames, ProjecturedDataFrames, ProjecturedWeb") ==
              ["ProjecturedDataFrames", "ProjecturedWeb"]
        # The umbrella alone loads no integration that has a trigger.
        @test _read_loaded_integrations(environment, "using Projectured") == with_umbrella()
        # A package that depends on the umbrella and on two adapters loads them in one
        # batch, and the umbrella loads the third adapter after the batch.
        @test _read_loaded_integrations(environment, "using ProjecturedExample") == with_umbrella()
        # Each of the other triggers; Video loads SDL, which it needs.
        @test _read_loaded_integrations(environment,
            "using FFMPEG, ODBC, Tulip, ModelContextProtocol, Projectured") ==
              with_umbrella("ProjecturedMCP", "ProjecturedODBC", "ProjecturedSDL",
                            "ProjecturedTulip", "ProjecturedVideo")
        # An integration or an adapter that the environment does not name stays
        # out, with no error.
        @test _read_loaded_integrations(_make_environment_without_sdl(repository),
            "using SimpleDirectMediaLayer, Projectured") == ["Projectured"]
    end
end
