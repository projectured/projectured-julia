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
function _write_release_fixture_package(root, name, uuid;
                                        slice, code, dependencies = Pair{String,String}[])
    mkpath(joinpath(root, "package", name, "src"))
    project = Dict{String,Any}("name" => name, "uuid" => uuid, "version" => "0.1.0",
                               "deps" => Dict{String,Any}(dependencies))
    siblings = [dependency for (dependency, _) in dependencies
                if startswith(dependency, "Fake")]
    isempty(siblings) ||
        (project["sources"] = Dict{String,Any}(dependency =>
                                               Dict("path" => "../$dependency")
                                               for dependency in siblings))
    open(io -> ProjecturedBuilder.BuilderModule.TOML.print(io, project),
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
    _write_release_fixture_package(root, "FakeBase",
        "00000000-0000-0000-0000-00000000000b";
        slice = "fakebase",
        code = "const THING = joinpath(@__DIR__, \"..\", \"..\", \"asset\", \"thing\")\n")
    _write_release_fixture_package(root, "FakeTop",
        "00000000-0000-0000-0000-00000000000c";
        slice = "faketop", code = "top() = 1\n",
        dependencies = ["FakeBase" => "00000000-0000-0000-0000-00000000000b",
                        "Registered" => "00000000-0000-0000-0000-00000000000d",
                        "Dates" => "ade2ca70-3891-5945-98fb-dc099432e06a"])
    _write_release_fixture_extension(root)
    # The recorded precompile statements of `FakeTop`, which AutoPrecompile reads
    # from the folder of a loaded package.
    mkpath(joinpath(root, "package", "FakeTop", "precompile"))
    write(joinpath(root, "package", "FakeTop", "precompile", "scenario.txt"),
          "Tuple{typeof(FakeTop.top)}\n")
    _write_release_fixture_tests(root)
    mkpath(joinpath(root, "environment"))
    write(joinpath(root, "environment", "Manifest.toml"), """
        [[deps.Registered]]
        git-tree-sha1 = "0000000000000000000000000000000000000000"
        uuid = "00000000-0000-0000-0000-00000000000d"
        version = "1.2.3+0"

        [[deps.WeakTrigger]]
        git-tree-sha1 = "0000000000000000000000000000000000000001"
        uuid = "00000000-0000-0000-0000-000000000010"
        version = "2.0.0"

        [[deps.Dates]]
        uuid = "ade2ca70-3891-5945-98fb-dc099432e06a"
        version = "1.11.0"
        """)
    _track_release_fixture(root)
    root
end

# An extension of `FakeTop` that a registered package triggers, as the umbrella of
# this repository has.
function _write_release_fixture_extension(root)
    path = joinpath(root, "package", "FakeTop", "Project.toml")
    project = ProjecturedBuilder.BuilderModule.TOML.parsefile(path)
    project["weakdeps"] = Dict{String,Any}("WeakTrigger" => "00000000-0000-0000-0000-000000000010")
    project["extensions"] = Dict{String,Any}("FakeTopWeakTriggerExt" => "WeakTrigger")
    open(io -> ProjecturedBuilder.BuilderModule.TOML.print(io, project), path, "w")
    mkpath(joinpath(root, "package", "FakeTop", "ext"))
    write(joinpath(root, "package", "FakeTop", "ext", "FakeTopWeakTriggerExt.jl"),
          "module FakeTopWeakTriggerExt end\n")
end

# The test package of `FakeTop` and an example package it needs, which no release
# holds. The suite includes its files from `test/` and the example package from
# `example/`, as the test packages of this repository do, and a test reads a file
# beside it while it runs.
function _write_release_fixture_tests(root)
    for (name, uuid, dependencies, folder, file, code) in (
            ("FakeTopExample", "00000000-0000-0000-0000-00000000000e",
             ["FakeTop" => "00000000-0000-0000-0000-00000000000c"],
             "example/faketop", "FakeTopExamples.jl", "make_top_example() = 1\n"),
            ("FakeTopTest", "00000000-0000-0000-0000-00000000000f",
             ["FakeTop" => "00000000-0000-0000-0000-00000000000c",
              "FakeTopExample" => "00000000-0000-0000-0000-00000000000e",
              "Test" => "8dfed614-e22c-5e08-85e1-65c5234f0b40"],
             "test/faketop", "FakeTopSuite.jl",
             "const DATA = joinpath(@__DIR__, \"data.txt\")\ntest_faketop() = nothing\n"))
        mkpath(joinpath(root, "package", name, "src"))
        project = Dict{String,Any}("name" => name, "uuid" => uuid, "version" => "0.1.0",
                                   "deps" => Dict{String,Any}(dependencies),
                                   "sources" => Dict{String,Any}(
                                       dependency => Dict("path" => "../$dependency")
                                       for (dependency, _) in dependencies
                                       if startswith(dependency, "Fake")))
        open(io -> ProjecturedBuilder.BuilderModule.TOML.print(io, project),
             joinpath(root, "package", name, "Project.toml"), "w")
        write(joinpath(root, "package", name, "src", "$name.jl"),
              "module $name\ninclude(\"../../../$folder/$file\")\nend\n")
        mkpath(joinpath(root, folder))
        write(joinpath(root, folder, file), code)
    end
    write(joinpath(root, "test", "faketop", "data.txt"), "data\n")
end

# The suite that tests a released package of the made repository.
_find_release_fixture_test(name) =
    name == "FakeTop" ? ("FakeTopTest" => "using FakeTopTest\ntest_faketop()\n") : nothing

# The workflow of the made repository: one line for each job, its package, the
# folders it develops and the folders of its coverage.
_format_release_fixture_workflow(jobs) =
    join(["$(job.name): $(join(job.develop, ' ')) | $(join(job.coverage, ' '))\n"
          for job in jobs])

# A registry folder that holds `versions`, `"<name>" => ["<version>", …]`, of the
# two packages of the made repository, in the layout that Pkg reads.
function _write_release_fixture_registry(folder, versions)
    uuids = Dict("FakeBase" => "00000000-0000-0000-0000-00000000000b",
                 "FakeTop" => "00000000-0000-0000-0000-00000000000c")
    packages = Dict{String,Any}()
    for (name, released) in versions
        packages[uuids[name]] = Dict("name" => name, "path" => "F/$name")
        mkpath(joinpath(folder, "F", name))
        open(io -> ProjecturedBuilder.BuilderModule.TOML.print(io,
                  Dict("name" => name, "uuid" => uuids[name],
                       "repo" => "file:///release")),
             joinpath(folder, "F", name, "Package.toml"), "w")
        open(io -> ProjecturedBuilder.BuilderModule.TOML.print(io,
                  Dict(version => Dict("git-tree-sha1" => "0"^40)
                       for version in released)),
             joinpath(folder, "F", name, "Versions.toml"), "w")
    end
    open(io -> ProjecturedBuilder.BuilderModule.TOML.print(io,
              Dict("name" => "FakeRegistry",
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
            build_package_release!(context;
                packages = ["FakeTop", "FakeBase"], output = into,
                assets = Dict("FakeBase" => ["asset/thing" => "asset/thing"]),
                licences = ["LICENSE"], readme = name -> "# $name\n",
                tests = _find_release_fixture_test,
                workflow = _format_release_fixture_workflow, manifest)
        read_project(name) =
            ProjecturedBuilder.BuilderModule.TOML.parsefile(joinpath(output, name,
                                                       "Project.toml"))
        commit(repository) = run(`git -C $repository -c user.name=test
                                  -c user.email=test@example.org commit -q -m release`)

        @testset "the first release copies every package into a folder of its own" begin
            results = release()
            @test [result.name for result in results] ==
                  ["FakeBase", "FakeTop", "FakeTopExample", "FakeTopTest"]
            @test [result.folder for result in results] ==
                  ["FakeBase", "FakeTop", "example/FakeTopExample", "test/FakeTopTest"]
            @test all(result -> result.status === :new && result.version == v"0.1.0",
                      results)
            top = read_project("FakeTop")
            @test !haskey(top, "sources")
            # The registered version without its build suffix, which a
            # `[compat]` entry can not name; no bound on a standard library; and a
            # bound on the weak dependency of the extension too.
            @test top["compat"] == Dict("FakeBase" => "0.1.0", "Registered" => "1.2.3",
                                        "WeakTrigger" => "2.0.0", "julia" => "1.11")
            @test top["extensions"] == Dict("FakeTopWeakTriggerExt" => "WeakTrigger")
            @test isfile(joinpath(output, "FakeTop", "ext", "FakeTopWeakTriggerExt.jl"))
            @test read(joinpath(output, "FakeTop", "precompile", "scenario.txt"), String) ==
                  "Tuple{typeof(FakeTop.top)}\n"
            @test !isdir(joinpath(output, "FakeBase", "precompile"))
            # One folder for each package, the support packages in `test/` and
            # `example/`, and the licence files and the workflow at the root.
            @test sort(readdir(output)) ==
                  [".github", "FakeBase", "FakeTop", "LICENSE", "example", "test"]
            # The slice is under `src/`, at the depth that `source/` has.
            @test occursin("include(\"faketop/FakeTopCode.jl\")",
                           read(joinpath(output, "FakeTop", "src", "FakeTop.jl"), String))
            @test isfile(joinpath(output, "FakeTop", "src", "faketop", "FakeTopCode.jl"))
            @test !isdir(joinpath(output, "FakeTop", "source"))
            @test isfile(joinpath(output, "FakeBase", "asset", "thing", "data.txt"))
            @test !isdir(joinpath(output, "FakeTop", "asset"))
            @test read(joinpath(output, "LICENSE"), String) == "the licence\n"
            for name in ("FakeBase", "FakeTop")
                @test read(joinpath(output, name, "LICENSE"), String) == "the licence\n"
                @test read(joinpath(output, name, "README.md"), String) == "# $name\n"
            end
        end

        @testset "a package gets the suite of its test package, which the release holds once" begin
            test = joinpath(output, "FakeTop", "test")
            @test read(joinpath(test, "runtests.jl"), String) ==
                  "using FakeTopTest\ntest_faketop()\n"
            @test sort(readdir(test)) == ["Project.toml", "runtests.jl"]
            # `test/Project.toml` names the test package, which a registry serves.
            project = ProjecturedBuilder.BuilderModule.TOML.parsefile(
                joinpath(test, "Project.toml"))
            @test project == Dict("deps" => Dict("FakeTopTest" =>
                                                 "00000000-0000-0000-0000-00000000000f"))
            # A support package is a package of the release: a version, bounds on
            # what it depends on, the licence, and no `[sources]`.
            support = read_project(joinpath("test", "FakeTopTest"))
            @test !haskey(support, "sources")
            @test support["version"] == "0.1.0"
            @test support["compat"]["FakeTop"] == "0.1.0" &&
                  support["compat"]["FakeTopExample"] == "0.1.0"
            @test isfile(joinpath(output, "test", "FakeTopTest", "LICENSE"))
            # The include prefix of the repository becomes one of the copy, and the
            # folders it names come along, the file a test reads included.
            @test occursin("include(\"../test/faketop/FakeTopSuite.jl\")",
                           read(joinpath(output, "test", "FakeTopTest", "src",
                                         "FakeTopTest.jl"), String))
            @test isfile(joinpath(output, "test", "FakeTopTest", "test", "faketop",
                                  "data.txt"))
            @test isfile(joinpath(output, "example", "FakeTopExample", "example", "faketop",
                                  "FakeTopExamples.jl"))
            @test !isdir(joinpath(output, "FakeBase", "test"))
        end

        @testset "the workflow tests each package that has tests, with the folders its test needs" begin
            # `FakeBase` has no tests, so no job; `FakeTop` develops the sibling it
            # depends on, then its support packages, and its code is in three
            # folders.
            @test readdir(joinpath(output, ".github", "workflows")) == ["FakeTop.yml"]
            @test read(joinpath(output, ".github", "workflows", "FakeTop.yml"), String) ==
                  "FakeTop: FakeBase FakeTop example/FakeTopExample test/FakeTopTest | " *
                  "FakeTop/src FakeTop/ext\n"

            # A released package that only a support package names is developed
            # too, and one that nothing names is not.
            folder = mktempdir()
            write_project(path, dependencies) =
                (mkpath(dirname(path));
                 open(io -> ProjecturedBuilder.BuilderModule.TOML.print(io,
                           Dict("deps" => Dict(name => "" for name in dependencies))),
                      path, "w"))
            write_project(joinpath(folder, "Low", "Project.toml"), String[])
            write_project(joinpath(folder, "Middle", "Project.toml"), ["Low"])
            write_project(joinpath(folder, "Other", "Project.toml"), String[])
            write_project(joinpath(folder, "Top", "Project.toml"), String[])
            write_project(joinpath(folder, "Top", "test", "Project.toml"), ["TopTest"])
            write_project(joinpath(folder, "test", "TopTest", "Project.toml"),
                          ["Top", "Middle", "Test"])
            folders = Dict("Low" => "Low", "Middle" => "Middle", "Other" => "Other",
                           "Top" => "Top", "TopTest" => joinpath("test", "TopTest"))
            @test ProjecturedBuilder.BuilderModule._collect_release_test_closure(
                      folder, "Top", ["Low", "Middle", "Other", "Top", "TopTest"], folders) ==
                  ["Low", "Middle", "Top", joinpath("test", "TopTest")]
        end

        @testset "the overview is the front page of the release repository" begin
            front = joinpath(mktempdir(), "Release.jl")
            build_package_release!(context; packages = ["FakeTop", "FakeBase"], output = front,
                assets = Dict("FakeBase" => ["asset/thing" => "asset/thing"]),
                licences = ["LICENSE"], overview = names -> "# Release\n$(join(names, ' '))\n",
                manifest)
            @test read(joinpath(front, "README.md"), String) == "# Release\nFakeBase FakeTop\n"
        end

        @testset "a release with no change keeps every folder and every version" begin
            before = _read_release_folder(output)
            # A file that git does not track never reaches the copy.
            write(joinpath(root, "source", "faketop", "FakeTopCode.jl.1234.cov"),
                  "coverage\n")
            results = release()
            @test all(result -> result.status === :unchanged &&
                                 result.version == v"0.1.0", results)
            @test _read_release_folder(output) == before
            rm(joinpath(root, "source", "faketop", "FakeTopCode.jl.1234.cov"))
        end

        @testset "a change of a test gives the test package a new version, and no other" begin
            before = _read_release_folder(joinpath(output, "FakeTop"))
            write(joinpath(root, "test", "faketop", "FakeTopSuite.jl"),
                  "const DATA = joinpath(@__DIR__, \"data.txt\")\ntest_faketop() = 1\n")
            _track_release_fixture(root)
            results = Dict(result.name => result for result in release())
            @test results["FakeTopTest"].status === :changed
            @test results["FakeTopTest"].version == v"0.1.1"
            @test all(name -> results[name].status === :unchanged,
                      ("FakeBase", "FakeTop", "FakeTopExample"))
            # The released folder keeps the tests of its version.
            @test _read_release_folder(joinpath(output, "FakeTop")) == before
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
                  "const THING = joinpath(@__DIR__, \"..\", \"..\", " *
                  "\"asset\", \"thing\")\nbase() = 1\n")
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

        @testset "a package that no longer exports a name takes a minor step, and the package above a new bound" begin
            write(joinpath(root, "source", "fakebase", "FakeBaseCode.jl"),
                  "const THING = joinpath(@__DIR__, \"..\", \"..\", \"asset\", \"thing\")\n" *
                  "export base\nbase() = 1\n")
            results = Dict(result.name => result for result in release())
            exported = results["FakeBase"].version
            @test exported.minor == 1 && exported.patch > 0
            top = results["FakeTop"].version
            write(joinpath(root, "source", "fakebase", "FakeBaseCode.jl"),
                  "const THING = joinpath(@__DIR__, \"..\", \"..\", \"asset\", \"thing\")\n" *
                  "export foundation\nfoundation() = 1\n")
            results = Dict(result.name => result for result in release())
            @test results["FakeBase"].version == v"0.2.0"
            @test results["FakeTop"].status === :changed
            @test results["FakeTop"].version == VersionNumber(top.major, top.minor, top.patch + 1)
            @test read_project("FakeTop")["compat"]["FakeBase"] == "0.2.0"
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
            @test sort([path.line for path in found]) ==
                  [2, 3, 4, 6, 8, 9, 10, 11, 12, 13, 14]
            @test all(path -> path.file == joinpath(folder, "Reads.jl"), found)
        end

        @testset "a release that fails leaves the copy as it was" begin
            before = _read_release_folder(output)
            write(joinpath(root, "source", "fakebase", "FakeBaseCode.jl"),
                  "const THING = joinpath(@__DIR__, \"..\", \"..\", " *
                  "\"asset\", \"thing\")\nbase() = 2\n")
            write(joinpath(root, "source", "faketop", "Escape.jl"),
                  "const SECRET = joinpath(@__DIR__, \"..\", \"..\", \"..\", " *
                  "\"secret\")\n")
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
                packages = ["FakeTop", "FakeBase"],
                output = joinpath(mktempdir(), "Release.jl"),
                manifest))
            @test occursin("FakeBase reads outside its folder", message)
        end

        @testset "a release keeps the history of the repository and the files it does not own, and refuses a change that is not committed" begin
            committed = joinpath(mktempdir(), "Release.jl")
            release(; into = committed)
            # A file at the root that the release does not write.
            write(joinpath(committed, "README.md"), "the release repository\n")
            run(`git -C $committed init -q`)
            run(`git -C $committed add -A`)
            commit(committed)
            @test all(result -> result.status === :unchanged, release(; into = committed))

            # A change replaces the folder of the package that changed, and
            # nothing else, so git shows what the release changed.
            write(joinpath(root, "source", "faketop", "FakeTopCode.jl"), "top() = 4\n")
            results = Dict(result.name => result
                           for result in release(; into = committed))
            @test results["FakeTop"].status === :changed
            changes = sort(split(read(`git -C $committed status --porcelain`, String),
                                 "\n"; keepempty = false))
            @test changes == [" M FakeTop/Project.toml",
                              " M FakeTop/src/faketop/FakeTopCode.jl"]
            @test read(joinpath(committed, "README.md"), String) ==
                  "the release repository\n"

            # Until that change is committed, the next release is refused.
            @test occursin("changes that are not committed",
                           _read_release_error(() -> release(; into = committed)))
        end

        @testset "a release stops while the last one is not registered" begin
            # The copy of the first release holds FakeBase and FakeTop at 0.1.0.
            first_release = joinpath(mktempdir(), "Release.jl")
            release(; into = first_release)
            again(registry) =
                build_package_release!(context; packages = ["FakeTop", "FakeBase"],
                    output = first_release,
                    assets = Dict("FakeBase" => ["asset/thing" => "asset/thing"]),
                    licences = ["LICENSE"], readme = name -> "# $name\n", manifest,
                    registry)
            partial = _write_release_fixture_registry(mktempdir(),
                                                      ["FakeBase" => ["0.1.0"]])
            message = _read_release_error(() -> again(partial))
            @test occursin("Register them first", message)
            @test occursin("FakeTop 0.1.0", message) &&
                  !occursin("FakeBase 0.1.0", message)
            complete = _write_release_fixture_registry(mktempdir(),
                ["FakeBase" => ["0.1.0"], "FakeTop" => ["0.1.0"]])
            @test all(result -> result.status === :unchanged, again(complete))
            @test occursin("no registry called",
                           _read_release_error(() -> again("NoSuchRegistry")))
            # A first release needs no registry at all.
            @test length(build_package_release!(context;
                packages = ["FakeTop", "FakeBase"],
                output = joinpath(mktempdir(), "Release.jl"),
                assets = Dict("FakeBase" => ["asset/thing" => "asset/thing"]),
                licences = ["LICENSE"], manifest, registry = "NoSuchRegistry")) == 2
        end

        @testset "a release that leaves out a dependency, a licence or the manifest, stops" begin
            message = _read_release_error(() -> build_package_release!(context;
                packages = ["FakeTop"],
                output = joinpath(mktempdir(), "Release.jl"), manifest))
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
        context = BuildContext(normpath(joinpath(@__DIR__, "..", "..", "..")))
        names = collect_projectured_release_packages(context)
        @test "ProjecturedKernel" in names && "Projectured" in names
        @test !any(name -> endswith(name, "Test") || endswith(name, "Example"), names)
        @test isempty(intersect(names, PROJECTURED_RELEASE_EXCLUSIONS))
        # Closed: every sibling that a released package depends on is released.
        for name in names
            project = ProjecturedBuilder.BuilderModule.TOML.parsefile(
                joinpath(get_package_directory(context, name), "Project.toml"))
            for dependency in keys(get(project, "deps", Dict{String,Any}()))
                has_package_directory(context, dependency) || continue
                @test dependency in names
            end
        end
        # A package of the table is released, or a package that a released test
        # needs.
        for name in keys(PROJECTURED_PACKAGE_ASSETS)
            @test has_package_directory(context, name)
        end
        # The scan passes on the code as it is, so a path that leaves a package
        # shows here and not at the release.
        output = joinpath(mktempdir(get_staging_root()), "Projectured.jl")
        results = build_projectured_package_release!(output; context)
        @test count(result -> result.folder == result.name, results) == length(names)
        # Each test and example package that a test needs is released once.
        @test all(result -> result.folder == result.name ||
                            startswith(result.folder, "test/") ||
                            startswith(result.folder, "example/"), results)
        @test !any(name -> isdir(joinpath(output, name, "test", "support")), names)
        # A released package carries its statement files, which AutoPrecompile reads.
        @test isfile(joinpath(output, "ProjecturedPlatform", "precompile", "readme-data-frame.txt"))
        @test all(result -> result.status === :new, results)
        # Each package that has tests has a workflow of its own, on each Julia
        # version, and its job develops the packages that its test needs.
        workflows = joinpath(output, ".github", "workflows")
        tested = filter(name -> isfile(joinpath(output, name, "test", "runtests.jl")), names)
        @test readdir(workflows) == sort(["$name.yml" for name in tested])
        workflow = read(joinpath(workflows, "ProjecturedJSON.yml"), String)
        # The badge shows the name of the workflow: the slice, and the umbrella's own.
        @test occursin("name: JSON\n", workflow)
        # It runs when a folder that its test develops changes, or itself.
        for pattern in ("ProjecturedJSON/**", "ProjecturedKernel/**", "test/ProjecturedJSONTest/**",
                        ".github/workflows/ProjecturedJSON.yml")
            @test count("      - '$pattern'\n", workflow) == 2
        end
        @test !occursin("ProjecturedSDL/**", workflow)
        @test occursin("name: Projectured\n", read(joinpath(workflows, "Projectured.yml"), String))
        @test [m[1] for m in eachmatch(r"- \{package: (\w+),", workflow)] == ["ProjecturedJSON"]
        versions = match(r"julia: \[(.*)\]", workflow)[1]
        @test all(version -> occursin("'$version'", versions), PROJECTURED_CI_JULIA_VERSIONS)
        develop = split(match(r"- \{package: ProjecturedJSON, develop: '([^']*)'", workflow)[1])
        @test issubset(["ProjecturedKernel", "ProjecturedPlatform", "ProjecturedJSON"], develop)
        # A job adds ProjecturedRegistry beside General, which hold the packages
        # of the other repositories, and adds no package by its URL.
        @test occursin("Pkg.Registry.add(\"General\")", workflow)
        @test occursin("Pkg.Registry.add(url = \"$PROJECTURED_REGISTRY_URL\")", workflow)
        @test !occursin("PackageSpec(url", workflow)
        # AutoIntegration, a package of a sibling repository, gets the bound of the
        # version that the manifest names.
        umbrella = ProjecturedBuilder.BuilderModule.TOML.parsefile(
            joinpath(output, "Projectured", "Project.toml"))
        @test umbrella["compat"]["AutoIntegration"] == "0.1.0"
        # The test of the umbrella loads the umbrella, which its test package does not.
        @test occursin("using Projectured\nusing ProjecturedTest\n",
                       read(joinpath(output, "Projectured", "test", "runtests.jl"), String))
        # Each released package, and no other, has a README entry whose document
        # exists, and its README holds its sentence and the install lines.
        @test sort(collect(keys(PROJECTURED_PACKAGE_READMES))) == sort(names)
        for (name, readme) in PROJECTURED_PACKAGE_READMES
            @test isfile(joinpath(context.root, readme.document))
        end
        # The front page has a row for each released package, with the badge of its
        # workflow when it has tests, and the install lines.
        front = read(joinpath(output, "README.md"), String)
        @test count("/actions/workflows/", front) == 2 * length(tested)
        @test occursin("| Package | &nbsp;", front)
        # The front page says which repository is which.
        @test occursin("| [projectured-julia]($PROJECTURED_SOURCE) |", front) &&
              occursin("| [AutoIntegration.jl]($AUTOINTEGRATION_URL) |", front)
        # The registries that it names are links.
        @test occursin("registry [`ProjecturedRegistry`]($PROJECTURED_REGISTRY_URL)", front) &&
              occursin("[General]($GENERAL_REGISTRY_URL)", front)
        # The way that loads `Projectured` comes before the way that names each package.
        @test findfirst("### Let `Projectured` load the integrations", front)[1] <
              findfirst("### Name each package", front)[1]
        @test occursin("| [ProjecturedJSON](ProjecturedJSON) | [![tests](" *
                       "$PROJECTURED_RELEASE_URL/actions/workflows/ProjecturedJSON.yml/badge.svg)]", front)
        @test all(name -> occursin("| [$name]($name) | ", front), names)
        @test occursin("pkg> registry add General\npkg> registry add $PROJECTURED_REGISTRY_URL\n", front)
        readme = read(joinpath(output, "ProjecturedJSON", "README.md"), String)
        @test occursin(PROJECTURED_PACKAGE_READMES["ProjecturedJSON"].summary, readme)
        @test occursin("pkg> registry add General\npkg> registry add $PROJECTURED_REGISTRY_URL\n" *
                       "pkg> add ProjecturedJSON\n", readme)
        # A README says when AutoIntegration loads the package, from the triggers
        # that its `Project.toml` declares.
        @test occursin("[AutoIntegration]($AUTOINTEGRATION_URL) also loads it by itself when " *
                       "`Projectured` is loaded", readme)
        @test occursin("registry\n[`ProjecturedRegistry`]($PROJECTURED_REGISTRY_URL)", readme)
        sdl = read(joinpath(output, "ProjecturedSDL", "README.md"), String)
        @test occursin("when `Projectured` and `SimpleDirectMediaLayer` are loaded", sdl)
        @test occursin("`using ProjecturedWeb` loads it.\n",
                       read(joinpath(output, "ProjecturedWeb", "README.md"), String))
        # The front page has a row for each integration, with its folder, the
        # repository of the package that it joins, and its triggers.
        @test occursin("| [`ProjecturedSDL`](ProjecturedSDL) | " *
                       "[SimpleDirectMediaLayer]($(PROJECTURED_JOINED_PACKAGE_URLS["SimpleDirectMediaLayer"])) | " *
                       "Projectured and SimpleDirectMediaLayer |", front)
        @test count("| [`Projectured", split(front, "### Choose")[1]) == 6
        # The front page says that the first window of a session compiles.
        @test occursin("> The first `using` after an install compiles the packages", front)
        rm(dirname(output); recursive = true)
    end
end
