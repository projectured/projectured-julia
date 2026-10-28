# The parts of the recording that need no process: the trace, the list, the
# graph of the dependencies, and the package that keeps a call.

function _write_text_file!(path::AbstractString, text::AbstractString)
    mkpath(dirname(path))
    write(path, text)
    path
end

"""
    test_precompile_recording()

The trace keeps each call once and drops what it cannot read back, a list reads
back what it wrote, and a call goes to the lowest package that sees what it
names.
"""
function test_precompile_recording()
    @testset "recording" begin
        mktempdir() do folder
            @testset "the trace" begin
                trace = _write_text_file!(joinpath(folder, "trace.jl"), """
                    precompile(Tuple{typeof(Base.sum), Array{Int64, 1}})
                    precompile(Tuple{typeof(Base.sum), Array{Int64, 1}})
                    precompile(Tuple{typeof(Main.driver), Int64})
                    precompile(Tuple{typeof(Base.length), String}) # recompile
                    #= 12.5 ms =# precompile(Tuple{typeof(Base.first), String})
                    precompile(Tuple{typeof(Base.last), )
                    not a call
                    """)
                @test collect_traced_calls(trace) == ["Tuple{typeof(Base.first), String}",
                                                      "Tuple{typeof(Base.length), String}",
                                                      "Tuple{typeof(Base.sum), Array{Int64, 1}}"]
            end
            @testset "the list" begin
                path = joinpath(folder, "Probe", "precompile", "workload.txt")
                calls = ["Tuple{typeof(Base.sum), Array{Int64, 1}}", "Tuple{typeof(Base.length), String}"]
                @test write_recorded_calls!(path, calls; workload = "Probe") == path
                @test read_recorded_calls(path) == calls
                @test startswith(read(path, String), "# The calls that the workload of Probe compiled")
                write_recorded_calls!(path, String[]; workload = "Probe")
                @test !isfile(path)
            end
            @testset "the repository" begin
                root = joinpath(folder, "repository")
                _write_text_file!(joinpath(root, "package", "Low", "src", "Low.jl"),
                                  "module Low\nusing ProjecturedPrecompile: @compile_ahead\n@compile_ahead\nend\n")
                _write_text_file!(joinpath(root, "package", "Quiet", "src", "Quiet.jl"),
                                  "module Quiet\n# @compile_ahead is only named here\nend\n")
                @test collect_compiling_packages(root) == ["Low"]
                @test find_repository_root(joinpath(root, "package", "Low", "src")) == root
                @test find_repository_root(folder) === nothing
                manifest = _write_text_file!(joinpath(root, "environment", "all", "Manifest.toml"), """
                    manifest_format = "2.0"
                    [[deps.Low]]
                    deps = ["Base64"]
                    [[deps.High]]
                    deps = ["Low"]
                    [[deps.Base64]]
                    """)
                closures = collect_package_closures(dirname(manifest))
                @test closures["High"] == Set(["High", "Low", "Base64"])
                @test closures["Base64"] == Set(["Base64"])
            end
            @testset "the owner of a call" begin
                closures = Dict("Kernel" => Set(["Kernel"]),
                                "Platform" => Set(["Platform", "Kernel"]),
                                "Json" => Set(["Json", "Platform", "Kernel"]),
                                "Graph" => Set(["Graph", "Platform", "Kernel"]),
                                "Fsm" => Set(["Fsm", "Graph", "Platform", "Kernel"]),
                                "Application" => Set(["Application", "Json", "Graph", "Fsm",
                                                      "Platform", "Kernel"]))
                candidates = ["Platform", "Json", "Graph", "Fsm", "Application"]
                owner(call) = find_call_owner(call, candidates, closures; fallback = "Application")
                # The lowest package that sees what the call names.
                @test owner("Tuple{typeof(Platform.f), Graph.Node}") == "Graph"
                @test owner("Tuple{typeof(Platform.f), Kernel.Cell}") == "Platform"
                # Base and a module that the manifest does not name are seen by all.
                @test owner("Tuple{typeof(Base.sum), Array{Int64, 1}}") == "Platform"
                # A call that joins two packages, where neither depends on the other.
                @test owner("Tuple{typeof(Json.f), Graph.Node}") == "Application"
                # The fallback when no candidate sees the call.
                @test find_call_owner("Tuple{typeof(Json.f), Graph.Node}", ["Json", "Graph"], closures;
                                      fallback = "Application") == "Application"
                owners = compute_call_owners(["Tuple{typeof(Platform.f), Graph.Node}",
                                              "Tuple{typeof(Json.f), Graph.Node}",
                                              "Tuple{typeof(Fsm.f), Graph.Node}"],
                                             candidates, closures; fallback = "Application")
                @test owners == Dict("Graph" => ["Tuple{typeof(Platform.f), Graph.Node}"],
                                     "Fsm" => ["Tuple{typeof(Fsm.f), Graph.Node}"],
                                     "Application" => ["Tuple{typeof(Json.f), Graph.Node}"])
            end
        end
    end
end
