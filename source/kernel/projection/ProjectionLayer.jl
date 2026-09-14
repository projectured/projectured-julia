# ── Projection layer ───────────────────────────────────────────────────────
# One module. It holds the projection contract, the fallback of each of its
# generics, the two codegen macros, the printer context, the reference step a
# projection introduces, and the open-generic seams a higher package registers
# against. The concrete projection algebra — the generic and the higher-order
# combinators — is domain-independent framework that sinks to a higher package,
# not here. The IO maps it builds on are the layer below (`iomap/`).
#
# A fragment of ProjecturedKernel.
include("ProjectionModule.jl")
