# ── Backend layer (layer 6 — rendering targets, independent of device) ─────
# The ordered include list of the backend layer; a fragment of ProjecturedKernel.
# BackendModule declares the abstract Backend, the batch generics
# (initialize_backend!, quit_backend!, measure_text, write_image, record_video,
# render_canvas, decode_image, get_pointer_position), and the make_backend
# factory seam. DisplayModule holds the display-size query with a provider
# indirection.
include("Backend.jl")
include("Display.jl")
include("HeadlessBackend.jl")
