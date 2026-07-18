# ── IoMap layer — a fragment of ProjecturedKernel ──────────────────────────
# Two modules: IoMapApiModule declares the `IoMap` contract (the supertype and
# its accessors); IoMapModule holds the concrete IO maps and imports the
# contract, so it loads second.
include("IoMapApi.jl")
include("IoMap.jl")
