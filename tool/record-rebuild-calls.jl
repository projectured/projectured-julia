# Record the calls that the build process compiles in a reactive rebuild into
# `package/ProjecturedBuilder/precompile/rebuild.txt`, from a file that
# `--trace-compile` wrote:
#
#     julia --project=environment/build --trace-compile=<trace> tool/build-binary.jl projectured
#     julia --project=environment/build tool/record-rebuild-calls.jl <trace>
#
# The traced build must be a rebuild: its output holds a reactive store, and the
# Julia is the reactive one. The preference `precompile_calls` of
# `ProjecturedBuilder` must be "none" for the traced build, so that the trace
# sees the calls that the list holds now. The list keeps the calls that
# `ProjecturedBuilder` sees. PackageCompiler, which a build loads by its
# identity, compiles its own rebuild path in its package image.

using ProjecturedBuilder

const PRECOMPILE = Base.require(Base.PkgId(Base.UUID("8baac0ef-e501-42fc-bcd5-0b2a8f58a069"),
                                           "ProjecturedPrecompile"))
const ROOT = normpath(joinpath(@__DIR__, ".."))

length(ARGS) == 1 || error("record-rebuild-calls: give the file that --trace-compile wrote")
calls = PRECOMPILE.collect_traced_calls(only(ARGS))
closures = PRECOMPILE.collect_package_closures(joinpath(ROOT, "environment", "build"))
kept = filter(call -> PRECOMPILE.find_call_owner(call, ["ProjecturedBuilder"], closures;
                                                 fallback = "") == "ProjecturedBuilder", calls)
path = PRECOMPILE.write_recorded_calls!(joinpath(ROOT, "package", "ProjecturedBuilder",
                                                 "precompile", "rebuild.txt"),
                                        kept; workload = "rebuild")
println("record-rebuild-calls: ", length(kept), " of ", length(calls), " calls in ", path)
