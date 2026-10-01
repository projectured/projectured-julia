"""
    Sdl

Opt-in package: the SDL display/input backend (window, GPU rendering, SDL_ttf text
rasterisation, offscreen image output). Depends on `ProjecturedKernel`,
`ProjecturedPlatform` and SimpleDirectMediaLayer/SDL2_jll; `using ProjecturedSdl`
provides the render/decode/image seam methods. Exposes `SdlBackend`,
`GraphicsCanvasToImageFile`, and the `sdl_*` helpers. Also exports the offscreen
primitives `open_offscreen_renderer` and `close_offscreen_renderer` that the
opt-in `ProjecturedVideo` package builds `record_video` on (FFMPEG lives
there, not here); `ProjecturedVideo` imports the unexported `write_offscreen_frames!` and
the other offscreen helpers by name.
"""
module ProjecturedSdl

using ProjecturedKernel
using ProjecturedPlatform

using SimpleDirectMediaLayer
using SimpleDirectMediaLayer.LibSDL2
# The locale data of Xlib, which SDL needs to give a window its title.
using Xorg_libX11_jll: Xorg_libX11_jll
# The backend + device contracts (PAR-QUALIFIED-EXTENSION): bare `using`,
# extended by qualification below. A bare `using` of an alias binds the
# module's *real* name, so the extension sites read BackendModule.*;
# DeviceModule supplies the `Device` type used in the render signatures.
using ProjecturedKernel.BackendModule
using ProjecturedKernel.DeviceModule
import ProjecturedKernel.EditorModule: get_backend_name, get_backend_output
using ProjecturedPlatform.GraphicsModule: GraphicsCanvas, GraphicsText, GraphicsRect,
                         GraphicsLine, GraphicsCircle, GraphicsPolyline, GraphicsPolygon,
                         GraphicsSpline, GraphicsViewport, GraphicsImage, GraphicsFence,
                         LayoutDirection, layout_none, layout_horizontal, layout_vertical,
                         ContentBounds, get_content_box, extend_content_bounds!,
                         extend_element_bounds!,
                         compute_first_visible_index, has_declared_extent,
                         tessellate_spline, build_polyline_arrowhead
using ProjecturedPlatform.CollectionModule: ListNode, CellVector
using ProjecturedPlatform.StyleModule: AffineTransform, affine_identity,
                         is_affine_axis_aligned
using ProjecturedPlatform.StyleModule: StyleColor
using ProjecturedPlatform.StyleModule: StyleFont, font_logical_size, font_device_size,
                         step_zoom, adjust_font_zoom!
# `_get_font` resolves a font's name through this rather than opening
# `font.filename` directly, so a bundle copied to another machine finds its
# fonts where they are now. The metrics reader resolves the same way, which is
# what keeps SDL and it opening one file.
using ProjecturedPlatform.StyleModule: font_file
# A character the font lacks draws in the font the style package names, and each
# glyph draws where the layout measures it (`compute_placed_glyphs`).
using ProjecturedPlatform.StyleModule: compute_text_extent, compute_placed_glyphs,
                         PlacedGlyph, FontFileMeasure
using ProjecturedKernel.EventModule: WindowQuit
using ProjecturedPlatform.ScreenModule: ScreenDocument, WindowDocument
using ProjecturedKernel.EventModule: WindowInput, WindowClose, WindowResize, WindowDefocus,
                         WindowLeave, DisplayUpdate
using ProjecturedKernel.EventModule: ModifierKeys
using ProjecturedKernel.EventModule: KeyDown, KeyUp, KeyPress
using ProjecturedKernel.EventModule: MouseButtons, MouseDown, MouseUp, MouseMove,
                         MouseScroll
using ProjecturedPlatform.StyleModule: ImageFile
using ProjecturedKernel.ProjectionModule: Projection, PrinterContext
using ProjecturedKernel.OperationModule: AdjustZoomOperation, AdjustFontZoomOperation
using ProjecturedKernel.CellModule: AbstractCell, Cell, ImmutableCell, is_cell_up_to_date
using ProjecturedKernel.DocumentModule: is_view_state_field
using ProjecturedKernel.ReferenceModule: EmptyReference
using ProjecturedKernel.IoMapModule: SimpleIoMap

# Imported to extend: this package adds a method to each of these.
import ProjecturedKernel.ProjectionModule: print_document
import ProjecturedKernel.OperationModule: evaluate_operation

include("../../../source/backend/sdl/Sdl.jl")

end # module Sdl
