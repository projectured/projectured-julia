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
# The command runs in an environment that holds `ProjecturedPrecompile`, and each
# measurement runs in a new process of the environment of the measured checkout,
# so a checkout from before the change can be measured too.
#
# It measures the build time and the size of the image of each package, in a
# depot of its own; the `using` line and the first frame of the session of the
# README; the calls that the start and each gesture of the binary compile; and,
# with `--binaries`, the build time, the peak memory and the size of the binary.

# The parts that each repository measures the same way are in
# `ProjecturedPrecompile`: the images of the packages, the timings of new
# processes and the build of a binary.

using ProjecturedPrecompile: measure_package_images, measure_process_median,
                             measure_binary_build, record_repository_calls!,
                             record_application_calls!

const ROOT = let given = filter(argument -> startswith(argument, "--root="), ARGS)
    normpath(isempty(given) ? joinpath(@__DIR__, "..") : abspath(last(given)[8:end]))
end
const JULIA = Base.julia_cmd()

function print_heading(text)
    println()
    println(text)
    println(repeat("─", length(text)))
end

# Each package of `environment/all`, built in a depot of its own.
function measure_images()
    print_heading("The images of the packages")
    measure_package_images(joinpath(ROOT, "environment", "all"))
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
println("MEASUREMENT the using line: ", using_seconds)
println("MEASUREMENT the first frame: ", wall)
println("MEASUREMENT the part of the first frame that compiles: ", compile)
"""

function measure_readme_session(; runs::Integer = 3)
    print_heading("The session of the README (the median of $runs runs)")
    command = addenv(`$JULIA --startup-file=no --project=$(joinpath(ROOT, "environment", "readme-data-frame"))
                      -e $README_SESSION`, "SDL_VIDEODRIVER" => "offscreen")
    measure_process_median(command; runs)
    nothing
end

# The guards: what the first window and each gesture of the binary compile, in a
# process of the environment of the measured checkout.
function measure_gestures()
    print_heading("The calls that the start and each gesture compile")
    script = "using ProjecturedTest, Test; " *
             "ProjecturedTest.test_first_window_compiles_little(); " *
             "ProjecturedTest.test_gestures_compile_little()"
    run(ignorestatus(`$JULIA --startup-file=no --project=$(joinpath(ROOT, "environment", "all")) -e $script`))
    nothing
end

# The binary `projectured`: the build time, the peak memory of the build and the
# size of the bundle. The peak memory needs `/usr/bin/time`.
function measure_binary()
    print_heading("The binary projectured")
    measure_binary_build(`$(joinpath(ROOT, "bin", "build_projectured"))`,
                         joinpath(ROOT, "build", "projectured"))
    nothing
end

function record_calls()
    print_heading("The recording")
    for path in record_repository_calls!(; root = ROOT)
        println("  ", relpath(path, ROOT))
    end
    for path in record_application_calls!("ProjecturedBuild", "projectured"; root = ROOT)
        println("  ", relpath(path, ROOT))
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
    for measure in (measure_images, measure_readme_session, measure_gestures,
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
