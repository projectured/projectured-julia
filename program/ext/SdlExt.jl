"""
    SdlExt

Package extension that loads the SDL2 backend when `SimpleDirectMediaLayer`
is available. Auto-loaded by Julia when the user does:

    using Projectured, SimpleDirectMediaLayer

If `SimpleDirectMediaLayer` (or its native `SDL2_image.dll`) is unavailable,
`Projectured` still loads normally — only the graphics editing functionality
is missing.

## How the import trick works

`backend/Sdl.jl` defines `module SdlBackendModule` with relative imports
such as `import ..BackendModule: Backend`. When included here, the `..` steps
up to `SdlExt`. By importing all required Projectured sub-modules into `SdlExt`
first, `..BackendModule` from inside `SdlBackendModule` resolves correctly to
`Projectured.BackendModule`. No changes to `Sdl.jl` are needed.
"""
module SdlExt

using Projectured
using SimpleDirectMediaLayer

import Projectured.BackendModule
import Projectured.DeviceModule
import Projectured.GraphicsModule
import Projectured.CollectionModule
import Projectured.FontModule
import Projectured.ScreenModule
import Projectured.ScreenDocumentModule
import Projectured.ModifiersModule
import Projectured.KeyboardModule
import Projectured.MouseModule
import Projectured.ImageModule
import Projectured.ProjectionApiModule
import Projectured.ProjectionContextModule
import Projectured.ReactiveModule
import Projectured.ReferenceModule
import Projectured.IoMapModule

include("../src/backend/Sdl.jl")

# Forward the real SDL implementations onto the stubs defined in Projectured,
# so that `Projectured.sdl_measure_text` etc. become callable once this
# extension is loaded.
import .SdlBackendModule: sdl_measure_text   as _sdl_measure_text
import .SdlBackendModule: sdl_render_canvas  as _sdl_render_canvas
import .SdlBackendModule: sdl_display_size   as _sdl_display_size
import .SdlBackendModule: sdl_decode_image   as _sdl_decode_image
import .SdlBackendModule: decode_image_file! as _decode_image_file!
import .SdlBackendModule: write_image        as _write_image

Projectured.sdl_measure_text(args...; kw...)  = _sdl_measure_text(args...; kw...)
Projectured.sdl_render_canvas(args...; kw...) = _sdl_render_canvas(args...; kw...)
Projectured.sdl_display_size(args...; kw...)  = _sdl_display_size(args...; kw...)
Projectured.sdl_decode_image(args...; kw...)  = _sdl_decode_image(args...; kw...)
Projectured.decode_image_file!(args...; kw...)= _decode_image_file!(args...; kw...)
Projectured.write_image(args...; kw...)       = _write_image(args...; kw...)

end # module
