# ═══════════════════════════════════════════════════════════════════════════
# ProjecturedRepl — the leaf a person loads to work.
#
# A package image is built with exactly that package's dependencies present, so
# compiled code is only safe in a package that nothing depends on and nothing
# loads after. This is that package: it names the session, runs the workload,
# and is the last thing the alias loads.
#
#     julia --project=. -e 'using Revise, ProjecturedRepl'
#
# Revise stays in the alias rather than in the dependencies here: it has to be
# loaded before the packages it tracks, and as a dependency its position in the
# load order is the resolver's business.
#
# Measured on the omnetpp-julia demo, which loads the same stack: with no
# workload the first click costs 5.98 s, of which 3.88 s is `recompile_time` —
# code that was compiled into the package images and then invalidated by
# something loading later. With a workload compiled here it costs 0.55 s.
#
# See plan/pending/package-convention-repl-leaves.md.
# ═══════════════════════════════════════════════════════════════════════════

module ProjecturedRepl

using PrecompileTools: @setup_workload, @compile_workload
using Preferences: @load_preference, set_preferences!

using Projectured
using ProjecturedExample
using ProjecturedSdl
using ProjecturedTest

# Everything the four packages export is exported again, so one `using` at the
# prompt gives the session a person expects: `run_example`, `test_all`, the
# document and projection constructors, and `SdlBackend`.
#
# A name exported by two of them with different bindings would be ambiguous —
# `test_export_collisions` is the guard that keeps that from happening.
for _module in (Projectured, ProjecturedExample, ProjecturedSdl, ProjecturedTest)
    for _name in names(_module)
        _name === nameof(_module) && continue
        @eval export $_name
    end
end

"""
    WORKLOAD

How much this build compiled ahead of time: `:none`, `:minimal`, `:demo` or
`:full`. Read as a preference at module scope, so the precompile cache depends
on it and changing it rebuilds. An environment variable would not — the stale
image would be reused and the setting would quietly do nothing.
"""
const WORKLOAD = Symbol(@load_preference("workload", "minimal"))

"""
    set_workload!(level::Symbol) -> level

Choose how much the next build compiles, then restart Julia. The next `using
ProjecturedRepl` pays the build once.

| level | build | the first click, measured on the demo |
| --- | ---: | ---: |
| `:none` | 8.8 s | 5.98 s |
| `:minimal` | | |
| `:demo` | 17–22 s | 0.55 s |
| `:full` | 107–116 s | 0.24 s |

`:none` is for a day spent editing the kernel, where every build is paid and no
click is. `:full` is for showing the editor to someone.
"""
function set_workload!(level::Symbol)
    level in (:none, :minimal, :demo, :full) ||
        error("set_workload!: level must be :none, :minimal, :demo or :full, got ",
              repr(level))
    set_preferences!(@__MODULE__, "workload" => String(level); force = true)
    @info "workload level set — restart Julia for it to take effect" level
    level
end

export WORKLOAD, set_workload!

@setup_workload begin
    # Built outside the workload: constructing the documents is not what needs
    # compiling, and this keeps the measured region to the pipeline.
    _atoms = ProjecturedExample.atomic_documents()
    @compile_workload begin
        ProjecturedExample.precompile_workload(WORKLOAD; atoms = _atoms)
    end
end

end # module ProjecturedRepl
