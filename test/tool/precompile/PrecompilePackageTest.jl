# A probe package in a temporary repository, built in new processes at each value
# of its two preferences, and recorded once.

const _PROBE = "CompileAheadProbe"

const _PROBE_SOURCE = """
    module CompileAheadProbe
    using ProjecturedPrecompile: @compile_ahead
    struct Thing
        value::Int
    end
    double(thing::Thing) = Thing(2 * thing.value)
    @compile_ahead begin
        marker = get(ENV, "COMPILE_AHEAD_PROBE_MARKER", "")
        isempty(marker) || write(marker, "ran")
        get(ENV, "COMPILE_AHEAD_PROBE_FAILS", "") == "yes" && error("the probe fails on purpose")
        double(Base.inferencebarrier(Thing(1)))
    end
    end
    """

const _PROBE_CALL = "Tuple{typeof(CompileAheadProbe.double), CompileAheadProbe.Thing}"

# The repository of the probe: its package, and an environment that holds it and
# `ProjecturedPrecompile`, resolved with no network.
function _make_probe_repository(root::AbstractString)
    precompile_folder = dirname(dirname(pathof(ProjecturedPrecompile)))
    precompile_uuid = string(Base.PkgId(ProjecturedPrecompile).uuid)
    probe_folder = joinpath(root, "package", _PROBE)
    probe_uuid = string(Base.UUID(rand(UInt128)))
    _write_text_file!(joinpath(probe_folder, "Project.toml"), """
        name = "$_PROBE"
        uuid = "$probe_uuid"
        version = "0.1.0"
        [deps]
        ProjecturedPrecompile = "$precompile_uuid"
        [sources]
        ProjecturedPrecompile = {path = $(repr(precompile_folder))}
        """)
    _write_text_file!(joinpath(probe_folder, "src", _PROBE * ".jl"), _PROBE_SOURCE)
    environment = joinpath(root, "environment", "all")
    _write_text_file!(joinpath(environment, "Project.toml"), """
        [deps]
        $_PROBE = "$probe_uuid"
        ProjecturedPrecompile = "$precompile_uuid"
        [sources]
        $_PROBE = {path = $(repr(probe_folder))}
        ProjecturedPrecompile = {path = $(repr(precompile_folder))}
        """)
    resolved = _run_probe_process(environment, "using Pkg; Pkg.resolve(io = devnull)"; depots = String[])
    resolved.success || error("The environment of the probe did not resolve:\n", resolved.output)
    environment
end

# Run `script` in a new process of `environment`, with `depots` first on the
# depot path, so that the images of the probe go there. Answers whether the
# process succeeded and what it wrote.
function _run_probe_process(environment::AbstractString, script::AbstractString;
                            depots::Vector{String}, variables::Vector{Pair{String,String}} = Pair{String,String}[],
                            flags::Cmd = ``)
    depot_path = join([depots; DEPOT_PATH], Sys.iswindows() ? ';' : ':')
    command = `$(Base.julia_cmd()) --startup-file=no --project=$environment $flags -e $script`
    command = addenv(command, "JULIA_DEPOT_PATH" => depot_path, "JULIA_PKG_OFFLINE" => "true", variables...)
    output = IOBuffer()
    process = run(pipeline(ignorestatus(command); stdout = output, stderr = output))
    (success = success(process), output = String(take!(output)))
end

function _write_probe_preferences!(environment::AbstractString, calls::String, failure::String)
    write(joinpath(environment, "LocalPreferences.toml"),
          "[$_PROBE]\nprecompile_calls = \"$calls\"\nprecompile_failure = \"$failure\"\n")
end

