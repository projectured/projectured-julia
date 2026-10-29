# The measurements of documentation/design/compile-ahead.md (U7), which a person
# starts by hand and which the release runs before it writes the release.
#
#     julia --project=environment/all tool/measure-compile-ahead.jl [--record] [--binaries] [--root=<checkout>]
#
# --record    record the calls of each package and of the binary `projectured`
#             first, as the release does
# --binaries  also build the binary `projectured`, and measure its build
# --root      measure another checkout of this repository, for example the one
#             of a commit before a change (default: this checkout)
#
# It measures the build time and the size of the image of each package, in a
# depot of its own; the `using` line and the first frame of the session of the
# README; the calls that the start and each gesture of the binary compile; and,
# with `--binaries`, the build time, the peak memory and the size of the binary.

using Printf

const ROOT = let given = filter(argument -> startswith(argument, "--root="), ARGS)
    normpath(isempty(given) ? joinpath(@__DIR__, "..") : abspath(last(given)[8:end]))
end
const JULIA = Base.julia_cmd()

function print_heading(text)
    println()
    println(text)
    println(repeat("─", length(text)))
end

# The size of each file under `folder`, added up.
function measure_folder_bytes(folder::AbstractString)
    isdir(folder) || return 0
    sum((filesize(joinpath(root, file)) for (root, _, files) in walkdir(folder) for file in files);
        init = 0)
end

# Each package of `environment/all`, built in a depot of its own, so that no
# image of another build is reused. The depot takes the packages, the artifacts
# and the registries of the depot of this process, so the build downloads nothing.
function measure_package_images()
    print_heading("The images of the packages")
    depot = mktempdir()
    source = first(DEPOT_PATH)
    for folder in ("packages", "artifacts", "registries", "scratchspaces", "clones")
        isdir(joinpath(source, folder)) && symlink(joinpath(source, folder), joinpath(depot, folder))
    end
    command = addenv(`$JULIA --startup-file=no --project=$(joinpath(ROOT, "environment", "all"))
                      -e "using Pkg; Pkg.precompile()"`,
                     "JULIA_DEPOT_PATH" => depot * (Sys.iswindows() ? ";" : ":"),
                     "JULIA_PKG_OFFLINE" => "true")
    output = IOBuffer()
    start = time()
    process = run(pipeline(ignorestatus(command); stdout = output, stderr = output))
    seconds = time() - start
    text = String(take!(output))
    success(process) || println(last(text, 4000))
    compiled = joinpath(depot, "compiled", "v$(VERSION.major).$(VERSION.minor)")
    rows = Tuple{String,Float64,Int}[]
    for found in eachmatch(r"(?m)^\s*([\d.]+) s\s+✓ (\S+)", text)
        name = found.captures[2]
        push!(rows, (name, parse(Float64, found.captures[1]),
                     measure_folder_bytes(joinpath(compiled, name))))
    end
    sort!(rows; by = row -> -row[2])
    for (name, build, bytes) in rows
        @printf("  %-44s %8.1f s %9.1f MB\n", name, build, bytes / 1e6)
    end
    @printf("  %-44s %8.1f s %9.1f MB\n", "all, the wall time", seconds,
            measure_folder_bytes(compiled) / 1e6)
    rm(depot; recursive = true, force = true)
    nothing
end

# The session of the README: the `using` line, and the first frame of a data
# frame of 100 000 rows, in seconds of the wall and of compilation.
const README_SESSION = raw"""
t0 = time()
using Projectured, DataFrames, ProjecturedSDL
using_seconds = time() - t0
function measure_first_frame()
    frame = DataFrames.DataFrame(n = 1:100_000, square = (1:100_000) .^ 2)
    Base.cumulative_compile_timing(true)
    before = Base.cumulative_compile_time_ns()[1]
    platform = Projectured.ProjecturedPlatform
    t1 = time()
    platform.display_in_editor(frame)
    editor = platform.DisplayModule._SESSION[].editor
    deadline = time() + 600
    while platform.ProjecturedKernel.PerformanceModule.get_frame_count(editor.frame_measurements) < 1 &&
          time() < deadline
        sleep(0.005)
    end
    wall = time() - t1
    compile = (Base.cumulative_compile_time_ns()[1] - before) / 1e9
    platform.close_display_editor!()
    (wall, compile)
end
(wall, compile) = measure_first_frame()
println("README ", using_seconds, " ", wall, " ", compile)
"""

