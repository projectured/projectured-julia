# ── Editor layer — the read-eval-print loop ────────────────────────────────
# The ordered include list of the editor layer; a fragment of ProjecturedKernel.
# The feed contract loads first: `Editor` holds a `Vector{Feed}`. The frame
# sample store loads with it: `Editor` holds one, and the loop folds into it.
include("FeedModule.jl")
include("FrameSampleModule.jl")
include("EditorModule.jl")
# Scripted live playback builds on the editor loop, so it loads last.
include("PlaybackModule.jl")
