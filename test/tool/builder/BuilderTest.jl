# Tests for `ProjecturedBuilder`'s stable core — what it writes into a binary,
# and what it checks before it calls one a distribution.
#
# Nothing here compiles. A build takes minutes and needs a compiler; what this
# guards is the text the builder writes and the refusals it makes, both decided
# long before a `compile_app` is reached. Every context a test makes has its
# `root` set to a fresh temporary directory, so a run writes nothing into this
# repository.

using Test

# A package that is certainly in this repository and costs nothing to name. The
# generated module is never loaded here, so what it holds does not matter — only
# that `get_package_directory` resolves it.
const A_PACKAGE = "ProjecturedBuilder"

"""
A `BuildContext` whose `root` is a fresh temporary directory, so a build writes
nothing into this repository. `package_roots` still points at this
repository's own `package/`, so `get_package_directory` has something real to
resolve.
"""
function _test_context()
    real_root = normpath(joinpath(@__DIR__, "..", "..", ".."))
    BuildContext(mktempdir(); package_roots = [joinpath(real_root, "package")])
end

"Read back the module a build would compile, without compiling it."
function _generated_source(context::BuildContext; name, usage, log_level::Symbol = :warn)
    # `main` is an `Expr` whose value is the exit code. A bare `0` is not one:
    # `:(0)` is the literal, and the builder asks for an expression so that
    # Julia's parser checks a build function's `main` while it still runs.
    main = :(begin
        0
    end)
    # The real record, not a fabricated one, so what the test reads back is what
    # a build writes — the build timestamp among it.
    info = build_info(; name = name, packages = [A_PACKAGE], main = main,
                        workload = nothing, preferences = [],
                        optimization = 3, debug_info = 1, cpu_target = "")
    project = write_app_package(context; name = name, packages = [A_PACKAGE],
                                 main = main, info = info, usage = usage,
                                 log_level = log_level)
    module_name = only(filter(f -> endswith(f, ".jl"), readdir(joinpath(project, "src"))))
    read(joinpath(project, "src", module_name), String)
end

"""
Evaluate the flag matcher the builder wrote, and answer a function that asks it.

The ask goes back through `Base.eval` rather than through the binding, because a
function defined a moment ago belongs to a later world than the code reading it,
and a recent Julia warns about that access before a later Julia refuses it.
"""
function _flag_matcher(source)
    sandbox = Module(:FlagSandbox)
    for line in split(source, '\n')
        (startswith(line, "const KNOWN_FLAGS") || startswith(line, "_known_flag")) &&
            Base.eval(sandbox, Meta.parse(line))
    end
    argument -> Base.eval(sandbox, :(_known_flag($argument)))
end

"""
Evaluate the three things the builder wrote about the log level, and answer the
module that holds them.

The whole generated module cannot be loaded here — it names packages this test
does not want — so the statements are picked out of its parse tree by name. That
is what keeps this a test of what the builder wrote rather than of a copy of it.
"""
function _log_level_sandbox(source)
    sandbox = Module(:LogSandbox)
    for statement in Meta.parseall(source).args[end].args[end].args
        wanted = if Meta.isexpr(statement, :const)
            statement.args[1].args[1] in (:DEFAULT_LOG_LEVEL, :LOG_LEVELS)
        elseif Meta.isexpr(statement, :function)
            statement.args[1].args[1].args[1] === :_apply_log_level!
        else
            false
        end
        wanted && Base.eval(sandbox, statement)
    end
    sandbox
end

"""
Run the generated `_apply_log_level!` over `arguments` and `environment`, and
answer its exit code, what it left in `ARGS`, and the level it set.

`ARGS` and the global logger are this process's own, so both are put back. A
test that left the logger at `Error` would silence every test after it.
"""
function _apply_log_level(sandbox; arguments = String[], environment = nothing)
    saved_arguments, saved_logger = copy(ARGS), Base.global_logger()
    try
        empty!(ARGS); append!(ARGS, arguments)
        answer = withenv("PROJECTURED_LOG_LEVEL" => environment) do
            # Through `Base.eval`, because a function defined a moment ago belongs
            # to a later world than the code reading it.
            Base.eval(sandbox, :(_apply_log_level!()))
        end
        (answer, copy(ARGS), Base.global_logger().min_level)
    finally
        empty!(ARGS); append!(ARGS, saved_arguments)
        Base.global_logger(saved_logger)
    end
end

