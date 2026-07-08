# ── Document layer (layer 2 — the contract) ────────────────────────────────
# The ordered include list of the document layer; a fragment of ProjecturedKernel.
# The Document abstract type, the selection generics, the shared @document
# machinery. DocumentModule.jl is the aggregator; it includes Interface.jl
# (the contract fragment) then Document.jl (the machinery fragment).
include("DocumentModule.jl")
