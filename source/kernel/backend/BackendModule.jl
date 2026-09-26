"""
    BackendModule

The backend contract. A `Backend` encapsulates everything needed to initialise,
shut down, read input from, and write output to a particular display/input
system.
Concrete subtypes and the methods of the generic functions declared here
live in **opt-in backend packages** that depend on this kernel; this module
carries only the abstract type and the forward-declared generics, so generic
code can name a capability (measure text, write an image, …) without
referencing any concrete backend at load time. A generic that isn't
implemented because its backend package isn't loaded raises a `MethodError`.

The contract is declared here and answered elsewhere. The module lives in two
fragments that share this namespace:

- [`BackendInterface.jl`](BackendInterface.jl) — the contract: the abstract
  `Backend` type and the open generics a backend package answers.
- [`BackendDefaults.jl`](BackendDefaults.jl) — the fallback behaviours the
  contract supplies itself, for the capabilities a backend may decline (pointer
  position, display size, device configuration, native windows, the input
  wait).
"""
module BackendModule

export Backend, initialize_backend!, quit_backend!,
       write_to_devices, read_from_devices, get_display_size, configure_devices!,
       open_native_windows!, wait_for_input, wake_backend!,
       write_image, record_video, render_canvas, decode_image, get_pointer_position

include("BackendInterface.jl")  # the backend contract (declaration-only)
include("BackendDefaults.jl")   # the fallback behaviours the contract supplies itself

end # module
