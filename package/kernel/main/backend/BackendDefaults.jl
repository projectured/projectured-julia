# Fragment of `BackendModule` — the behaviour the backend contract supplies
# itself, for the generics a backend may leave unanswered. The contract is
# declared in `BackendInterface.jl`; the concrete backends live in opt-in packages.

# The capabilities a backend may decline, each with a legal fallback rather than
# a missing implementation: a pointer position defaults to `(-1, -1)` (no pointer
# or cannot query it), a display size to the display-free `(1280, 800)`, and
# device configuration to a no-op (the devices keep their default physical
# properties). The batch generics have no counterpart here on purpose — an
# unimplemented `measure_text` or `write_image` must raise a `MethodError`, not
# fabricate a result.
get_pointer_position(::Backend) = (-1, -1)
get_display_size(::Backend; display::Integer=0) = (1280, 800)
configure_devices!(::Backend, devices) = nothing
