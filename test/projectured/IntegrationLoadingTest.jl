# The umbrella loads an installed integration when its trigger is loaded, in either
# order, and each installed model adapter with no trigger; a session without the
# umbrella loads only what it names. Each case is
# a new Julia process in the development environment, which names every trigger and
# every integration; one case uses an environment that names the trigger and not
# the integration.

const _INTEGRATION_NAMES = ("Projectured", "ProjecturedAnthropic", "ProjecturedDataFrames",
                            "ProjecturedJSON",
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

# An environment that names only `deps`, `"<name>" => "<uuid>"`: the manifest of
# the development environment with its paths made absolute, and `extra`, entries
# of the manifest for packages of the test.
function _make_scratch_environment(repository, deps; extra = "")
    folder = mktempdir()
    manifest = read(joinpath(repository, "environment", "all", "Manifest.toml"), String)
    write(joinpath(folder, "Manifest.toml"),
          replace(manifest, "path = \"../../package/" =>
                            "path = \"" * joinpath(repository, "package") * "/") * extra)
    write(joinpath(folder, "Project.toml"),
          "[deps]\n" * join(["$name = \"$uuid\"\n" for (name, uuid) in deps]))
    folder
end

# A package that depends on the umbrella and on the Ollama adapter, so that Julia
# loads both in one batch, in an environment that also names the OpenRouter adapter.
function _make_environment_with_umbrella_and_adapter(repository)
    folder = mktempdir()
    uuid = "10000000-0000-0000-0000-000000000021"
    package = joinpath(folder, "UmbrellaWithAdapter")
    mkpath(joinpath(package, "src"))
    write(joinpath(package, "Project.toml"), """
        name = "UmbrellaWithAdapter"
        uuid = "$uuid"
        version = "0.1.0"

        [deps]
        Projectured = "92922de3-b970-4d9a-8b2a-9d6f361397b5"
        ProjecturedOllama = "1e313069-2975-45bd-ba6e-35a6296eb437"
        """)
    write(joinpath(package, "src", "UmbrellaWithAdapter.jl"),
          "module UmbrellaWithAdapter\nusing Projectured\nusing ProjecturedOllama\nend\n")
    _make_scratch_environment(repository,
        ["UmbrellaWithAdapter" => uuid,
         "ProjecturedOpenRouter" => "52a43d73-2617-4b68-a734-0e5186e9ad8a"];
        extra = """

            [[deps.UmbrellaWithAdapter]]
            deps = ["Projectured", "ProjecturedOllama"]
            path = "$package"
            uuid = "$uuid"
            version = "0.1.0"
            """)
end

function test_umbrella_loads_integrations()
    @testset "the umbrella loads the installed integration of each trigger" begin
        repository = normpath(joinpath(@__DIR__, "..", ".."))
        environment = joinpath(repository, "environment", "all")
        # The domains and the model adapters load with the umbrella when they are
        # installed; JSON stands for the domains.
        with_umbrella(names...) = sort!(["Projectured", "ProjecturedAnthropic", "ProjecturedJSON",
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
        # A package that depends on the umbrella and on an adapter loads them in one
        # batch, and the umbrella loads another installed adapter after the batch.
        @test _read_loaded_integrations(_make_environment_with_umbrella_and_adapter(repository),
            "using UmbrellaWithAdapter") ==
              ["Projectured", "ProjecturedOllama", "ProjecturedOpenRouter"]
        # Each of the other triggers; Video loads SDL, which it needs.
        @test _read_loaded_integrations(environment,
            "using FFMPEG, ODBC, Tulip, ModelContextProtocol, Projectured") ==
              with_umbrella("ProjecturedMCP", "ProjecturedODBC", "ProjecturedSDL",
                            "ProjecturedTulip", "ProjecturedVideo")
        # A domain, an integration or an adapter that the environment does not name
        # stays out, with no error.
        @test _read_loaded_integrations(
            _make_scratch_environment(repository,
                ["Projectured" => "92922de3-b970-4d9a-8b2a-9d6f361397b5",
                 "SimpleDirectMediaLayer" => "98e33af6-2ee5-5afd-9e75-cbc738b767c4"]),
            "using SimpleDirectMediaLayer, Projectured") == ["Projectured"]
    end
end

# The `Projectured*` names under the heading `section`, for example `"[deps]"`, of
# the `Project.toml` of the package `name`.
function _read_project_packages(repository, name, section)
    packages = String[]
    inside = false
    for line in eachline(joinpath(repository, "package", name, "Project.toml"))
        if startswith(line, "[")
            inside = line == section
        elseif inside
            m = match(r"^(Projectured\w*) = ", line)
            m === nothing || push!(packages, m.captures[1])
        end
    end
    packages
end

function test_umbrella_names_every_package()
    @testset "the umbrella loads every package of the flat namespace" begin
        repository = normpath(joinpath(@__DIR__, "..", ".."))
        flat = setdiff(_read_project_packages(repository, "ProjecturedAll", "[deps]"),
                       ["ProjecturedKernel", "ProjecturedPlatform"])
        adapters = ["ProjecturedAnthropic", "ProjecturedOllama", "ProjecturedOpenRouter"]
        code = "using Projectured; print(join(Projectured._INSTALLED_PACKAGES, ' '))"
        environment = joinpath(repository, "environment", "all")
        command = addenv(`$(Base.julia_cmd()) --startup-file=no --project=$environment -e $code`,
                         "JULIA_PKG_OFFLINE" => "true")
        installed = split(read(command, String))
        @test sort(installed) == sort([flat; adapters])
        # Each one is a weak dependency, for its `[compat]` bound.
        @test issubset(installed, _read_project_packages(repository, "Projectured", "[weakdeps]"))
    end
end