function measure_readme_session(; runs::Integer = 3)
    print_heading("The session of the README (the median of $runs runs)")
    results = NTuple{3,Float64}[]
    for _ in 1:runs
        command = addenv(`$JULIA --startup-file=no --project=$(joinpath(ROOT, "environment", "readme-data-frame"))
                          -e $README_SESSION`, "SDL_VIDEODRIVER" => "offscreen")
        found = match(r"README (\S+) (\S+) (\S+)", read(ignorestatus(command), String))
        found === nothing || push!(results, Tuple(parse.(Float64, found.captures)))
    end
    if isempty(results)
        println("  the session printed no result")
        return nothing
    end
    median(values) = sort(values)[cld(length(values), 2)]
    @printf("  %-44s %8.2f s\n", "the using line", median(first.(results)))
    @printf("  %-44s %8.2f s\n", "the first frame", median(getindex.(results, 2)))
    @printf("  %-44s %8.2f s\n", "the part of the first frame that compiles", median(last.(results)))
    nothing
end

# The guards: what the first window and each gesture of the binary compile.
function measure_gestures()
    print_heading("The calls that the start and each gesture compile")
    @eval using ProjecturedTest, Test
    Base.invokelatest() do
        ProjecturedTest.test_first_window_compiles_little()
        ProjecturedTest.test_gestures_compile_little()
    end
    nothing
end

# The binary `projectured`: the build time, the peak memory of the build and the
# size of the bundle. The peak memory needs `/usr/bin/time`.
function measure_binary()
    print_heading("The binary projectured")
    command = `$(joinpath(ROOT, "bin", "build_projectured"))`
    time_tool = "/usr/bin/time"
    report = tempname()
    isfile(time_tool) && (command = `$time_tool -f "%M" -o $report $command`)
    start = time()
    process = run(ignorestatus(command))
    seconds = time() - start
    success(process) || println("  the build failed")
    @printf("  %-44s %8.1f s\n", "the build time", seconds)
    if isfile(report)
        kilobytes = parse(Int, strip(last(readlines(report))))
        @printf("  %-44s %8.1f GiB\n", "the peak memory of the build", kilobytes / 2^20)
    end
    @printf("  %-44s %8.1f MB\n", "the bundle",
            measure_folder_bytes(joinpath(ROOT, "build", "projectured")) / 1e6)
    nothing
end

function record_calls()
    print_heading("The recording")
    @eval using ProjecturedPrecompile
    Base.invokelatest() do
        for path in ProjecturedPrecompile.record_repository_calls!(; root = ROOT)
            println("  ", relpath(path, ROOT))
        end
        for path in ProjecturedPrecompile.record_application_calls!("ProjecturedBuild", "projectured";
                                                                     root = ROOT)
            println("  ", relpath(path, ROOT))
        end
    end
    nothing
end

function main(arguments)
    unknown = filter(argument -> !(argument in ("--record", "--binaries") ||
                                   startswith(argument, "--root=")), arguments)
    isempty(unknown) || (println(stderr, "unknown option ", first(unknown)); return 1)
    println("Measuring ", ROOT)
    "--record" in arguments && record_calls()
    # A measurement that fails says so and does not stop the others.
    failed = false
    for measure in (measure_package_images, measure_readme_session, measure_gestures,
                    ("--binaries" in arguments ? (measure_binary,) : ())...)
        try
            measure()
        catch exception
            failed = true
            println("  the measurement failed: ", first(split(sprint(showerror, exception), "\n")))
        end
    end
    failed ? 1 : 0
end

exit(main(ARGS))
