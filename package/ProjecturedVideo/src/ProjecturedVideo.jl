"""
    ProjecturedVideo

Opt-in package: headless video recording (`record_video`, `VideoBackend`). This is the
only thing that pulls `FFMPEG`, so it lives here rather than in `ProjecturedSdl` —
desktop-editor and screenshot users (`Projectured` + `ProjecturedSdl`) don't carry FFMPEG.

`record_video` reuses `ProjecturedSdl`'s offscreen renderer to rasterise each frame
(`_open_offscreen_renderer` / `_emit_frames!` / `_close_offscreen_renderer`), then shells
out to `ffmpeg` (via `FFMPEG.jl`) to encode the frames into an `.mp4`. The
`record_video` *generic* is the kernel `BackendModule` seam (re-exported by the
`Projectured` umbrella); this package adds the method.

`VideoBackend` is a `Backend` over the same offscreen renderer, for a caller that wants
a scripted timeline played through the real `run_editor!` loop — every tool the loop
offers, not one projection printed by hand — rather than `record_video`'s own loop.

Usage: `using Projectured, ProjecturedSdl, ProjecturedVideo;
record_video(doc, proj; gestures, filename = "out.mp4")`.
"""
module ProjecturedVideo

using ProjecturedKernel
using ProjecturedPlatform
using ProjecturedSdl
import FFMPEG

using ProjecturedKernel.BackendModule: Backend
using ProjecturedPlatform.GraphicsModule: GraphicsCanvas, GraphicsCircle, GraphicsPolygon,
       GraphicsRect, GraphicsText
using ProjecturedPlatform.StyleModule: StyleColor, color_black, color_white,
       color_transparent, color_solarized_orange, color_solarized_red,
       font_dejavu_monospace_bold_16
using ProjecturedKernel.ProjectionModule: print_document, read_intent
using ProjecturedKernel.OperationModule: evaluate_operation
using ProjecturedKernel.SelectionModule: clear_selection!, set_selection!
using ProjecturedKernel.ProjectionModule: PrinterContext
using ProjecturedKernel.CellModule: Cell
using ProjecturedKernel.ClockModule: Clock, set_clock_time!
using ProjecturedKernel.ReferenceModule: EmptyReference
using ProjecturedKernel.EventModule: WindowInput, WindowQuit,
       MouseDown, MouseUp, MouseMove, MouseScroll
using ProjecturedKernel.GestureModule: MouseClick
using ProjecturedPlatform.ScreenModule: ScreenDocument, WindowDocument

import ProjecturedSdl: _open_offscreen_renderer, _close_offscreen_renderer, _emit_frames!,
                       _make_offscreen_paint_state, _render_canvas_offscreen_partial!,
                       _emit_frame_with_overlay!, _save_picture_with_overlay!
# `SdlBackend` itself is already in scope via the bare `using ProjecturedSdl` above.

# Imported to extend: this package adds a method to each of these.
import ProjecturedKernel.BackendModule: record_video, initialize_backend!, quit_backend!,
       write_to_devices, read_from_devices, wait_for_input, get_pointer_position,
       get_display_size
import ProjecturedKernel.EditorModule: get_frame_clock_time

include("../../../source/backend/video/Video.jl")
include("../../../source/backend/video/VideoBackend.jl")

end # module ProjecturedVideo
