# Fragment of `BackendModule` — the behaviour the backend contract supplies
# itself, for the generics a backend may leave unanswered. The contract is
# declared in `BackendInterface.jl`; the concrete backends live in opt-in packages.

# A pointer position is the one capability a backend may decline: a display
# system without a pointer (or one that cannot query it) answers `(-1, -1)`,
# which is a legal answer rather than a missing implementation. The batch
# generics have no counterpart here on purpose — an unimplemented `measure_text`
# or `write_image` must raise a `MethodError`, not fabricate a result.
get_pointer_position(::Backend) = (-1, -1)
