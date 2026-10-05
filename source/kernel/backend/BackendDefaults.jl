# Fragment of `BackendModule` — the fallback behaviours the backend contract
# supplies itself, for the generics a backend may leave unanswered. The contract
# is declared in `BackendInterface.jl`; the concrete backends live in opt-in packages.

# The capabilities a backend may decline, each with a legal fallback rather than
# a missing implementation: a pointer position defaults to `(-1, -1)` (no pointer
# or cannot query it), a display size to the display-free `(1280, 800)`, the colour
# settings of the system to `nothing` (the backend can not find them), device
# configuration to a no-op (the devices keep their default physical properties),
# and native windows to a no-op (a backend that has none has nothing to open and
# no geometry to answer with). The batch generics have no counterpart here on
# purpose — an unimplemented `write_image` must raise a `MethodError`, not
# fabricate a result.
# The wait defaults to one 10 ms poll slice, with the wake a matching no-op:
# a sliced sleep notices pending work on its next slice at the latest, which
# is the cadence the editor loop has without a real wait.
get_pointer_position(::Backend) = (-1, -1)
get_display_size(::Backend) = (1280, 800)
find_system_colors(::Backend) = nothing
configure_devices!(::Backend, devices) = nothing
open_native_windows!(::Backend, document) = nothing
wait_for_input(::Backend, devices, timeout_seconds) = sleep(min(timeout_seconds, 0.01))
wake_backend!(::Backend) = nothing
