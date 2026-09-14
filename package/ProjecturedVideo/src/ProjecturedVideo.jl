"""
    ProjecturedVideo

Opt-in package: headless video recording (`record_video`). This is the only thing that
pulls `FFMPEG`, so it lives here rather than in `ProjecturedSdl` — desktop-editor and
screenshot users (`Projectured` + `ProjecturedSdl`) don't carry FFMPEG.

`record_video` reuses `ProjecturedSdl`'s offscreen renderer to rasterise each frame
(`_open_offscreen_renderer` / `_emit_frames!` / `_close_offscreen_renderer`), then shells
out to `ffmpeg` (via `FFMPEG.jl`) to encode the frames into an `.mp4`. The
`record_video` *generic* is the kernel `BackendModule` seam (re-exported by the
`Projectured` umbrella); this package adds the method.

Usage: `using Projectured, ProjecturedSdl, ProjecturedVideo; record_video(doc, proj, gestures, "out.mp4")`.
"""
module ProjecturedVideo

using ProjecturedGraphics
using ProjecturedGraphics
using ProjecturedGraphics
using ProjecturedKernel
using ProjecturedSdl
using ProjecturedSdl
using ProjecturedSdl
import FFMPEG

import ProjecturedKernel.BackendModule: record_video
import ProjecturedGraphics.GraphicsModule: GraphicsCanvas
import ProjecturedKernel.ProjectionModule: print_document, read_intent
import ProjecturedKernel.OperationModule: evaluate_operation
import ProjecturedKernel.SelectionModule: clear_selection!, set_selection!
import ProjecturedKernel.PrinterContextModule: PrinterContext
import ProjecturedKernel.CellModule: Cell, ComputedCell
import ProjecturedKernel.ClockModule: Clock, set_clock_time!
import ProjecturedKernel.ReferenceModule: EmptyReference

import ProjecturedSdl: _open_offscreen_renderer, _close_offscreen_renderer, _emit_frames!

include("../../../source/video/Video.jl")

end # module ProjecturedVideo
