# ── Document layer (layer 2 — the contract) ────────────────────────────────
# The ordered include list of the document layer; a fragment of ProjecturedKernel.
# The Document abstract type, the selection generics, the shared @document
# machinery. DocumentModule.jl is the aggregator; it includes Interface.jl
# (the contract fragment) then Document.jl (the machinery fragment).
include("DocumentModule.jl")
# The animation clock (a `Cell`-backed time value), relocated here from the cell
# layer — it belongs with the document model, not the reactive engine. Depends
# only on `Cell`. Pending the clock-as-document redesign that renames it
# `Clock.jl`; see plan/pending/per-editor-animation-clock.md.
include("Time.jl")
