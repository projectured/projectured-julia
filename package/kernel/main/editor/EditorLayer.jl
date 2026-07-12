# ── Editor layer (layer 10 — the read-eval-print loop) ──────────────────────
# The ordered include list of the editor layer; a fragment of ProjecturedKernel.
include("Editor.jl")
# Scripted live playback builds on the editor loop, so it loads last.
include("Playback.jl")
