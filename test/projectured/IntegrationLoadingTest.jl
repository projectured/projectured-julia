# A session loads the packages that it names, and nothing more. With the umbrella,
# AutoIntegration also loads each installed package whose triggers are loaded and
# whose state is "auto". Each case is a new Julia process that sees only one
# environment and the standard library: a scratch environment that names the
# packages of a user, or the development environment, which names every package.

const _UUIDS = Dict(
    "DataFrames"             => "a93c6f00-e57d-5684-b7b6-d8193f3e46c0",
    "Projectured"            => "92922de3-b970-4d9a-8b2a-9d6f361397b5",
    "ProjecturedDataFrames"  => "56a0c30a-96eb-4614-b42e-73838bfa8222",
    "ProjecturedIntegrations" => "12794e67-4fc4-4a27-b5bd-3fafde71a2fd",
    "ProjecturedJSON"        => "975d7430-285c-49f1-8705-4e3c002513ca",
    "ProjecturedSDL"         => "f0002b97-94ba-416c-b93c-86cdc095626f",
    "SimpleDirectMediaLayer" => "98e33af6-2ee5-5afd-9e75-cbc738b767c4")

const _INTEGRATION_NAMES = ("AutoIntegration", "Projectured", "ProjecturedACP", "ProjecturedAnthropic",
                            "ProjecturedDataFrames", "ProjecturedIntegrations", "ProjecturedJSON",
                            "ProjecturedMCP",
                            "ProjecturedODBC", "ProjecturedOllama", "ProjecturedOpenRouter",
                            "ProjecturedSDL", "ProjecturedTulip", "ProjecturedVideo",
                            "ProjecturedWeb")

# The packages of `_INTEGRATION_NAMES` that a new process with `environment` has
# loaded after `code`, and the text of its standard error.
function _read_loaded_integrations_and_errors(environment, code)
    report = """
        $code
        print(join(sort([package.name for package in keys(Base.loaded_modules)
                         if package.name in $(_INTEGRATION_NAMES)]), " "))
        """
    output = IOBuffer()
    errors = IOBuffer()
    command = addenv(`$(Base.julia_cmd()) --startup-file=no --project=$environment -e $report`,
                     "SDL_VIDEODRIVER" => "offscreen", "JULIA_PKG_OFFLINE" => "true",
                     "JULIA_LOAD_PATH" => "@" * (Sys.iswindows() ? ";" : ":") * "@stdlib")
    run(pipeline(command; stdout = output, stderr = errors))
    split(String(take!(output))), String(take!(errors))
end

_read_loaded_integrations(environment, code) =
    first(_read_loaded_integrations_and_errors(environment, code))

# An environment that names only the packages `names`: the manifest of the
# development environment with its paths made absolute, the packages of this
# repository and the sibling repositories that it names.
function _make_scratch_environment(repository, names)
    folder = mktempdir()
    development = joinpath(repository, "environment", "all")
    manifest = read(joinpath(development, "Manifest.toml"), String)
    write(joinpath(folder, "Manifest.toml"),
          replace(manifest, r"path = \"(\.\./[^\"]*)\"" =>
                            found -> "path = \"" * normpath(joinpath(development,
                                                    match(r"\"(.*)\"", found)[1])) * "\""))
    write(joinpath(folder, "Project.toml"),
          "[deps]\n" * join(["$name = \"$(_UUIDS[name])\"\n" for name in names]))
    folder
end

function test_umbrella_loads_integrations()
    @testset "the umbrella loads the installed packages whose triggers are loaded" begin
        repository = normpath(joinpath(@__DIR__, "..", ".."))
        user = _make_scratch_environment(repository,
            ["Projectured", "ProjecturedSDL", "ProjecturedDataFrames", "ProjecturedJSON",
             "DataFrames", "SimpleDirectMediaLayer"])

        # Without the umbrella, a session loads what it names and nothing more, and
        # the names that most users call come with the packages that it names.
        @test _read_loaded_integrations(user,
            "using DataFrames, ProjecturedSDL, ProjecturedDataFrames; " *
            "display_in_editor isa Function || error(\"display_in_editor is not visible\")") ==
              ["ProjecturedDataFrames", "ProjecturedSDL"]
        # With the umbrella, AutoIntegration loads the domain, and each integration
        # whose third-party package is loaded, in each order.
        both = ["AutoIntegration", "Projectured", "ProjecturedDataFrames", "ProjecturedJSON",
                "ProjecturedSDL"]
        @test _read_loaded_integrations(user,
            "using Projectured, DataFrames, SimpleDirectMediaLayer") == both
        @test _read_loaded_integrations(user,
            "using SimpleDirectMediaLayer; using DataFrames; using Projectured") == both
        # The umbrella alone loads the domain and no integration.
        @test _read_loaded_integrations(user, "using Projectured") ==
              ["AutoIntegration", "Projectured", "ProjecturedJSON"]

        # The environment of the user turns a package off.
        write(joinpath(user, "LocalPreferences.toml"), """
            [AutoIntegration]
            ProjecturedDataFrames = "manual"
            ProjecturedJSON = "manual"
            """)
        @test _read_loaded_integrations(user,
            "using Projectured, DataFrames, SimpleDirectMediaLayer") ==
              ["AutoIntegration", "Projectured", "ProjecturedSDL"]

        # An integration that the environment does not name stays out, with no
        # warning.
        loaded, errors = _read_loaded_integrations_and_errors(
            _make_scratch_environment(repository, ["Projectured", "SimpleDirectMediaLayer"]),
            "using SimpleDirectMediaLayer, Projectured")
        @test loaded == ["AutoIntegration", "Projectured"]
        @test !occursin("AutoIntegration", errors)

        # Each of the other triggers, in the development environment, where every
        # domain and model adapter loads with the umbrella. Video loads SDL, which
        # it needs. The web backend declares no trigger.
        @test _read_loaded_integrations(joinpath(repository, "environment", "all"),
            "using FFMPEG, ODBC, Tulip, ModelContextProtocol, Projectured") ==
              ["AutoIntegration", "Projectured", "ProjecturedAnthropic", "ProjecturedJSON",
               "ProjecturedMCP", "ProjecturedODBC", "ProjecturedOllama", "ProjecturedOpenRouter",
               "ProjecturedSDL", "ProjecturedTulip", "ProjecturedVideo"]
    end
