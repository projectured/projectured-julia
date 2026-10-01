"""
    Web

Opt-in package: the HTTP/WebSocket web backend (browser-rendered editor). Depends
on `ProjecturedKernel`, `ProjecturedPlatform` + HTTP/JSON3; `using ProjecturedWeb`
exports `WebBackend` (construct it directly). SDL-free — reuses the pure-Julia
TrueType text metrics.
"""
module ProjecturedWeb

using ProjecturedKernel
using ProjecturedPlatform

using HTTP
using JSON3
using Base64: base64encode

# The backend contract (PAR-QUALIFIED-EXTENSION): bare `using`, extended by
# qualification below. A bare `using` of an alias binds the module's *real*
# name, so the extension sites read BackendModule.*.
using ProjecturedKernel.BackendModule
import ProjecturedKernel.EditorModule: get_backend_name, get_backend_output
import ProjecturedPlatform.GraphicsModule: GraphicsCanvas, GraphicsText, GraphicsRect, GraphicsLine,
                         GraphicsCircle, GraphicsPolyline, GraphicsPolygon, GraphicsSpline,
                         GraphicsViewport, GraphicsImage, GraphicsFence,
                         ContentBounds, get_content_box, extend_content_bounds!,
                         extend_canvas_bounds!, extend_element_bounds!, tessellate_spline
import ProjecturedPlatform.CollectionModule: ListNode, CellVector
import ProjecturedPlatform.StyleModule: StyleColor
import ProjecturedPlatform.StyleModule: AffineTransform, affine_identity
import ProjecturedPlatform.StyleModule: StyleFont, font_logical_size, compute_text_extent,
                                    compute_caret_offsets, FontFileMeasure, get_fallback_font_files
import ProjecturedKernel.CellModule: Cell, Computation, is_cell_up_to_date
import ProjecturedKernel.DocumentModule: is_view_state_field
import ProjecturedKernel.EventModule: WindowInput, ModifierKeys,
                               WindowQuit, WindowClose, WindowResize, WindowDefocus,
                               WindowLeave
import ProjecturedPlatform.ScreenModule: ScreenDocument, WindowDocument
import ProjecturedKernel.EventModule: KeyDown, KeyUp, KeyPress
import ProjecturedKernel.EventModule: MouseButtons, MouseDown, MouseUp, MouseMove, MouseScroll

include("../../../source/backend/web/Web.jl")

end # module Web
