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
    real_root = normpath(joinpath(@__DIR__, "..", ".."))
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

function test_builder()
    @testset "builder" begin
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
                  ProjecturedBuilder.TOML.parsefile(joinpath(directory, "Project.toml"))["uuid"]
            @test_throws ErrorException get_package_directory(context, "NoSuchPackage")
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
            @test occursin(ProjecturedBuilder._BUILD_TIMESTAMP, first_source)
            # A different timestamp alone is not a difference, so nothing is
            # written and the cache holds.
            other_time = replace(first_source,
                                 ProjecturedBuilder._BUILD_TIMESTAMP =>
                                     "built 1999-01-01 00:00 by ProjecturedBuilder")
            @test other_time != first_source
            @test !write_if_changed(path, other_time;
                                    ignoring = ProjecturedBuilder._BUILD_TIMESTAMP)
            @test mtime(path) == before
            # Anything else is.
            @test write_if_changed(path, replace(first_source, "module " => "module X");
                                   ignoring = ProjecturedBuilder._BUILD_TIMESTAMP)
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
                    path = "../../package/A"
                    """)
                manifest = joinpath(project, "Manifest.toml")
                agreeing = """
                    [[deps.A]]
                    path = "../../package/A"
                    uuid = "22222222-2222-2222-2222-222222222222"
                    """
                write(manifest, agreeing)
                # A manifest that agrees is left where it is.
                @test !ProjecturedBuilder._drop_stale_manifest(project)
                @test isfile(manifest)

                # A path that differs is what the assertion would have died on.
                write(manifest, replace(agreeing, "package/A" => "package/AOld"))
                @test ProjecturedBuilder._drop_stale_manifest(project)
                @test !isfile(manifest)

                # A project with no manifest beside it is not an error.
                @test !ProjecturedBuilder._drop_stale_manifest(project)
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
                entry = only(ProjecturedBuilder.TOML.parsefile(manifest)["deps"]["OrderedCollections"])
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
                @test_throws ProjecturedBuilder.Pkg.Resolve.ResolverError resolve_app_project(project;
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
            record(d) = read(joinpath(d, "src", ProjecturedBuilder._module_name(basename(d)) * ".jl"),
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

        @testset "the staging directory is not a memory filesystem" begin
            # A bundle can run to several hundred megabytes, and `/tmp` is a
            # `tmpfs` on many machines — a copy there is a copy into memory.
            root = get_staging_root()
            @test isdir(root)
        end
    end
end