end

function test_integrations_load_with_extensions()
    @testset "ProjecturedIntegrations loads each integration with a package extension" begin
        repository = normpath(joinpath(@__DIR__, "..", ".."))
        environment = _make_scratch_environment(repository,
                                                ["ProjecturedIntegrations", "DataFrames"])
        loaded = ["AutoIntegration", "Projectured", "ProjecturedDataFrames",
                  "ProjecturedIntegrations"]
        @test _read_loaded_integrations(environment,
            "using ProjecturedIntegrations, DataFrames") == loaded
        # Without the package that it joins, an integration does not load.
        @test _read_loaded_integrations(environment, "using ProjecturedIntegrations") ==
              ["AutoIntegration", "Projectured", "ProjecturedIntegrations"]
        # The extension loads an integration that the user sets to "manual".
        write(joinpath(environment, "LocalPreferences.toml"),
              "[AutoIntegration]\nProjecturedDataFrames = \"manual\"\n")
        @test _read_loaded_integrations(environment,
            "using ProjecturedIntegrations, DataFrames") == loaded
    end
end

# The packages that re-export the names of `ProjecturedPlatform.EssentialsModule`.
const _ESSENTIAL_NAME_PACKAGES = ("Projectured", "ProjecturedSDL", "ProjecturedDataFrames",
                                  "ProjecturedVideo", "ProjecturedODBC", "ProjecturedTulip",
                                  "ProjecturedMCP", "ProjecturedConsole", "ProjecturedPDF",
                                  "ProjecturedWeb", "ProjecturedIntegrations")

function test_essential_names()
    @testset "the umbrella, the integrations and the backends give the essential names" begin
        repository = normpath(joinpath(@__DIR__, "..", ".."))
        for name in _ESSENTIAL_NAME_PACKAGES
            @test name == "ProjecturedIntegrations" ||
                  "ProjecturedPlatform" in _read_project_packages(repository, name)
        end
        # Each package exports each name, bound to the same value.
        check = """
            import ProjecturedPlatform, $(join(_ESSENTIAL_NAME_PACKAGES, ", "))
            essentials = ProjecturedPlatform.EssentialsModule
            essential = filter(!=(:EssentialsModule), names(essentials))
            length(essential) == 12 || error("EssentialsModule exports \$(length(essential)) names")
            for package in ($(join(_ESSENTIAL_NAME_PACKAGES, ", "))), name in essential
                Base.isexported(package, name) &&
                    getfield(package, name) === getfield(essentials, name) ||
                    error("\$package does not give \$name")
            end
            """
        command = addenv(`$(Base.julia_cmd()) --startup-file=no --project=$(joinpath(repository, "environment", "all")) -e $check`,
                         "SDL_VIDEODRIVER" => "offscreen", "JULIA_PKG_OFFLINE" => "true",
                         "JULIA_LOAD_PATH" => "@" * (Sys.iswindows() ? ";" : ":") * "@stdlib")
        @test success(pipeline(command; stderr = stderr))
    end
end

# The `Projectured*` names under the heading `[deps]` of the `Project.toml` of
# the package `name`.
function _read_project_packages(repository, name)
    project = TOML.parsefile(joinpath(repository, "package", name, "Project.toml"))
    sort!([dependency for dependency in keys(get(project, "deps", Dict()))
           if startswith(dependency, "Projectured")])
end

# The names of the triggers that the package `name` declares for AutoIntegration,
# and its default.
function _read_declared_triggers(repository, name)
    project = TOML.parsefile(joinpath(repository, "package", name, "Project.toml"))
    declaration = get(project, "auto-integration", Dict())
    sort!(collect(keys(get(declaration, "triggers", Dict())))), get(declaration, "default", nothing)
end

function test_packages_declare_triggers()
    @testset "each package of the umbrella declares its triggers" begin
        repository = normpath(joinpath(@__DIR__, "..", ".."))
        # The domains, the console, PDF, the model adapters and the file watching
        # adapter load with the umbrella.
        alone = [setdiff(_read_project_packages(repository, "ProjecturedAll"),
                         ["ProjecturedKernel", "ProjecturedPlatform"]);
                 ["ProjecturedAnthropic", "ProjecturedOllama", "ProjecturedOpenRouter",
                  "ProjecturedFileWatching"]]
        for name in alone
            @test _read_declared_triggers(repository, name) == (["Projectured"], "auto")
        end
        # An integration loads with the umbrella and the package that it joins.
        for (name, joined) in ("ProjecturedSDL" => "SimpleDirectMediaLayer",
                               "ProjecturedDataFrames" => "DataFrames",
                               "ProjecturedVideo" => "FFMPEG", "ProjecturedODBC" => "ODBC",
                               "ProjecturedTulip" => "Tulip",
                               "ProjecturedMCP" => "ModelContextProtocol")
            @test _read_declared_triggers(repository, name) ==
                  (sort(["Projectured", joined]), "auto")
        end
        # A loaded web backend becomes the default backend when SDL is absent, so it
        # loads only by name.
        @test _read_declared_triggers(repository, "ProjecturedWeb") == (String[], nothing)
    end
end
