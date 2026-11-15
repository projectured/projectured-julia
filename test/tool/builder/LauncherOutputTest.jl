# The output of the slow work of a launcher: a work that ends within its time
# shows nothing, a slow work shows the notice and all of its output, and a work
# that fails shows its output and its error. Each case runs in a process of its
# own, with the file included alone, as a launcher includes it.

const _LAUNCHER_OUTPUT_FILE = normpath(joinpath(@__DIR__, "..", "..", "..", "source", "tool", "builder",
                                                "LauncherOutput.jl"))

# The standard output and the error output of a process that runs `code` after the
# include, and whether it ended well.
function _run_launcher_output(code::AbstractString)
    script = string("launcher = Module()\n",
                    "Base.include(launcher, ", repr(_LAUNCHER_OUTPUT_FILE), ")\n",
                    code)
    output = Pipe()
    errors = Pipe()
    process = run(pipeline(`$(Base.julia_cmd()) --startup-file=no -e $script`; stdout = output, stderr = errors);
                  wait = false)
    close(output.in)
    close(errors.in)
    reading = @async read(errors, String)
    printed = read(output, String)
    wait(process)
    (printed, fetch(reading), success(process))
end

function test_launcher_output()
    @testset "a launcher shows the output of its preparation when it is slow" begin
        (printed, errors, ok) = _run_launcher_output("""
            print(launcher.run_with_slow_output(; notice = "NOTICE", after = 5.0) do
                println(stderr, "a line of quick work"); @info "a log of quick work"; "quick"
            end)""")
        @test ok && printed == "quick" && errors == ""
        (printed, errors, ok) = _run_launcher_output("""
            print(launcher.run_with_slow_output(; notice = "NOTICE", after = 0.2) do
                println(stderr, "held"); sleep(1.0); println(stderr, "live"); @info "a log"; "slow"
            end)""")
        @test ok && printed == "slow"
        @test startswith(errors, "NOTICE\nheld\nlive\n") && occursin("a log", errors)
        (printed, errors, ok) = _run_launcher_output("""
            launcher.run_with_slow_output(; notice = "NOTICE", after = 5.0) do
                println(stderr, "before the failure"); error("it failed")
            end""")
        @test !ok && startswith(errors, "NOTICE\nbefore the failure\n") && occursin("it failed", errors)
    end
end
