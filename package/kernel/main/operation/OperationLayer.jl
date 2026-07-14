# ── Operation layer ────────────────────────────────────────────────────────
# The ordered include list of the operation layer; a fragment of ProjecturedKernel.
# The operation contract and the shared operations (selection replacement,
# value replacement, compounds) plus rerooting. Like the reference layer, it
# declares open seams (generics) that `package/base` extends for its concrete
# documents.
include("OperationModule.jl")
