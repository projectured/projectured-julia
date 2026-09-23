# The report of the argument guard: how many positional arguments the
# definitions of `source/` and `example/` take, and every public one over the
# rule of three. See documentation/rule/code-quality-rules.md §4.
#
#     julia tool/survey-arguments.jl
#
# The guard itself is `test/suite/arguments.jl`, and it holds the parser, the
# protocol list and the ledger. It answers what fails:
#
#     julia test/suite/arguments.jl

include(joinpath(@__DIR__, "..", "test", "suite", "arguments.jl"))

argument_report(normpath(joinpath(@__DIR__, "..")))
