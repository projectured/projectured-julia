# The first window of a data frame compiles little. Each package that the session
# of the README loads holds the code of its first window in its image, and no
# package loaded after it invalidates that code, by the rules of package-rules.md
# under "A package that a user loads compiles its own first window".

# The seconds of compilation that the first window may take, in a fresh process,
# from the call of `display_in_editor` until the editor has drawn a frame. Measured
# on 2026-10-08: 0.65 s; with no workloads, more than 40 s.
const _FIRST_WINDOW_COMPILE_LIMIT = 2.0

# The same seconds with every domain integration of the active environment
# installed, which `using Projectured` loads too. Each domain compiles its natural
# rows in its own image. Measured on 2026-10-12 in `environment/all`: 1.1 to
# 1.2 s; without the workloads of the domains, 8 to 15 s.
const _FIRST_WINDOW_WITH_DOMAINS_COMPILE_LIMIT = 3.0

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

# The project of the README session in `folder`: the packages that the README
# tells a user to add, from `environment/readme-data-frame`, and the manifest of the
# active environment with each package path made absolute, so the session loads
# the images that the active environment compiled. AutoIntegration loads the
# integrations of the packages that the project lists, so an integration that the
# active environment holds and the README does not stays out of the session.
function _make_readme_session_project(folder::String)
    readme = TOML.parsefile(joinpath(@__DIR__, "..", "..", "environment", "readme-data-frame",
                                     "Project.toml"))
    open(io -> TOML.print(io, Dict("deps" => readme["deps"])), joinpath(folder, "Project.toml"), "w")
    manifest = Base.project_file_manifest_path(Base.active_project())
    root = dirname(manifest)
    text = replace(read(manifest, String),
                   r"(?m)^path = \"(.*)\"$" => line -> _make_absolute_path_line(line, root))
    write(joinpath(folder, "Manifest.toml"), text)
    folder
end

# The line `path = "…"` of a manifest in `root`, with the path made absolute.
_make_absolute_path_line(line, root) =
    "path = \"" * normpath(joinpath(root, match(r"^path = \"(.*)\"$", line)[1])) * "\""

# The seconds of compilation of the first window of `_FIRST_WINDOW_SESSION` in a
# fresh process with the project `project`, or `nothing` when the session printed
# no result. The binary alone, with the flags of a user's session: a test runs
# with bounds checks and often with coverage, and under those flags Julia compiles
# the packages again instead of using their images.
function _measure_first_window_compile_seconds(project::String)
    julia = first(Base.julia_cmd().exec)
    command = addenv(`$julia --startup-file=no --project=$project -e $_FIRST_WINDOW_SESSION`,
                     "SDL_VIDEODRIVER" => "offscreen")
    output, errors = IOBuffer(), IOBuffer()
    run(pipeline(ignorestatus(command); stdout = output, stderr = errors))
    found = match(r"FIRST WINDOW COMPILED ([0-9.e+-]+)", String(take!(output)))
    found === nothing &&
        println(stderr, "\nthe session of the first window printed no result:\n",
                last(String(take!(errors)), 3000))
    found === nothing ? nothing : parse(Float64, found[1])
end

# The assertions on the seconds of one session.
function _test_first_window_compile_seconds(seconds, limit::Float64)
    @test seconds !== nothing
    if seconds !== nothing
        seconds < limit || println(stderr, "\nthe first window compiled for ", seconds, " s")
        @test seconds < limit
    end
end

function test_first_window_compiles_little()
    @testset "the first window of a data frame compiles little" begin
        seconds = mktempdir(folder -> _measure_first_window_compile_seconds(
            _make_readme_session_project(folder)))
        _test_first_window_compile_seconds(seconds, _FIRST_WINDOW_COMPILE_LIMIT)
    end
    @testset "the first window of a data frame compiles little with every domain installed" begin
        seconds = _measure_first_window_compile_seconds(Base.active_project())
        _test_first_window_compile_seconds(seconds, _FIRST_WINDOW_WITH_DOMAINS_COMPILE_LIMIT)
    end
end
