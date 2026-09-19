# Fragment of `BackendModule` — the fallback behaviours the backend contract
# supplies itself, for the generics a backend may leave unanswered. The contract
# is declared in `BackendInterface.jl`; the concrete backends live in opt-in packages.

# The capabilities a backend may decline, each with a legal fallback rather than
# a missing implementation: a pointer position defaults to `(-1, -1)` (no pointer
# or cannot query it), a display size to the display-free `(1280, 800)`, device
# configuration to a no-op (the devices keep their default physical properties),
# and native windows to a no-op (a backend that has none has nothing to open and
# no geometry to answer with). The batch generics have no counterpart here on
# purpose — an unimplemented `measure_text` or `write_image` must raise a
# `MethodError`, not fabricate a result.
get_pointer_position(::Backend) = (-1, -1)
get_display_size(::Backend; display::Integer=0) = (1280, 800)
# A backend that cannot say where a window is says so, and does not guess.
get_screen_origin(::Backend, id) = nothing
configure_devices!(::Backend, devices) = nothing
open_native_windows!(::Backend, document) = nothing
