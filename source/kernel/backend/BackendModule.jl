"""
    BackendModule

The backend contract. A `Backend` holds everything that is necessary to
initialize, stop, read input from and write output to one display and input
system.

The concrete subtypes and the methods of the generic functions declared here
live in packages above the kernel. The SDL, web and video backends are opt-in
packages, the console backend is a package of its own, not opt-in, and the headless
test double is in `ProjecturedKernelExample`. This module carries only the
abstract type and the forward-declared generics, so generic code can name a
capability, such as the output of an image, and refer to no concrete backend
when it loads. A generic whose backend package is not loaded raises a
`MethodError`.

The contract is declared here and answered elsewhere. The module lives in two
fragments that share this namespace:

- [`BackendInterface.jl`](BackendInterface.jl) — the contract: the abstract
  `Backend` type and the open generics a backend package answers.
- [`BackendDefaults.jl`](BackendDefaults.jl) — the fallback behaviours the
  contract supplies itself, for the capabilities a backend can lack (pointer
  position, display size, the colour settings of the system, device
  configuration, native windows, the input wait and the wake).
"""
module BackendModule

export Backend, initialize_backend!, quit_backend!,
       write_to_devices!, take_from_devices!, get_display_size, find_system_colors,
       configure_devices!,
       open_native_windows!, wait_for_input, wake_backend!,
       write_image, record_video, render_canvas, decode_image, get_pointer_position

include("BackendInterface.jl")
include("BackendDefaults.jl")

end # module
