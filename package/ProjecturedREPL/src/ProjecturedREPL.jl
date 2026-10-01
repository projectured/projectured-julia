# ═══════════════════════════════════════════════════════════════════════════
# ProjecturedREPL — the leaf a person loads to work.
#
# A package image is built with exactly that package's dependencies present, so
# compiled code is only safe in a package that nothing depends on and nothing
# loads after. This is that package: it names the session, runs the workload,
# and is the last thing the alias loads.
#
#     julia --project=environment/all -e 'using Revise, ProjecturedREPL'
#
# Revise stays in the alias rather than in the dependencies here: it has to be
# loaded before the packages it tracks, and as a dependency its position in the
# load order is the resolver's business.
#
# Measured on a downstream demo, which loads the same stack: with no
# workload the first click costs 5.98 s, of which 3.88 s is `recompile_time` —
# code that was compiled into the package images and then invalidated by
# something loading later.
#
# What this build compiles is `WORKLOAD`. The default replays a recording rather
# than running a workload, because a workload only compiles what somebody
# thought to run and nobody thought to read: measured on the json example, the
# read half of a first click is 221 ms replaying a recording and 1494 ms running
# the workload.
#
# See plan/pending/package-convention-repl-leaves.md and
# plan/done/recorded-precompile-workload.md.
# ═══════════════════════════════════════════════════════════════════════════

module ProjecturedREPL

using Projectured
using ProjecturedExample
using ProjecturedSDL
using ProjecturedTest

# Everything the four packages export is exported again, so one `using` at the
# prompt gives the session a person expects: `run_example`, `test_all`, the
# document and projection constructors, and `SdlBackend`.
#
# A name exported by two of them with different bindings would be ambiguous —
# `test_export_collisions` is the guard that keeps that from happening.
for _module in (Projectured, ProjecturedExample, ProjecturedSDL, ProjecturedTest)
    for _name in names(_module)
        _name === nameof(_module) && continue
        @eval export $_name
    end
end

include("../../../source/tool/repl/ReplModule.jl")

# A person loads this package by name, so its names are exported here.
using .ReplModule: WORKLOAD, set_workload!, get_workload, PRECOMPILE_STATEMENTS,
                   replay_precompile_statements, record_precompile_statements
export WORKLOAD, set_workload!, get_workload, PRECOMPILE_STATEMENTS,
       replay_precompile_statements, record_precompile_statements

end # module ProjecturedREPL