"""
    test_compile_ahead()

A probe package compiles nothing at `"none"`, runs its workload at `"live"`,
compiles its recorded calls at `"recorded"`, fails as `precompile_failure` says,
refuses an unknown value, and records its workload into `precompile/workload.txt`.
"""
function test_compile_ahead()
    @testset "compile ahead" begin
        mktempdir() do folder
            root = joinpath(folder, "repository")
            environment = _make_probe_repository(root)
            list = joinpath(root, "package", _PROBE, "precompile", "workload.txt")
            shared = mkpath(joinpath(folder, "shared-depot"))
            @test _run_probe_process(environment, "using ProjecturedPrecompile"; depots = [shared]).success
            case_count = Ref(0)
            # Each case builds the probe in a depot of its own, because the image
            # does not depend on the variables of the process.
            function run_case(calls, failure, script; fails = false, flags = ``)
                _write_probe_preferences!(environment, calls, failure)
                depot = mkpath(joinpath(folder, "depot-$(case_count[] += 1)"))
                marker = joinpath(folder, "marker-$(case_count[])")
                result = _run_probe_process(environment, script; depots = [depot, shared], flags,
                                            variables = ["COMPILE_AHEAD_PROBE_MARKER" => marker,
                                                         "COMPILE_AHEAD_PROBE_FAILS" => fails ? "yes" : "no"])
                (; result.success, result.output, ran = isfile(marker))
            end
            show_failure = "using $_PROBE; print(\"FAILURE=\", repr($_PROBE.PRECOMPILE_FAILURE))"
            call_double = "using $_PROBE; $_PROBE.double($_PROBE.Thing(2))"
            trace = joinpath(folder, "trace.jl")

            @testset "none" begin
                case = run_case("none", "warning", call_double; flags = `--trace-compile=$trace`)
                @test case.success
                @test !case.ran
                @test occursin(_PROBE_CALL, read(trace, String))
            end
            @testset "live" begin
                case = run_case("live", "warning", show_failure)
                @test case.success
                @test case.ran
                @test occursin("FAILURE=nothing", case.output)
            end
            @testset "live, a failed workload" begin
                warning = run_case("live", "warning", show_failure; fails = true)
                @test warning.success
                @test occursin("FAILURE=\"The workload of $_PROBE failed: the probe fails on purpose\"",
                               warning.output)
                @test occursin("The precompilation of $_PROBE failed, so it compiles more while it runs.",
                               warning.output)
                silent = run_case("live", "silent", show_failure; fails = true)
                @test silent.success
                @test occursin("FAILURE=nothing", silent.output)
                @test !occursin("The precompilation of $_PROBE failed", silent.output)
                stop = run_case("live", "error", show_failure; fails = true)
                @test !stop.success
                @test occursin("the probe fails on purpose", stop.output)
            end
            @testset "recorded" begin
                write_recorded_calls!(list, [_PROBE_CALL]; workload = _PROBE)
                rm(trace; force = true)
                case = run_case("recorded", "warning", call_double; flags = `--trace-compile=$trace`)
                @test case.success
                @test !case.ran
                @test !occursin(_PROBE_CALL, read(trace, String))
            end
            @testset "recorded, a stale list" begin
                stale = [_PROBE_CALL; ["Tuple{typeof($_PROBE.gone_$i), Int64}" for i in 1:9]]
                write_recorded_calls!(list, stale; workload = _PROBE)
                case = run_case("recorded", "warning", show_failure)
                @test case.success
                @test occursin("FAILURE=\"9 of the 10 recorded calls of $_PROBE no longer resolve.", case.output)
            end
            @testset "an unknown value" begin
                case = run_case("everything", "warning", show_failure)
                @test !case.success
                @test occursin("The preference `precompile_calls` of $_PROBE is \"everything\", and it must be one of",
                               case.output)
            end
            @testset "the recording" begin
                rm(list; force = true)
                _write_probe_preferences!(environment, "recorded", "warning")
                depot = mkpath(joinpath(folder, "depot-recording"))
                script = "using ProjecturedPrecompile; record_package_calls!(\"$_PROBE\"; root = $(repr(root)))"
                result = _run_probe_process(environment, script; depots = [depot, shared])
                @test result.success
                # The entry of the workload; `double` compiles inside it.
                calls = read_recorded_calls(list)
                @test "Tuple{typeof($_PROBE.run_package_workload)}" in calls
                # The images were built before the trace, so no call of a build is in it.
                @test !any(call -> occursin("Precompilation", call), calls)
            end
        end
    end
end
