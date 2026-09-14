# ── Operation layer — a fragment of ProjecturedKernel ──────────────────────
include("OperationModule.jl")
# Intent — the reader-side protocol data type, pairing the input that arrived with
# the operation it became. Its second half IS an operation, and the binding layer
# above must build one, so it belongs here rather than with the projection
# interface.
include("IntentModule.jl")
