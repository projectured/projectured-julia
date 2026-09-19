# ── Editor layer — the read-eval-print loop ────────────────────────────────
# The ordered include list of the editor layer; a fragment of ProjecturedKernel.
# The feed contract loads first: `Editor` holds a `Vector{Feed}`.
include("FeedModule.jl")
include("EditorModule.jl")
# Scripted live playback builds on the editor loop, so it loads last.
include("PlaybackModule.jl")
