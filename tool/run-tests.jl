# usage: julia --project=environment/all tool/run-tests.jl [options] PACKAGE SUITE [PACKAGE SUITE ...]
#
# Run the parts of the suites in worker processes, each part with a time limit
# and a memory limit, and print a summary. This process loads no package; the
# workers load the test packages. `--help` gives the options.
#
#     julia --project=environment/all tool/run-tests.jl ProjecturedPlatformTest test_platform
include(joinpath(@__DIR__, "..", "test", "kernel", "runner", "TestSupervisor.jl"))
exit(run_test_supervisor(ARGS))