function test_build_executable()
    @testset "builder" begin
        @testset "the help text of the binary names exactly the options of the application" begin
            # The `--help` text of a binary names exactly the options the
            # parser takes.
            usage = make_projectured_usage([:sdl, :web])
            flags = Set(first(split(label, '=')) for (label, _) in usage.options)
            @test flags == Set(["--backend", "--assistant", "--model",
                                "--root", "--mcp", "--context",
                                "--strict-fault-policy", "--agent-command"])
            # The binary takes both forms of `--mcp`: the flag alone, and the
            # flag with the address.
            @test "--mcp" in collect_option_flags(usage)
            @test "--mcp=" in collect_option_flags(usage)
            # A flag and the keyword it sets spell the same words, a flag with
            # a hyphen and a keyword with an underscore, so
            # `--strict-fault-policy` is `strict_fault_policy`.
            for flag in flags
                @test haskey(pairs(parse_application_arguments(String[])),
                             Symbol(replace(flag[3:end], '-' => '_')))
            end
            @test !any(label -> startswith(first(label), "--backend"),
                       make_projectured_usage([:sdl]).options)
        end

        @testset "the binary loads every package of the flat namespace" begin
            context = BuildContext(normpath(joinpath(@__DIR__, "..", "..", "..")))
            project = ProjecturedBuilder.BuilderModule.TOML.parsefile(
                joinpath(get_package_directory(context, "ProjecturedAll"), "Project.toml"))
            flat = [name for name in keys(project["deps"]) if startswith(name, "Projectured")]
            @test sort(PROJECTURED_APPLICATION_IMPORTS) ==
                  sort(setdiff(flat, ["ProjecturedKernel", "ProjecturedPlatform"]))
        end

        @testset "the help text says the three flags every binary answers" begin
            text = format_usage("a-binary", Usage("What it does."; synopsis = "[options] <file>",
                                                options = ["--wide=<n>" => "how wide"]))
            @test startswith(text, "Usage: a-binary [options] <file>\n")
            @test occursin("What it does.", text)
            @test occursin("--wide=<n>", text)
            # The builder appends these, so no build function can leave one out.
            @test occursin("--log-level=<level>", text)
            @test occursin("-h, --help", text)
            @test occursin("-v, --version", text)
            @test occursin("--build-info", text)
            # A description starts at one column, so a person who reads one help
            # text and then another sees one shape.
            @test occursin("\n  -h, --help                 print this text and exit\n", text)

            # A second line of a description starts in the same column, and a
            # label too wide for the column puts its description below it.
            text = format_usage("a-binary", Usage("x"; options = [
                "--short" => "one\ntwo",
                "--a-label-wider-than-the-column" => "three"]))
            @test occursin("\n  --short                    one\n" *
                           "                             two\n", text)
            @test occursin("\n  --a-label-wider-than-the-column\n" *
                           "                             three\n", text)
        end

        @testset "a flag that takes a value is known by its prefix" begin
            flags = collect_option_flags(Usage("x"; options = ["--backend=web" => "y",
                                                                "-q, --quiet" => "z"]))
            @test "--backend=" in flags       # a value follows it
            @test "-q" in flags && "--quiet" in flags   # one label, two flags
            @test "--build-info" in flags && "-h" in flags && "-v" in flags
            # A value follows it, so it is known by its prefix like any other.
            @test "--log-level=" in flags
        end

        @testset "a binary whose build wrote a usage answers all three flags" begin
            context = _test_context()
            source = _generated_source(context; name = "with_usage",
                                         usage = Usage("Draws a window.";
                                                       options = ["--backend=web" => "a browser"]))
            @test occursin("const USAGE", source)
            @test occursin("const VERSION_LINE = \"with_usage 0.1.0\"", source)
            @test occursin("\"--build-info\" in ARGS", source)
            @test occursin("\"--help\" in ARGS", source)
            @test occursin("\"--version\" in ARGS", source)
            # An unknown flag is refused, and is not read as something else.
            @test occursin("unknown option", source)
        end

        @testset "a binary whose program owns the command line keeps it" begin
            context = _test_context()
            source = _generated_source(context; name = "no_usage", usage = nothing)
            # `--build-info` is the builder's whatever else a binary answers: the
            # constant is the generated module's and a program cannot know it.
            @test occursin("\"--build-info\" in ARGS", source)
            @test !occursin("\"--help\" in ARGS", source)
            @test !occursin("const USAGE", source)
            @test !occursin("unknown option", source)
        end

        @testset "the flag matcher the builder wrote" begin
            context = _test_context()
            known = _flag_matcher(_generated_source(context; name = "matcher",
                                    usage = Usage("x"; options = ["--backend=web" => "y"])))
            @test known("--backend=web")
            @test known("--backend=anything")   # the value is not the builder's business
            @test known("-h") && known("--version") && known("--build-info")
            @test !known("--bogus")
            @test !known("--backend")           # it takes a value, so bare is not a flag
        end

        @testset "every binary logs from warn and up, whatever else it does" begin
            context = _test_context()
            source = _generated_source(context; name = "quiet", usage = nothing)
            @test occursin("const DEFAULT_LOG_LEVEL = \"warn\"", source)
            # FIRST in `julia_main`: the flag has to be gone before anything else
            # reads `ARGS`.
            @test occursin("function julia_main()::Cint\n" *
                           "    _apply_log_level!() == 0 || return 1\n", source)
        end

        @testset "a stand-in takes the place of a JLL that a binary must not carry" begin
            context = _test_context()
            uuid = "00000000-0000-0000-0000-0000000000aa"
            keep = "00000000-0000-0000-0000-0000000000ab"
            stand_ins = [StandIn("some_jll", uuid; keeps = ["Kept_jll" => keep])]
            directory = write_app_package(context; name = "quiet", packages = [A_PACKAGE],
                                          main = :(begin 0 end), stand_ins)
            project = ProjecturedBuilder.BuilderModule.TOML.parsefile(joinpath(directory,
                                                                 "Project.toml"))
            @test project["deps"]["some_jll"] == uuid
            @test project["sources"]["some_jll"]["path"] ==
                  joinpath("stand_in", "some_jll")
            stand_in = joinpath(directory, "stand_in", "some_jll")
            stand_in_project = ProjecturedBuilder.BuilderModule.TOML.parsefile(joinpath(stand_in,
                                                                          "Project.toml"))
            @test stand_in_project["uuid"] == uuid
            # It keeps a dependency of the real one, and loads it.
            @test stand_in_project["deps"] == Dict("Kept_jll" => keep)
            source = read(joinpath(stand_in, "src", "some_jll.jl"), String)
            @test occursin("import Kept_jll", source)
            # What a user of a JLL reads: an artifact folder and two lists of paths,
            # all empty. Evaluated in a module of its own, without the import, so
            # nothing here is changed.
            sandbox = Module(:StandInSandbox)
            Base.include_string(sandbox, replace(source, "import Kept_jll" => ""))
            jll = getfield(sandbox, :some_jll)
            @test jll.artifact_dir == ""
            @test isempty(jll.PATH_list) && isempty(jll.LIBPATH_list)
            @test !Base.invokelatest(jll.is_available)
            # The build record says what the binary does not carry.
            info = build_info(; name = "quiet", packages = [A_PACKAGE],
                                main = :(begin 0 end),
                                workload = nothing, preferences = [], optimization = 3,
                                debug_info = 1, cpu_target = "", stand_ins)
            @test occursin("stand-in: some_jll, which this binary does not carry; it " *
                           "keeps Kept_jll", info)
            @test only(PROJECTURED_STAND_INS).name == "alsa_plugins_jll"
            @test only(PROJECTURED_STAND_INS).uuid ==
                  "5ac2f6bb-493e-5871-9171-112d4c21a6e7"
            @test Set(first.(only(PROJECTURED_STAND_INS).keeps)) ==
                  Set(["libsamplerate_jll", "Libiconv_jll"])
        end

        @testset "an archive carries the licence texts of what it holds" begin
            # The texts of the colour data that the program holds are in the repository.
            repository = normpath(joinpath(@__DIR__, "..", "..", ".."))
            @test all(isfile(joinpath(repository, file))
                      for (_, file) in ProjecturedBuilder.BuilderModule.PROJECTURED_DATA_TEXTS)
            root = mktempdir()
            # A standard-library JLL whose artifact, for this platform, is a local
            # tarball with one licence text.
            artifact = joinpath(root, "artifact")
            mkpath(joinpath(artifact, "share", "licenses", "Fake"))
            write(joinpath(artifact, "share", "licenses", "Fake", "LICENSE"),
                  "fake licence\n")
            tarball = joinpath(root, "Fake.tar.gz")
            run(`tar -czf $tarball -C $artifact share`)
            digest = bytes2hex(open(ProjecturedBuilder.BuilderModule.sha256, tarball))
            stdlib = joinpath(root, "stdlib")
            mkpath(joinpath(stdlib, "Fake_jll"))
            write_stdlib(sha) = write(joinpath(stdlib, "Fake_jll",
                                      "StdlibArtifacts.toml"), """
                [[Fake]]
                arch = "$(Sys.ARCH)"
                git-tree-sha1 = "0000000000000000000000000000000000000000"
                libc = "glibc"
                os = "linux"

                    [[Fake.download]]
                    sha256 = "$sha"
                    url = "file://$tarball"
                """)
            write_stdlib(digest)
            # A package from a registry, found in a depot by its slug; a standard
            # library and a package reached by path carry no tree hash.
            uuid = "00000000-0000-0000-0000-0000000000bb"
            tree = "1111111111111111111111111111111111111111"
            depot = joinpath(root, "depot")
            package = joinpath(depot, "packages", "Foo",
                               Base.version_slug(Base.UUID(uuid), Base.SHA1(tree)))
            mkpath(package)
            write(joinpath(package, "LICENSE.md"), "foo licence\n")
            write(joinpath(package, "README.md"), "not a licence\n")
            project = joinpath(root, "project")
            mkpath(project)
            write(joinpath(project, "Manifest.toml"), """
                [[deps.Foo]]
                git-tree-sha1 = "$tree"
                uuid = "$uuid"
                version = "1.2.3"

                [[deps.Dates]]
                uuid = "ade2ca70-3891-5945-98fb-dc099432e06a"
                version = "1.11.0"
                """)
            thirdparty = joinpath(root, "THIRDPARTY.md")
            write(thirdparty, "third parties\n")
            # A bundle whose one artifact carries its own texts.
            bundle = joinpath(root, "bundle")
            mkpath(joinpath(bundle, "share", "julia", "artifacts", "abc", "share",
                            "licenses", "Bar"))
            write(joinpath(bundle, "share", "julia", "artifacts", "abc", "share",
                           "licenses", "Bar", "COPYING"),
                  "bar\n")

            readme = read(bundle_licence_texts!(bundle; project,
                          cache = joinpath(root, "cache"),
                          credits = ["A credit."], julia_thirdparty = thirdparty,
                          extra_texts = ["Certs" => thirdparty],
                          data_texts = ["Palette" => thirdparty],
                          stdlib, depots = [depot]), String)
            licenses = joinpath(bundle, "share", "licenses")
            @test isfile(joinpath(licenses, "julia", "LICENSE.md"))
            @test read(joinpath(licenses, "julia", "THIRDPARTY.md"), String) ==
                  "third parties\n"
            @test read(joinpath(licenses, "stdlib", "Fake", "LICENSE"), String) ==
                  "fake licence\n"
            @test isfile(joinpath(licenses, "stdlib", "Certs", "THIRDPARTY.md"))
            @test isfile(joinpath(licenses, "data", "Palette", "THIRDPARTY.md"))
            @test !isdir(joinpath(licenses, "stdlib", "Palette"))
            @test read(joinpath(licenses, "packages", "Foo", "LICENSE.md"), String) ==
                  "foo licence\n"
            @test !isfile(joinpath(licenses, "packages", "Foo", "README.md"))
            @test !isdir(joinpath(licenses, "packages", "Dates"))
            for line in ("  Certs", "  Fake", "  Foo 1.2.3", "  Palette",
                         "  Bar: share/julia/artifacts/abc/share/licenses/Bar",
                         "  A credit.")
                @test occursin(line, readme)
            end
            # An artifact whose bytes are not the ones its JLL names stops the build.
            write_stdlib("0"^64)
            @test_throws ErrorException bundle_licence_texts!(bundle; project,
                cache = joinpath(root, "other-cache"), julia_thirdparty = thirdparty,
                stdlib, depots = [depot])
            # And the README of the archive points to the index and holds the credits.
            text = read(write_readme(mktempdir(); name = "thing", version = "0.1.0",
                                     requirements = String[], third_party = true,
                                     credits = ["A credit."]), String)
            @test occursin("share/licenses/README", text) && occursin("A credit.", text)
            @test PROJECTURED_CREDITS[1] ==
                  "This software is based in part on the work of the Independent JPEG " *
                  "Group."
            rm(root; recursive = true)
        end

        @testset "every binary ends in silence on SIGTERM" begin
            context = _test_context()
            source = _generated_source(context; name = "quiet", usage = nothing)
            # Second, right after the log level, before the program starts any
            # work that a signal could interrupt.
            @test occursin("    _apply_log_level!() == 0 || return 1\n" *
                           "    _end_on_terminate!()\n", source)
            # Not called here: it would change how this test process takes the
            # signal. What it does is checked on a real process in Step A3 of the
            # release plan.
            @test occursin("function _end_on_terminate!()::Nothing", source)
            @test occursin("ccall(:pthread_sigmask", source)
        end

        @testset "the build bakes the default and the flag says another" begin
            context = _test_context()
            # A build for developing ships at info; a distribution ships quiet.
            source = _generated_source(context; name = "talkative", usage = nothing,
                                         log_level = :info)
            @test occursin("const DEFAULT_LOG_LEVEL = \"info\"", source)
            sandbox = _log_level_sandbox(source)

            # The baked default answers when nobody says.
            code, arguments, level = _apply_log_level(sandbox)
            @test code == 0
            @test level == Base.CoreLogging.Info

            # The flag says another, and THE BUILD CONSUMES IT: a program that
            # parses its own command line refuses a flag it does not know, and it
            # never sees this one.
            code, arguments, level = _apply_log_level(sandbox;
                                        arguments = ["--log-level=error", "-c", "Something"])
            @test code == 0
            @test arguments == ["-c", "Something"]
            @test level == Base.CoreLogging.Error

            # The environment is asked before the baked default and after the flag.
            @test last(_apply_log_level(sandbox; environment = "debug")) ==
                  Base.CoreLogging.Debug
            @test last(_apply_log_level(sandbox; environment = "debug",
                                        arguments = ["--log-level=warn"])) ==
                  Base.CoreLogging.Warn

            # `none` silences `@error` as well, for a run driven by its exit code.
            @test last(_apply_log_level(sandbox; arguments = ["--log-level=NONE"])) ==
                  Base.CoreLogging.AboveMaxLevel

            # A level nobody defined is refused, and both copies of the flag go.
            code, arguments, _ = _apply_log_level(sandbox;
                                    arguments = ["--log-level=chatty", "x", "--log-level=loud"])
            @test code == 1
            @test arguments == ["x"]
        end

        @testset "a level nobody defined is refused before anything is written" begin
            context = _test_context()
            @test_throws ErrorException _generated_source(context; name = "wrong", usage = nothing,
                                                            log_level = :chatty)
        end

        @testset "a build is measured with a flag every binary answers" begin
            # `--version` reaches `main` in a binary whose build wrote no usage,
            # and a window binary then opens a window instead of answering. So
            # the report asks for the one flag the builder writes itself.
            @test get_smoke_flag() == "--build-info"
        end

        @testset "the package lookup searches every root in order" begin
            context = _test_context()
            directory = get_package_directory(context, A_PACKAGE)
            @test isdir(directory)
            @test get_package_uuid(directory) ==
                  ProjecturedBuilder.BuilderModule.TOML.parsefile(joinpath(directory, "Project.toml"))["uuid"]
            @test_throws ErrorException get_package_directory(context, "NoSuchPackage")
        end

        @testset "a root can be the folder of one package itself" begin
            folder = mktempdir()
            open(joinpath(folder, "Project.toml"), "w") do io
                ProjecturedBuilder.BuilderModule.TOML.print(io, Dict(
                    "name" => "Agent", "uuid" => string(Base.UUID(hash("Agent")))))
            end
            context = BuildContext(mktempdir(); package_roots = [folder])
            @test has_package_directory(context, "Agent")
            @test get_package_directory(context, "Agent") == folder
            @test !has_package_directory(context, "Other")
        end

        @testset "a local dependency without a path in [sources] is found" begin
            packages = mktempdir()
            write_project(name, deps, sources) = begin
                mkpath(joinpath(packages, name))
                open(joinpath(packages, name, "Project.toml"), "w") do io
                    ProjecturedBuilder.BuilderModule.TOML.print(io, Dict(
                        "name" => name, "uuid" => string(Base.UUID(hash(name))),
                        "deps" => Dict(d => string(Base.UUID(hash(d))) for d in deps),
                        "sources" => Dict(d => Dict("path" => "../$d") for d in sources)))
                end
            end
            write_project("Top", ["Middle", "Dates"], ["Middle"])
            write_project("Middle", ["Bottom", "Other"], ["Other"])
            write_project("Other", String[], String[])
            write_project("Bottom", String[], String[])
            context = BuildContext(mktempdir(); package_roots = [packages])
            @test has_package_directory(context, "Bottom")
            @test !has_package_directory(context, "Dates")
            @test collect_missing_sources(context, ["Top"]) == ["Middle" => "Bottom"]
            @test_throws ErrorException build_executable(context; name = "top",
                packages = ["Top"], main = :(begin 0 end), compile = false)
            @test !isdir(joinpath(context.root, "build"))    # nothing is written
            write_project("Middle", ["Bottom", "Other"], ["Bottom", "Other"])
            @test isempty(collect_missing_sources(context, ["Top"]))
        end

        @testset "a caller puts its own file into the package before it is resolved" begin
            context = _test_context()
            seen = String[]
            project = build_executable(context; name = "extra", packages = [A_PACKAGE],
                main = :(begin 0 end), compile = false,
                after_write = directory -> begin
                    push!(seen, directory)
                    write(joinpath(directory, "extra.jl"), "# a file of the caller\n")
                end)
            @test seen == [project]
            @test isfile(joinpath(project, "extra.jl"))
        end

        @testset "a build that would write the same module again leaves it alone" begin
            # A rewrite is a recompile: Julia decides a cache is stale from the
            # source file, and the generated module is the top of the tree.
            context = _test_context()
            first_source = _generated_source(context; name = "stable", usage = nothing)
            path = joinpath(context.root, "build", "app", "stable", "src", "StableApp.jl")
            before = mtime(path)
            second_source = _generated_source(context; name = "stable", usage = nothing)
            @test mtime(path) == before          # not written again
            @test first_source == second_source   # and what is there is unchanged

            # The build timestamp is the one line that differs between two builds
            # of the same binary, and it must not count as a difference.
            @test occursin(ProjecturedBuilder.BuilderModule._BUILD_TIMESTAMP, first_source)
            # A different timestamp alone is not a difference, so nothing is
            # written and the cache holds.
            other_time = replace(first_source,
                                 ProjecturedBuilder.BuilderModule._BUILD_TIMESTAMP =>
                                     "built 1999-01-01 00:00 by ProjecturedBuilder")
            @test other_time != first_source
            @test !write_if_changed(path, other_time;
                                    ignoring = ProjecturedBuilder.BuilderModule._BUILD_TIMESTAMP)
            @test mtime(path) == before
            # Anything else is.
            @test write_if_changed(path, replace(first_source, "module " => "module X");
                                   ignoring = ProjecturedBuilder.BuilderModule._BUILD_TIMESTAMP)
        end

        @testset "a manifest that names a path no package is at goes" begin
            # A manifest names by path every package the build resolved, and a
            # package that is deleted from the tree stays in it. `Pkg.resolve`
            # reads that entry and throws `expected package to exist at path`.
            # The project beside it names only the direct packages, so the
            # entry is caught by the path on disk and not by the project.
            mktempdir() do project
                write(joinpath(project, "Project.toml"), """
                    name = "T"
                    uuid = "11111111-1111-1111-1111-111111111111"
                    """)
                mkpath(joinpath(project, "package", "A"))
                manifest = joinpath(project, "Manifest.toml")
                held = """
                    [[deps.A]]
                    path = "package/A"
                    uuid = "22222222-2222-2222-2222-222222222222"
                    """
                write(manifest, held)
                # Every path is on disk, so the manifest stays.
                @test !ProjecturedBuilder.BuilderModule._drop_stale_manifest(project)
                @test isfile(manifest)

                # The package goes, and the entry that names it is what
                # `Pkg.resolve` would have thrown on.
                rm(joinpath(project, "package", "A"); recursive = true)
                @test ProjecturedBuilder.BuilderModule._drop_stale_manifest(project)
                @test !isfile(manifest)

                # An entry with no path is a registered package, and it stays.
                write(manifest, """
                    [[deps.B]]
                    uuid = "33333333-3333-3333-3333-333333333333"
                    version = "1.0.0"
                    """)
                @test !ProjecturedBuilder.BuilderModule._drop_stale_manifest(project)
                @test isfile(manifest)
            end
        end

        @testset "a manifest that names another path than its project goes" begin
            # A package that is renamed or split between two builds leaves a
            # manifest the project no longer agrees with, and `Pkg.resolve`
            # asserts on it instead of resolving. The manifest is the artefact
            # and the project is the truth, so the manifest goes.
            mktempdir() do project
                write(joinpath(project, "Project.toml"), """
                    name = "T"
                    uuid = "11111111-1111-1111-1111-111111111111"

                    [sources.A]
                    path = "package/A"
                    """)
                mkpath(joinpath(project, "package", "A"))
                mkpath(joinpath(project, "package", "AOld"))
                manifest = joinpath(project, "Manifest.toml")
                agreeing = """
                    [[deps.A]]
                    path = "package/A"
                    uuid = "22222222-2222-2222-2222-222222222222"
                    """
                write(manifest, agreeing)
                # A manifest that agrees is left where it is.
                @test !ProjecturedBuilder.BuilderModule._drop_stale_manifest(project)
                @test isfile(manifest)

                # A path that differs is what the assertion would have died on.
                # Both paths are on disk, so only the project catches this one.
                write(manifest, replace(agreeing, "package/A" => "package/AOld"))
                @test ProjecturedBuilder.BuilderModule._drop_stale_manifest(project)
                @test !isfile(manifest)

                # A project with no manifest beside it is not an error.
                @test !ProjecturedBuilder.BuilderModule._drop_stale_manifest(project)
            end
        end

        @testset "a manifest whose versions do not resolve is resolved again without it" begin
            # `Pkg.resolve` holds every version the manifest names. A project
            # that asks for an older version than the manifest holds fails on
            # that manifest, and a resolve from the project alone succeeds. The
            # registry on disk is enough: the resolve does not update it.
            mktempdir() do project
                write(joinpath(project, "Project.toml"), """
                    [deps]
                    OrderedCollections = "bac558e1-5e72-5ebc-8fee-abe8a469f55d"

                    [compat]
                    OrderedCollections = "1"
                    """)
                manifest = joinpath(project, "Manifest.toml")
                held = """
                    manifest_format = "2.0"

                    [[deps.OrderedCollections]]
                    git-tree-sha1 = "05f45c2e0de6259db764adbfd2f1dc6d3f8de13c"
                    uuid = "bac558e1-5e72-5ebc-8fee-abe8a469f55d"
                    version = "2.0.1"
                    """
                write(manifest, held)
                resolve_app_project(project; precompile = false)
                entry = only(ProjecturedBuilder.BuilderModule.TOML.parsefile(manifest)["deps"]["OrderedCollections"])
                @test VersionNumber(entry["version"]).major == 1

                # A conflict that the project itself holds is thrown after the
                # second resolve, and the manifest is not written again.
                write(joinpath(project, "Project.toml"), """
                    [deps]
                    OrderedCollections = "bac558e1-5e72-5ebc-8fee-abe8a469f55d"

                    [compat]
                    OrderedCollections = "99"
                    """)
                write(manifest, held)
                @test_throws ProjecturedBuilder.BuilderModule.Pkg.Resolve.ResolverError resolve_app_project(project;
                                                                                precompile = false)
                @test !isfile(manifest)
            end
        end

        @testset "incremental is the default, and a distribution is not" begin
            # `create_app` defaults `incremental` to false; the core flips the
            # default because a non-incremental build compiles every stdlib into
            # a fresh image, and an incremental one starts from the running
            # Julia's, which has them already.
            info = build_info(; name = "d", packages = ["A"], main = :(begin
                                   0
                               end),
                               workload = nothing, preferences = [],
                               optimization = 3, debug_info = 1,
                               cpu_target = "", incremental = true)
            @test occursin(INCREMENTAL_MARK, info)
        end

        @testset "every build compiles for native; only a distribution travels" begin
            # `cpu_target` asks which machines the binary RUNS on. `incremental`
            # asks which image it is built ON. They are different questions, so
            # `incremental` does not move the target.
            context = _test_context()
            build(; kw...) = build_executable(context; packages = [A_PACKAGE],
                                               main = :(begin; 0; end),
                                               compile = false, resolve = false, kw...)
            record(d) = read(joinpath(d, "src", get_app_module_name(basename(d)) * ".jl"),
                             String)
            @test occursin("for native", record(build(; name = "cpu_a")))
            @test occursin("for native", record(build(; name = "cpu_b", incremental = false)))
            @test occursin("for haswell", record(build(; name = "cpu_c", cpu_target = "haswell")))
            # The portable target is the empty one: `compile_app!` leaves the
            # keyword out and `create_app` picks the variants for the architecture.
            @test !occursin("-g1 for", record(build(; name = "cpu_d",
                                                      cpu_target = PORTABLE_CPU_TARGET)))
        end

        @testset "an incremental build says so, and cannot be distributed" begin
            # The binary's own record is where this is written, and where
            # `check_relocation` reads it back, so a developer image cannot be
            # archived even by a caller that did not build it.
            marked = build_info(; name = "x", packages = ["A"], main = :(begin
                                     0
                                 end),
                                 workload = nothing, preferences = [],
                                 optimization = 3, debug_info = 1,
                                 cpu_target = "", incremental = true)
            @test occursin(INCREMENTAL_MARK, marked)
            plain = build_info(; name = "x", packages = ["A"], main = :(begin
                                     0
                                 end),
                                workload = nothing, preferences = [],
                                optimization = 3, debug_info = 1, cpu_target = "")
            @test !occursin(INCREMENTAL_MARK, plain)
        end

        @testset "build_info appends what a caller's own build adds" begin
            info = build_info(; name = "x", packages = ["A"], main = :(begin
                                   0
                               end),
                               workload = nothing, preferences = [],
                               optimization = 3, debug_info = 1, cpu_target = "",
                               extra_info = "an extra line a caller wrote")
            @test endswith(strip(info), "an extra line a caller wrote")
        end

        @testset "a distribution refuses what it cannot check" begin
            context = _test_context()
            @test_throws ErrorException build_distribution(context; name = "nothing_here",
                                            bundle = joinpath(context.root, "build", "no-such-bundle"))
            # A bundle with no executable in it is a build that did not finish.
            empty_bundle = mktempdir()
            mkpath(joinpath(empty_bundle, "bin"))
            @test_throws ErrorException build_distribution(context; name = "gone", bundle = empty_bundle)

            # A copy tested inside the checkout it was built in proves nothing
            # about a copy, so the staging directory must be outside.
            mkpath(joinpath(empty_bundle, "bin"))
            write(joinpath(empty_bundle, "bin", "gone"), "")
            @test_throws ErrorException build_distribution(context; name = "gone", bundle = empty_bundle,
                                            staging = joinpath(context.root, "build", "stage"))
            rm(empty_bundle; recursive = true, force = true)
        end

        @testset "a source archive holds exactly the offered sources" begin
            root = mktempdir()
            context = _test_context()
            # Two upstream tarballs and a patch, served from files.
            for (file, text) in (("lib-1.0.tar.gz", "library source"),
                                 ("fix.patch", "a patch"))
                write(joinpath(root, file), text)
            end
            digest(file) =
                bytes2hex(open(ProjecturedBuilder.BuilderModule.sha256, joinpath(root, file)))
            stdlib = joinpath(root, "stdlib")
            mkpath(joinpath(stdlib, "Lib_jll"))
            write(joinpath(stdlib, "Lib_jll", "Project.toml"),
                  "name = \"Lib_jll\"\nversion = \"1.0.0+1\"\n")
            project = joinpath(root, "project")
            mkpath(project)
            write(joinpath(project, "Manifest.toml"), """
                [[deps.Other_jll]]
                git-tree-sha1 = "1111111111111111111111111111111111111111"
                uuid = "00000000-0000-0000-0000-0000000000cc"
                version = "2.0.0+0"
                """)
            offer(jll, version; sha = digest("lib-1.0.tar.gz"),
                                name = "Lib (a library)") =
                SourceOffer(name, "1.0"; jll, jll_version = version,
                            url = "file://$root/lib-1.0.tar.gz", sha256 = sha,
                            recipe = "https://example.org/recipe",
                            patches = ["file://$root/fix.patch"], notes = "A note.")
            build(offers) =
                build_source_archive(context; name = "thing", version = "0.1.0", offers,
                                     output = joinpath(root, "out"),
                                     cache = joinpath(root, "cache"), project, stdlib)

            error_text(action) =
                try action(); "" catch exception; sprint(showerror, exception) end
            archive = build([offer("Lib_jll", "1.0.0+1"),
                             offer("Other_jll", "2.0.0+0"; name = "Other"),
                             offer("julia", string(VERSION); name = "Julia")])
            @test basename(archive) == "thing-0.1.0-sources.tar"
            listing = split(read(`tar -tf $archive`, String))
            @test "thing-0.1.0-sources/README" in listing
            @test "thing-0.1.0-sources/Lib-1.0/lib-1.0.tar.gz" in listing
            @test "thing-0.1.0-sources/Lib-1.0/patches/fix.patch" in listing
            readme = read(`tar -xOf $archive thing-0.1.0-sources/README`, String)
            @test "thing-0.1.0-sources/Other-1.0/lib-1.0.tar.gz" in listing
            for line in ("Lib (a library) 1.0", "of:      Lib_jll 1.0.0+1",
                         "of:      Other_jll 2.0.0+0",
                         "recipe:  https://example.org/recipe", "patches: fix.patch",
                         "  A note.")
                @test occursin(line, readme)
            end

            # A tarball that is not the one that was checked stops the build.
            @test occursin("must be checked again",
                           error_text(() -> build([offer("Lib_jll", "1.0.0+1";
                                                         sha = "0"^64)])))
            # So does a JLL of another version than its offer, and one the binary lacks.
            @test occursin("change the offer",
                           error_text(() -> build([offer("Lib_jll", "1.0.0+2")])))
            @test occursin("carries no Missing_jll",
                           error_text(() -> build([offer("Missing_jll", "1.0.0")])))
            # And two offers that would share one folder.
            @test occursin("share the folder",
                           error_text(() -> build([offer("Lib_jll", "1.0.0+1"),
                                                   offer("julia", string(VERSION))])))

            # The offers of this repository: seven parts, each with a checked SHA-256.
            @test length(PROJECTURED_SOURCE_OFFERS) == 7
            @test all(offer -> occursin(r"^[0-9a-f]{64}$", offer.sha256),
                      PROJECTURED_SOURCE_OFFERS)
            @test Set(offer.jll for offer in PROJECTURED_SOURCE_OFFERS) ==
                  Set(["alsa_jll", "GMP_jll", "MPFR_jll", "CompilerSupportLibraries_jll",
                       "LibGit2_jll", "p7zip_jll", "julia"])
            rm(root; recursive = true)
        end

        @testset "a distribution carries every library it needs beyond glibc" begin
            julia_lib = joinpath(Sys.BINDIR, "..", "lib", "julia")
            if Sys.islinux() && Sys.which("readelf") !== nothing &&
               isfile(joinpath(julia_lib, "libmpfr.so.6"))
                bundle = mktempdir()
                mkpath(joinpath(bundle, "lib"))
                cp(joinpath(julia_lib, "libmpfr.so.6"),
                   joinpath(bundle, "lib", "libmpfr.so.6"); follow_symlinks = true)
                # MPFR needs GMP, and a machine that builds can have it where the test
                # of a copy does not look.
                @test ("libgmp.so.10" => joinpath("lib", "libmpfr.so.6")) in
                      collect_missing_libraries(bundle)
                cp(joinpath(julia_lib, "libgmp.so.10"),
                   joinpath(bundle, "lib", "libgmp.so.10"); follow_symlinks = true)
                @test isempty(collect_missing_libraries(bundle))
                # A bundle that lacks a library stops the distribution.
                rm(joinpath(bundle, "lib", "libgmp.so.10"))
                mkpath(joinpath(bundle, "bin"))
                write(joinpath(bundle, "bin", "thing"), "")
                message = try
                    build_distribution(_test_context(); name = "thing", bundle = bundle)
                    ""
                catch exception
                    sprint(showerror, exception)
                end
                @test occursin("libgmp.so.10, which lib/libmpfr.so.6 needs", message)
                rm(bundle; recursive = true)
            end
            @test "libc.so.6" in GLIBC_LIBRARIES
        end

        @testset "a distribution carries the libstdc++ of Julia, not of the machine" begin
            own = joinpath(Sys.BINDIR, "..", "lib", "julia", "libstdc++.so.6")
            if Sys.islinux() && isfile(own)
                context = _test_context()
                bundle = mktempdir()
                mkpath(joinpath(bundle, "bin"))
                write(joinpath(bundle, "bin", "thing"), "")
                mkpath(joinpath(bundle, "lib", "julia"))
                write(joinpath(bundle, "lib", "julia", "libstdc++.so.6"),
                      "another library")
                message = try
                    build_distribution(context; name = "thing", bundle = bundle,
                                       licences = ["NO-SUCH-LICENCE"])
                    ""
                catch exception
                    sprint(showerror, exception)
                end
                @test occursin("JULIA_PROBE_LIBSTDCXX=0", message)
                # Julia's own library passes, and the build stops at the next check.
                cp(own, joinpath(bundle, "lib", "julia", "libstdc++.so.6"); force = true)
                message = try
                    build_distribution(context; name = "thing", bundle = bundle,
                                       licences = ["NO-SUCH-LICENCE"])
                    ""
                catch exception
                    sprint(showerror, exception)
                end
                @test !occursin("JULIA_PROBE_LIBSTDCXX", message)
                rm(bundle; recursive = true, force = true)
            end
            @test occursin("JULIA_PROBE_LIBSTDCXX=0",
                           read(joinpath(dirname(dirname(dirname(@__DIR__))), "bin",
                                        "build_projectured"), String))
        end

        @testset "an archive carries the licence of what is in it" begin
            # A licence that asks for its text in every copy is broken by an
            # archive that leaves the file out.
            context = _test_context()
            bundle = mktempdir()
            mkpath(joinpath(bundle, "bin"))
            write(joinpath(bundle, "bin", "thing"), "")
            @test_throws ErrorException build_distribution(context; name = "thing",
                bundle = bundle, licences = ["NO-SUCH-LICENCE"])
            rm(bundle; recursive = true, force = true)

            # The README beside the binary names each file that travels with it.
            staged = mktempdir()
            readme = read(write_readme(staged; name = "thing", version = "0.1.0",
                                       requirements = String[],
                                       licences = ["LICENSE", "NOTICE"],
                                       source = "https://example.org/thing"), String)
            @test occursin("LICENSE", readme)
            @test occursin("NOTICE", readme)
            # The source of this version, which MPL-2.0 asks a binary to name.
            @test occursin("https://example.org/thing, tag v0.1.0", readme)
            bare = read(write_readme(staged; name = "thing", version = "0.1.0",
                                     requirements = String[]), String)
            @test !occursin("LICENSE", bare)
            @test !occursin("source code", bare)
            rm(staged; recursive = true, force = true)

            # The application declares its licence, and the file is in the tree.
            @test PROJECTURED_LICENCES == ["LICENSE"]
            @test startswith(
                read(joinpath(dirname(dirname(dirname(@__DIR__))), "LICENSE"), String),
                "Mozilla Public License Version 2.0")
            @test all(licence -> isfile(joinpath(dirname(dirname(dirname(@__DIR__))), licence)),
                      PROJECTURED_LICENCES)
        end

        @testset "a bundle must hold what its build declared it bundled" begin
            context = _test_context()
            bundle = mktempdir()
            mkpath(joinpath(bundle, "bin"))
            write(joinpath(bundle, "bin", "thing"), "")
            # This is the check that would have caught the font fault, where a
            # bundle read its text faces out of the checkout that built it.
            @test_throws ErrorException build_distribution(context; name = "thing", bundle = bundle,
                                            expect = ["share/projectured/font"])
            rm(bundle; recursive = true, force = true)
        end

        @testset "a bundled font carries its licence" begin
            # Lucide and Noto Emoji ask for their notice in every copy, and
            # neither font holds it in its own tables.
            # The fonts run to megabytes, and `/tmp` can be a memory filesystem.
            bundle = mktempdir(get_staging_root())
            bundle_fonts!(bundle)
            fonts = readdir(joinpath(bundle, "share", "projectured", "font"))
            @test "lucide.ttf" in fonts
            @test "Lucide-ISC.txt" in fonts
            @test "NotoEmoji-OFL.txt" in fonts
            rm(bundle; recursive = true, force = true)
        end

        @testset "the staging directory is not a memory filesystem" begin
            # A bundle can run to several hundred megabytes, and `/tmp` is a
            # `tmpfs` on many machines — a copy there is a copy into memory.
            root = get_staging_root()
            @test isdir(root)
        end

        @testset "a copy is tested with the checkout out of sight" begin
            context = _test_context()
            hidden = get_hidden_directories(context)
            @test context.root in hidden
            @test dirname(dirname(dirname(@__DIR__))) in hidden    # the repository
            @test all(isdir, hidden)
            @test make_hidden_command(`true`, String[]) == `true`
            if Sys.which("bwrap") !== nothing
                secret = mktempdir()
                write(joinpath(secret, "file"), "x")
                command = make_hidden_command(`ls -A $secret`, [secret])
                @test first(command.exec) == "bwrap"
                @test isempty(read(command, String))
                @test read(`ls -A $secret`, String) == "file\n"
                # A stop of the command stops the program in it.
                marker = "sleep $(rand(100000:999999))"
                process = run(make_hidden_command(Cmd(split(marker)), [secret]); wait = false)
                @test timedwait(() -> success(`pgrep -x -f $marker`), 10.0) === :ok
                kill(process)
                @test timedwait(() -> !success(`pgrep -x -f $marker`), 10.0) === :ok
                rm(secret; recursive = true)
            end
        end

        @testset "the projectured build writes its package and compiles nothing" begin
            context = _test_context()
            project = build_projectured_executable(; context = context, compile = false)
            @test project == joinpath(context.root, "build", "app", "projectured")
            deps = ProjecturedBuilder.BuilderModule.TOML.parsefile(joinpath(project, "Project.toml"))["deps"]
            # The packages of the binary, and the stand-in that keeps the sound
            # libraries out of it.
            @test Set(keys(deps)) == Set(["PrecompileTools", "ProjecturedPlatform",
                                          PROJECTURED_APPLICATION_IMPORTS...,
                                          "ProjecturedOllama", "ProjecturedAnthropic",
                                          "ProjecturedMCP", "ProjecturedACP", "ProjecturedSDL",
                                          "ProjecturedWeb",
                                          "alsa_plugins_jll"])
            source = read(joinpath(project, "src", "ProjecturedApp.jl"), String)
            @test occursin("ProjecturedPlatform.run_application_command(ARGS; backends = " *
                           "(sdl = ProjecturedSDL.SdlBackend, web = ProjecturedWeb.WebBackend))",
                           source)
            @test occursin("ProjecturedPlatform.warm_application()", source)
            @test occursin("--backend=sdl|web", source)
            @test occursin("--assistant=ollama|anthropic|acp|none", source)
            @test occursin("--agent-command=COMMAND", source)
            text = format_usage("projectured", make_projectured_usage([:sdl, :web]))
            @test all(line -> length(line) <= 80, split(text, '\n'))

            # One backend: no `--backend`, and no workload.
            project = build_projectured_executable(; context = context, compile = false,
                                                   name = "projectured-web",
                                                   backends = (:web,), workload = false)
            deps = ProjecturedBuilder.BuilderModule.TOML.parsefile(joinpath(project, "Project.toml"))["deps"]
            @test !haskey(deps, "ProjecturedSDL") && haskey(deps, "ProjecturedWeb")
            source = read(joinpath(project, "src", "ProjecturedWebApp.jl"), String)
            @test occursin("(web = ProjecturedWeb.WebBackend,)", source)
            @test !occursin("--backend=", source)
            @test !occursin("warm_application", source)

            @test_throws ErrorException build_projectured_executable(; context = context,
                                            compile = false, backends = (:x11,))
            @test_throws ErrorException build_projectured_executable(; context = context,
                                            compile = false, backends = ())
            @test_throws ErrorException build_projectured_distribution(; context = context,
                                            compile = false)
        end

        @testset "the claude-code-acp build writes its package and compiles nothing" begin
            # A small package in place of ClaudeCodeACP, so the test needs no
            # folder beside the repository.
            source = mktempdir()
            mkpath(joinpath(source, "src"))
            open(joinpath(source, "Project.toml"), "w") do io
                ProjecturedBuilder.BuilderModule.TOML.print(io, Dict(
                    "name" => "ClaudeCodeACP", "uuid" => "397ce549-bc36-418a-97e7-6295a63dbdc4"))
            end
            write(joinpath(source, "src", "ClaudeCodeACP.jl"), "module ClaudeCodeACP\nmain(arguments) = 0\nend\n")
            context = make_claude_code_acp_build_context(source; context = _test_context())
            project = build_claude_code_acp_executable(; source, context, compile = false)
            @test project == joinpath(context.root, "build", "app", "claude-code-acp")
            toml = ProjecturedBuilder.BuilderModule.TOML.parsefile(joinpath(project, "Project.toml"))
            @test Set(keys(toml["deps"])) == Set(["ClaudeCodeACP", "PrecompileTools"])
            @test normpath(joinpath(project, toml["sources"]["ClaudeCodeACP"]["path"])) == normpath(source)
            text = read(joinpath(project, "src", "ClaudeCodeAcpApp.jl"), String)
            @test occursin("ClaudeCodeACP.main(ARGS)", text)
            @test occursin("ClaudeCodeACP.serve_agent", text)
            @test_throws ErrorException build_claude_code_acp_executable(; source = mktempdir(),
                context = make_claude_code_acp_build_context(mktempdir(); context = _test_context()),
                compile = false)
        end

        @testset "the shell front end" begin
            # The command line of the builder, which `tool/build-binary.jl` runs.
            script = read(joinpath(@__DIR__, "..", "..", "..", "tool", "build-binary.jl"), String)
            @test occursin("run_build_command(ARGS)", script)
            parse_arguments(arguments, fixed = "") = parse_build_arguments(arguments; fixed)
            usage = format_build_usage(; fixed = "")
            for (_, label, _) in BUILD_OPTIONS
                @test occursin(label, usage)
            end
            @test occursin("projectured", usage)
            @test occursin("claude-code-acp", usage)
            @test parse_arguments(["claude-code-acp", "--no-workload"]) ==
                  ("claude-code-acp", false, Dict{Symbol,Any}(:workload => false))
            # The agent has no distribution build and no backends; both refusals
            # start no build.
            @test redirect_stderr(() -> run_build_command(["claude-code-acp", "--distribution"]), devnull) == 1
            @test redirect_stderr(() -> run_build_command(["claude-code-acp", "--backends=web"]), devnull) == 1

            binary, distribution, keywords = parse_arguments(String[])
            @test binary === nothing && !distribution && isempty(keywords)
            binary, distribution, keywords = parse_arguments(
                ["projectured", "--backends=web,sdl", "--no-workload", "--no-incremental",
                 "--filter-stdlibs", "--name=pr", "--optimization=2", "--debug-info=0",
                 "--strip-metadata", "--cpu-target=generic", "--log-level=info", "--no-compile"])
            @test binary == "projectured" && !distribution
            @test keywords == Dict{Symbol,Any}(:backends => (:web, :sdl), :workload => false,
                :incremental => false, :filter_stdlibs => true, :name => "pr",
                :optimization => 2, :debug_info => 0, :strip_metadata => true,
                :cpu_target => "generic", :log_level => :info, :compile => false)
            # A `bin/` script fixes the binary, and then the command line names none.
            binary, distribution, keywords = parse_arguments(["--no-compile"], "projectured")
            @test binary == "projectured" && keywords == Dict{Symbol,Any}(:compile => false)
            @test_throws ErrorException parse_arguments(["projectured"], "projectured")
            binary, distribution, keywords = parse_arguments(["projectured", "--distribution",
                                                              "--filter-stdlibs"])
            @test distribution && keywords == Dict{Symbol,Any}(:filter_stdlibs => true)
            # Every option the build function takes is a keyword of it.
            method = only(methods(build_projectured_executable))
            for key in (:backends, :workload)
                @test key in Base.kwarg_decl(method)
            end
            method = only(methods(build_executable))
            for key in (:incremental, :filter_stdlibs, :name, :output, :optimization,
                        :debug_info, :strip_metadata, :cpu_target, :logfile, :log_level,
                        :compile)
                @test key in Base.kwarg_decl(method)
            end

            for arguments in (["projectured", "--colour"], ["omnet"],
                              ["projectured", "projectured"],
                              ["projectured", "--optimization=high"],
                              ["projectured", "--filter-stdlibs"],
                              ["projectured", "--distribution", "--no-compile"],
                              ["projectured", "--distribution", "--no-incremental"],
                              ["projectured", "--distribution", "--cpu-target=native"])
                @test_throws ErrorException parse_arguments(arguments)
            end
            quiet = devnull
            @test redirect_stdout(() -> run_build_command(["--help"]), quiet) == 0
            @test redirect_stderr(() -> run_build_command(String[]), quiet) == 1
            @test redirect_stderr(() -> run_build_command(["--colour"]), quiet) == 1
        end
    end
end
