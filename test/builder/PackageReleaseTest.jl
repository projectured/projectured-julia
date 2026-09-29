# Tests for `build_package_release!` — the copy of the packages that a registry
# serves, and the scan that keeps every package inside its own folder.
#
# Nothing here compiles or registers. Every repository and every copy is a fresh
# temporary directory, except the last test set, which writes the release copy
# of this repository into one.
#
# TOML is reached through `ProjecturedBuilder`, because the test package that
# includes this file does not declare it.

using Test

# One package of a repository made for a test: `Project.toml`, an entry file that
# includes its slice the way the packages of this repository do, and the slice.
function _write_release_fixture_package(root, name, uuid; slice, code, dependencies = Pair{String,String}[])
    mkpath(joinpath(root, "package", name, "src"))
    project = Dict{String,Any}("name" => name, "uuid" => uuid, "version" => "0.1.0",
                               "deps" => Dict{String,Any}(dependencies))
    siblings = [dependency for (dependency, _) in dependencies if startswith(dependency, "Fake")]
    isempty(siblings) ||
        (project["sources"] = Dict{String,Any}(dependency => Dict("path" => "../$dependency")
                                               for dependency in siblings))
    open(io -> ProjecturedBuilder.TOML.print(io, project),
         joinpath(root, "package", name, "Project.toml"), "w")
    write(joinpath(root, "package", name, "src", "$name.jl"),
          "module $name\ninclude(\"../../../source/$slice/$(name)Code.jl\")\nend\n")
    mkpath(joinpath(root, "source", slice))
    write(joinpath(root, "source", slice, "$(name)Code.jl"), code)
end

# Git tracks every file of the made repository, as it tracks the files of this
# one. The release copy takes only tracked files.
_track_release_fixture(root) = run(`git -C $root add -A`)

# A git repository with two packages. `FakeBase` reads a folder of the repository
# while it runs. `FakeTop` depends on `FakeBase`, on a registered package and on
# a standard library.
function _make_release_repository()
    root = mktempdir()
    run(`git -C $root init -q`)
    write(joinpath(root, "LICENSE"), "the licence\n")
    mkpath(joinpath(root, "asset", "thing"))
    write(joinpath(root, "asset", "thing", "data.txt"), "data\n")
    _write_release_fixture_package(root, "FakeBase", "00000000-0000-0000-0000-00000000000b";
        slice = "fakebase",
        code = "const THING = joinpath(@__DIR__, \"..\", \"..\", \"asset\", \"thing\")\n")
    _write_release_fixture_package(root, "FakeTop", "00000000-0000-0000-0000-00000000000c";
        slice = "faketop", code = "top() = 1\n",
        dependencies = ["FakeBase" => "00000000-0000-0000-0000-00000000000b",
                        "Registered" => "00000000-0000-0000-0000-00000000000d",
                        "Dates" => "ade2ca70-3891-5945-98fb-dc099432e06a"])
    mkpath(joinpath(root, "environment"))
    write(joinpath(root, "environment", "Manifest.toml"), """
        [[deps.Registered]]
        git-tree-sha1 = "0000000000000000000000000000000000000000"
        uuid = "00000000-0000-0000-0000-00000000000d"
        version = "1.2.3+0"

        [[deps.Dates]]
        uuid = "ade2ca70-3891-5945-98fb-dc099432e06a"
        version = "1.11.0"
        """)
    _track_release_fixture(root)
    root
end

# A registry folder that holds `versions`, `"<name>" => ["<version>", …]`, of the
# two packages of the made repository, in the layout that Pkg reads.
function _write_release_fixture_registry(folder, versions)
    uuids = Dict("FakeBase" => "00000000-0000-0000-0000-00000000000b",
                 "FakeTop" => "00000000-0000-0000-0000-00000000000c")
    packages = Dict{String,Any}()
    for (name, released) in versions
        packages[uuids[name]] = Dict("name" => name, "path" => "F/$name")
        mkpath(joinpath(folder, "F", name))
        open(io -> ProjecturedBuilder.TOML.print(io, Dict("name" => name, "uuid" => uuids[name],
                                                          "repo" => "file:///release")),
             joinpath(folder, "F", name, "Package.toml"), "w")
        open(io -> ProjecturedBuilder.TOML.print(io, Dict(version => Dict("git-tree-sha1" => "0"^40)
                                                          for version in released)),
             joinpath(folder, "F", name, "Versions.toml"), "w")
    end
    open(io -> ProjecturedBuilder.TOML.print(io, Dict("name" => "FakeRegistry",
                                                      "uuid" => "00000000-0000-0000-0000-0000000000ff",
                                                      "repo" => "file:///registry",
                                                      "packages" => packages)),
         joinpath(folder, "Registry.toml"), "w")
    folder
