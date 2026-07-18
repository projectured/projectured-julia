# ── Backend layer — rendering targets ──────────────────────────────────────
# The ordered include list of the backend layer; a fragment of ProjecturedKernel.
# BackendModule declares the abstract Backend and the backend generics a backend
# package implements (lifecycle, text measurement, device I/O, display query,
# device configuration, image/video output, pointer position).
include("BackendModule.jl")
include("HeadlessBackend.jl")
