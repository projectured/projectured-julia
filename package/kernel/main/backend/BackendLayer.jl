# ── Backend layer — rendering targets ──────────────────────────────────────
# The ordered include list of the backend layer; a fragment of ProjecturedKernel.
# BackendModule declares the abstract Backend and the batch generics
# (initialize_backend!, quit_backend!, measure_text, write_image, record_video,
# render_canvas, decode_image, get_pointer_position). DisplayModule holds the
# display-size query with a provider indirection.
include("BackendModule.jl")
include("Display.jl")
include("HeadlessBackend.jl")
