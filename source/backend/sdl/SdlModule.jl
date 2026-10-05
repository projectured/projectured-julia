"""
    SdlModule

The SDL backend: a native window for each window document of a screen, drawn
with the renderer of SDL and with SDL_ttf, the input of the keyboard and the
mouse, and an offscreen renderer that writes an image or the frames of a video.
It extends the generic functions of `BackendModule`, so a caller reaches it
through them.
"""
module SdlModule

using ..KernelModule
using ..PlatformModule
using SimpleDirectMediaLayer
using SimpleDirectMediaLayer.LibSDL2
# The locale data of Xlib, which SDL needs to give a window its title.
using Xorg_libX11_jll: Xorg_libX11_jll

# Imported to extend: this module adds a method to each of these. The backend
# contract is extended by qualification instead, `BackendModule.render_canvas`.
import ..EditorModule: get_backend_name, get_backend_output
import ..ProjectionModule: print_document, map_reference_forward, map_reference_backward
import ..SettingsModule: apply_settings!, read_settings!

# A backend's public surface is the generic it extends, not the helper behind
# it: `BackendModule.render_canvas`, `decode_image` and `get_display_size` are
# how a caller reaches this backend. The offscreen renderer is public as well,
# because `ProjecturedVideo` records its frames with it.
export SdlBackend, open_offscreen_renderer, close_offscreen_renderer, with_offscreen_zoom,
       GraphicsCanvasToImageFile, write_offscreen_frames!, make_offscreen_paint_state,
       render_offscreen_changes!, write_offscreen_frame_with_overlay!,
       write_offscreen_picture_with_overlay!

include("SdlBackend.jl")
include("SystemColorQuery.jl")

end # module SdlModule
