# ── Reference layer (layer 3) ───────────────────────────────────────────────
# The ordered include list of the reference layer; a fragment of ProjecturedKernel.
# Reference machinery: paths, steps, the builder and the case macro. Declares
# open seams (generics) that `package/base` extends for its concrete documents
# and document-shaped projections; the kernel itself carries no concrete
# document.
include("ReferenceModule.jl")
