# The first window of a data frame compiles little. Each package that the session
# of the README loads holds the code of its first window in its image, and no
# package loaded after it invalidates that code, by the rules of package-rules.md
# under "A package that a user loads compiles its own first window".

# The seconds of compilation that the first window may take, in a fresh process,
# from the call of `display_in_editor` until the editor has drawn a frame. Measured
# on 2026-10-08: 0.65 s; with no workloads, more than 40 s.
const _FIRST_WINDOW_COMPILE_LIMIT = 2.0

# The session of the README in a fresh process: the packages load by their ids, so
# a package that the environment holds but does not list loads too. It prints the
# seconds of compilation of the first window.
const _FIRST_WINDOW_SESSION = raw"""
_load(uuid, name) = Base.require(Base.PkgId(Base.UUID(uuid), name))
_load("92922de3-b970-4d9a-8b2a-9d6f361397b5", "Projectured")
const DataFrames = _load("a93c6f00-e57d-5684-b7b6-d8193f3e46c0", "DataFrames")
_load("f0002b97-94ba-416c-b93c-86cdc095626f", "ProjecturedSDL")
const Kernel = _load("a3e3499a-684d-4df9-a0d6-de2d1797b1f3", "ProjecturedKernel")
const Platform = _load("b21cb890-5227-4e91-ae0e-8ab4d844f9f7", "ProjecturedPlatform")
function compute_first_window_compile_seconds()
    frame = DataFrames.DataFrame(n = 1:100_000, square = (1:100_000) .^ 2)
    Base.cumulative_compile_timing(true)
    before = Base.cumulative_compile_time_ns()[1]
    Platform.display_in_editor(frame)
    editor = Platform.DisplayModule._SESSION[].editor
    deadline = time() + 600
    while Kernel.PerformanceModule.get_frame_count(editor.frame_measurements) < 1 && time() < deadline
        sleep(0.005)
    end
    seconds = (Base.cumulative_compile_time_ns()[1] - before) / 1e9
    Platform.close_display_editor!()
    seconds
end
println("FIRST WINDOW COMPILED ", compute_first_window_compile_seconds())
"""

function test_first_window_compiles_little()
    @testset "the first window of a data frame compiles little" begin
        command = addenv(`$(Base.julia_cmd()) --startup-file=no --project=$(Base.active_project())
                          -e $_FIRST_WINDOW_SESSION`, "SDL_VIDEODRIVER" => "offscreen")
        output = read(pipeline(ignorestatus(command); stderr = devnull), String)
        found = match(r"FIRST WINDOW COMPILED ([0-9.e+-]+)", output)
        @test found !== nothing
        if found !== nothing
            seconds = parse(Float64, found[1])
            seconds < _FIRST_WINDOW_COMPILE_LIMIT ||
                println(stderr, "\nthe first window compiled for ", seconds, " s")
            @test seconds < _FIRST_WINDOW_COMPILE_LIMIT
        end
    end
end
