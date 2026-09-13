"""
    Sdl

Opt-in package: the SDL display/input backend (window, GPU rendering, SDL_ttf text
rasterisation, offscreen image output). Depends on `ProjecturedDomain` +
SimpleDirectMediaLayer/SDL2_jll; `using ProjecturedSdl` provides the
render/decode/image seam methods. Exposes `SdlBackend`,
`GraphicsCanvasToImageFile`, and the `sdl_*` helpers. Also exports the offscreen
primitives (`_open_offscreen_renderer`, `_close_offscreen_renderer`, `_emit_frames!`)
that the opt-in `ProjecturedVideo` package builds `record_video` on (FFMPEG lives there,
not here).

Relocated from the former program/src/backend/Sdl.jl (ProjecturedSdl); relative
submodule imports were rewritten to absolute ProjecturedDomain.* references.
"""
module ProjecturedSdl

using ProjecturedCollection
using ProjecturedGraphics
using ProjecturedCollection
using ProjecturedGraphics
using ProjecturedKernel
using ProjecturedScreen
using ProjecturedStyle
using ProjecturedScreen
using ProjecturedStyle


using SimpleDirectMediaLayer
using SimpleDirectMediaLayer.LibSDL2
# The backend + device contracts (PAR-QUALIFIED-EXTENSION): bare `using`,
# extended by qualification below. A bare `using` of an alias binds the
# module's *real* name, so the extension sites read BackendModule.*;
# DeviceModule supplies the `Device` type used in the render signatures.
using ProjecturedKernel.BackendModule
using ProjecturedKernel.DeviceModule
import ProjecturedGraphics.GraphicsModule: GraphicsCanvas, GraphicsText, GraphicsRect, GraphicsLine, GraphicsCircle,
                         GraphicsPolyline, GraphicsPolygon, GraphicsSpline, GraphicsViewport, GraphicsImage,
                         GraphicsFence, LayoutDirection, layout_none, layout_horizontal, layout_vertical,
                         get_canvas_content_bounds, _accumulate_bounds!, _bounds_elem!,
                         tessellate_spline, build_polyline_arrowhead
import ProjecturedCollection.CollectionModule: ListNode, CellVector, ComputedCellVector
import ProjecturedStyle.StyleModule: AffineTransform, affine_identity, is_affine_axis_aligned
import ProjecturedStyle.StyleModule: StyleColor
import ProjecturedStyle.StyleModule: StyleFont, font_scaled_size, font_logical_size, font_device_size,
                         _DISPLAY_SCALE, _BASE_DISPLAY_SCALE, recompute_display_scale!,
                         adjust_user_zoom!, adjust_font_zoom!, _FONT_DIR
# `_get_font` resolves a font's name through this rather than opening
# `font.filename` directly, so a bundle copied to another machine finds its
# fonts where they are now. The metrics reader resolves the same way, which is
# what keeps SDL and it opening one file.
import ProjecturedStyle.StyleModule: font_file
import ProjecturedKernel.EventModule: WindowQuit
import ProjecturedScreen.ScreenModule: ScreenDocument, WindowDocument
import ProjecturedKernel.EventModule: WindowInput, WindowClose, WindowResize, WindowDefocus
import ProjecturedKernel.EventModule: ModifierKeys
import ProjecturedKernel.EventModule: KeyDown, KeyUp, KeyPress
import ProjecturedKernel.EventModule: MouseDown, MouseUp, MousePress, MouseMove, MouseScroll
import ProjecturedStyle.StyleModule: ImageFile
import ProjecturedKernel.ProjectionApiModule: print_document, read_intent, Projection
import ProjecturedKernel.OperationModule: Operation, evaluate_operation
import ProjecturedKernel.OperationModule: AdjustZoomOperation, AdjustFontZoomOperation
import ProjecturedKernel.SelectionModule: clear_selection!, set_selection!
import ProjecturedKernel.PrinterContextModule: PrinterContext
import ProjecturedKernel.CellModule: Cell, ComputedCell, is_cell_up_to_date
import ProjecturedKernel.ReferenceModule: EmptyReference
import ProjecturedKernel.IoMapModule: SimpleIoMap

include("../../../source/sdl/Sdl.jl")

end # module Sdl
