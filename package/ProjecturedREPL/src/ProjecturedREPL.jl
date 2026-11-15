# ═══════════════════════════════════════════════════════════════════════════
# ProjecturedREPL — the leaf a person loads to work.
#
#     julia --project=environment/all -e 'using Revise, ProjecturedREPL'
#
# One `using` gives the session a person expects. The code of the session is
# compiled ahead of time in the images of the packages below, as their
# preferences `precompile_calls` say; see documentation/design/compile-ahead.md.
#
# Revise stays in the alias rather than in the dependencies here: it has to be
# loaded before the packages it tracks, and as a dependency its position in the
# load order is the resolver's business.
# ═══════════════════════════════════════════════════════════════════════════

module ProjecturedREPL

using ProjecturedAll
using ProjecturedExample
using ProjecturedSDL
using ProjecturedTest

# Everything the four packages export is exported again, so one `using` at the
# prompt gives the session a person expects: `run_example`, `test_all`, the
# document and projection constructors, and `SdlBackend`.
#
# A name exported by two of them with different bindings would be ambiguous —
# `test_export_collisions` is the guard that keeps that from happening.
for _module in (ProjecturedAll, ProjecturedExample, ProjecturedSDL, ProjecturedTest)
    for _name in names(_module)
        _name === nameof(_module) && continue
        @eval export $_name
    end
end

end # module ProjecturedREPL
