# ============================================================================
# The part of the kernel suite that tests the supervisor of `tool/run-tests.jl`.
#
# The package does not include the supervisor (`TestSupervisor.jl`) or its test
# (`TestSupervisorTest.jl`): this part includes both at run time into a module of
# its own, as `tool/run-tests.jl` includes the supervisor, so a change of the
# supervisor compiles no test package.
# ============================================================================

"""
    test_supervised_runs()

Run the test of the supervisor of `tool/run-tests.jl` (`run_supervisor_tests` of
`TestSupervisorTest.jl`), with the supervisor and its test loaded now into a module
of their own.
"""
function test_supervised_runs()
    tests = Module(:SupervisorTests)
    # A module that `Module` makes has an `include` of its own on a newer Julia,
    # and none on an older one.
    isdefined(tests, :include) ||
        Core.eval(tests, :(include(path::AbstractString) = Base.include($tests, path)))
    Core.eval(tests, :(using Test))
    Core.eval(tests, :(using ProjecturedKernelTest: read_name_filter, read_part_records))
    Base.include(tests, joinpath(@__DIR__, "TestSupervisor.jl"))
    Base.include(tests, joinpath(@__DIR__, "TestSupervisorTest.jl"))
    # The supervisors of the test must not grow or lower the cap of the job that runs it.
    withenv("BOUNDED_RUN_JOB" => nothing, "BOUNDED_RUN_BIN" => nothing) do
        Base.invokelatest(getglobal(tests, :run_supervisor_tests))
    end
end