end

# Every file of a folder with its bytes, so that two states of a folder compare
# whole.
_read_release_folder(folder) =
    Dict(relpath(joinpath(directory, file), folder) => read(joinpath(directory, file))
         for (directory, _, files) in walkdir(folder) for file in files)

# The message of the error that `action` throws, or "" when it throws none.
function _read_release_error(action)
    try
        action()
        ""
    catch exception
        sprint(showerror, exception)
    end
end

function test_package_release()
    @testset "package release" begin
        root = _make_release_repository()
        context = BuildContext(root)
        output = joinpath(mktempdir(), "Release.jl")
        manifest = joinpath(root, "environment", "Manifest.toml")
        release(; into = output) =
            build_package_release!(context; packages = ["FakeTop", "FakeBase"], output = into,
                                   assets = Dict("FakeBase" => ["asset/thing" => "asset/thing"]),
                                   licences = ["LICENSE"], readme = name -> "# $name\n", manifest)
        read_project(name) = ProjecturedBuilder.TOML.parsefile(joinpath(output, "$name.jl", "Project.toml"))
        commit(repository) = run(`git -C $repository -c user.name=test
                                  -c user.email=test@example.org commit -q -m release`)

        @testset "the first release copies every package into a repository of its own" begin
            results = release()
            @test [result.name for result in results] == ["FakeBase", "FakeTop"]
            @test all(result -> result.status === :new && result.version == v"0.1.0", results)
            top = read_project("FakeTop")
            @test !haskey(top, "sources")
            # The registered version without its build suffix, which a
            # `[compat]` entry can not name; no bound on a standard library.
            @test top["compat"] == Dict("FakeBase" => "0.1.0", "Registered" => "1.2.3",
                                        "julia" => "1.11")
            # `<Name>.jl` with the package at its root: the name that a
            # registry expects of the repository of a package.
            @test sort(readdir(output)) == ["FakeBase.jl", "FakeTop.jl"]
            @test occursin("include(\"../source/faketop/FakeTopCode.jl\")",
                           read(joinpath(output, "FakeTop.jl", "src", "FakeTop.jl"), String))
            @test isfile(joinpath(output, "FakeTop.jl", "source", "faketop", "FakeTopCode.jl"))
            @test isfile(joinpath(output, "FakeBase.jl", "asset", "thing", "data.txt"))
            @test !isdir(joinpath(output, "FakeTop.jl", "asset"))
            for name in ("FakeBase", "FakeTop")
                @test read(joinpath(output, "$name.jl", "LICENSE"), String) == "the licence\n"
                @test read(joinpath(output, "$name.jl", "README.md"), String) == "# $name\n"
            end
        end

        @testset "a release with no change keeps every folder and every version" begin
            before = _read_release_folder(output)
            # A file that git does not track never reaches the copy.
            write(joinpath(root, "source", "faketop", "FakeTopCode.jl.1234.cov"), "coverage\n")
            results = release()
            @test all(result -> result.status === :unchanged && result.version == v"0.1.0", results)
            @test _read_release_folder(output) == before
            rm(joinpath(root, "source", "faketop", "FakeTopCode.jl.1234.cov"))
        end

        @testset "a change gives a new version to the package that changed, and only to it" begin
            write(joinpath(root, "source", "faketop", "FakeTopCode.jl"), "top() = 2\n")
            results = Dict(result.name => result for result in release())
            @test results["FakeBase"].status === :unchanged
            @test results["FakeTop"].status === :changed
            @test results["FakeTop"].version == v"0.1.1"
            @test read_project("FakeTop")["version"] == "0.1.1"

            # A change below a package that did not change leaves that package as
            # it is, `[compat]` included, so the change gives it no new version.
            write(joinpath(root, "source", "fakebase", "FakeBaseCode.jl"),
                  "const THING = joinpath(@__DIR__, \"..\", \"..\", \"asset\", \"thing\")\nbase() = 1\n")
            results = Dict(result.name => result for result in release())
            @test results["FakeBase"].status === :changed
            @test results["FakeBase"].version == v"0.1.1"
            @test results["FakeTop"].status === :unchanged
            @test read_project("FakeTop")["compat"]["FakeBase"] == "0.1.0"

            # A package that changes after that bounds its siblings by their
            # versions in this release.
            write(joinpath(root, "source", "faketop", "FakeTopCode.jl"), "top() = 3\n")
            results = Dict(result.name => result for result in release())
            @test results["FakeTop"].version == v"0.1.2"
            @test read_project("FakeTop")["compat"]["FakeBase"] == "0.1.1"
        end

        @testset "the scan finds a path that leaves the package folder" begin
            folder = mktempdir()
            write(joinpath(folder, "Reads.jl"), """
                const INSIDE = joinpath(@__DIR__, "Reads.jl")
                const OUTSIDE = joinpath(@__DIR__, "..", "elsewhere")
                const MISSING = joinpath(@__DIR__, "nothing-here")
                const BARE = @__DIR__
                include("Reads.jl")
                include("../Other.jl")
                include(dynamic_path)
                const BY_FILE = joinpath(dirname(@__FILE__), "..", "example")
                Base.include(@__MODULE__, "../Other.jl")
                include(identity, "../Other.jl")
                const BY_PACKAGE = joinpath(pkgdir(@__MODULE__), "asset")
                include(joinpath("..", "Other.jl"))
                const QUALIFIED = joinpath(Base.@__DIR__, "..", "elsewhere")
                const FILE = @__FILE__
                """)
            found = collect_outside_paths(folder)
            @test sort([path.line for path in found]) == [2, 3, 4, 6, 8, 9, 10, 11, 12, 13, 14]
            @test all(path -> path.file == joinpath(folder, "Reads.jl"), found)
        end

        @testset "a release that fails leaves the copy as it was" begin
            before = _read_release_folder(output)
            write(joinpath(root, "source", "fakebase", "FakeBaseCode.jl"),
                  "const THING = joinpath(@__DIR__, \"..\", \"..\", \"asset\", \"thing\")\nbase() = 2\n")
            write(joinpath(root, "source", "faketop", "Escape.jl"),
                  "const SECRET = joinpath(@__DIR__, \"..\", \"..\", \"..\", \"secret\")\n")
            _track_release_fixture(root)
            message = _read_release_error(release)
            @test occursin("FakeTop reads outside its folder", message)
            @test occursin("Escape.jl:1", message)
            # `FakeBase` comes first and changed, and still nothing was written.
            @test _read_release_folder(output) == before
            rm(joinpath(root, "source", "faketop", "Escape.jl"))
            _track_release_fixture(root)

            # A folder that the package reads and the release does not copy.
            message = _read_release_error(() -> build_package_release!(context;
                packages = ["FakeTop", "FakeBase"], output = joinpath(mktempdir(), "Release.jl"),
                manifest))
            @test occursin("FakeBase reads outside its folder", message)
        end

        @testset "a release keeps the git history of each repository, and refuses a change that is not committed" begin
            committed = joinpath(mktempdir(), "Release")
            release(; into = committed)
            for name in ("FakeBase", "FakeTop")
                repository = joinpath(committed, "$name.jl")
                run(`git -C $repository init -q`)
                run(`git -C $repository add -A`)
                commit(repository)
            end
            @test all(result -> result.status === :unchanged, release(; into = committed))

            # A change replaces the files of the repository and keeps its `.git`,
            # so git shows what the release changed.
            write(joinpath(root, "source", "faketop", "FakeTopCode.jl"), "top() = 4\n")
            results = Dict(result.name => result for result in release(; into = committed))
            @test results["FakeTop"].status === :changed
            changes = read(`git -C $(joinpath(committed, "FakeTop.jl")) status --porcelain`, String)
            @test occursin("source/faketop/FakeTopCode.jl", changes)
            @test occursin("Project.toml", changes)
            @test isempty(read(`git -C $(joinpath(committed, "FakeBase.jl")) status --porcelain`, String))

            # Until that change is committed, the next release is refused.
            @test occursin("changes that are not committed",
                           _read_release_error(() -> release(; into = committed)))
        end

        @testset "a release stops while the last one is not registered" begin
            # The copy of the first release holds FakeBase and FakeTop at 0.1.0.
            first_release = joinpath(mktempdir(), "Release.jl")
            release(; into = first_release)
            again(registry) = build_package_release!(context; packages = ["FakeTop", "FakeBase"],
                output = first_release, assets = Dict("FakeBase" => ["asset/thing" => "asset/thing"]),
                licences = ["LICENSE"], readme = name -> "# $name\n", manifest, registry)
            partial = _write_release_fixture_registry(mktempdir(), ["FakeBase" => ["0.1.0"]])
            message = _read_release_error(() -> again(partial))
            @test occursin("Register them first", message)
            @test occursin("FakeTop 0.1.0", message) && !occursin("FakeBase 0.1.0", message)
            complete = _write_release_fixture_registry(mktempdir(),
                ["FakeBase" => ["0.1.0"], "FakeTop" => ["0.1.0"]])
            @test all(result -> result.status === :unchanged, again(complete))
            @test occursin("no registry called",
                           _read_release_error(() -> again("NoSuchRegistry")))
            # A first release needs no registry at all.
            @test length(build_package_release!(context; packages = ["FakeTop", "FakeBase"],
                output = joinpath(mktempdir(), "Release.jl"),
                assets = Dict("FakeBase" => ["asset/thing" => "asset/thing"]),
                licences = ["LICENSE"], manifest, registry = "NoSuchRegistry")) == 2
        end

        @testset "a release that leaves out a dependency, a licence or the manifest, stops" begin
            message = _read_release_error(() -> build_package_release!(context;
                packages = ["FakeTop"], output = joinpath(mktempdir(), "Release.jl"), manifest))
            @test occursin("FakeTop → FakeBase", message)
            message = _read_release_error(() -> build_package_release!(context;
                packages = ["FakeBase"], output = joinpath(mktempdir(), "Release.jl"),
                assets = Dict("FakeBase" => ["asset/thing" => "asset/thing"]),
                licences = ["LICENCE-MISSING"], manifest))
            @test occursin("no licence file", message)
            message = _read_release_error(() -> build_package_release!(context;
                packages = ["FakeBase"], output = joinpath(mktempdir(), "Release.jl"),
                assets = Dict("FakeBase" => ["asset/thing" => "asset/thing"]),
                manifest = joinpath(root, "no-such-manifest.toml")))
            @test occursin("no manifest", message)
        end

        rm(root; recursive = true)
    end

    @testset "the release copy of this repository" begin
        context = BuildContext(normpath(joinpath(@__DIR__, "..", "..")))
        names = collect_projectured_release_packages(context)
        @test "ProjecturedKernel" in names && "Projectured" in names
        @test !any(name -> endswith(name, "Test") || endswith(name, "Example"), names)
        @test isempty(intersect(names, PROJECTURED_RELEASE_EXCLUSIONS))
        # Closed: every sibling that a released package depends on is released.
        for name in names
            project = ProjecturedBuilder.TOML.parsefile(joinpath(get_package_directory(context, name),
                                                                 "Project.toml"))
            for dependency in keys(get(project, "deps", Dict{String,Any}()))
                has_package_directory(context, dependency) || continue
                @test dependency in names
            end
        end
        for name in keys(PROJECTURED_PACKAGE_ASSETS)
            @test name in names
        end
        # The scan passes on the code as it is, so a path that leaves a package
        # shows here and not at the release.
        output = joinpath(mktempdir(get_staging_root()), "Projectured.jl")
        results = build_projectured_package_release!(output; context)
        @test length(results) == length(names)
        @test all(result -> result.status === :new, results)
        rm(dirname(output); recursive = true)
    end
end
