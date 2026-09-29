"""
    Web

Opt-in package: the HTTP/WebSocket web backend (browser-rendered editor). Depends
on `ProjecturedCollection`, `ProjecturedGraphics`, `ProjecturedKernel`,
`ProjecturedScreen`, `ProjecturedStyle` + HTTP/JSON3; `using ProjecturedWeb`
exports `WebBackend` (construct it directly). SDL-free — reuses the pure-Julia
TrueType text metrics.
"""
module ProjecturedWeb

using ProjecturedCollection
using ProjecturedGraphics
using ProjecturedKernel
using ProjecturedScreen
using ProjecturedStyle

using HTTP
using JSON3
using Base64: base64encode

# The backend contract (PAR-QUALIFIED-EXTENSION): bare `using`, extended by
# qualification below. A bare `using` of an alias binds the module's *real*
# name, so the extension sites read BackendModule.*.
using ProjecturedKernel.BackendModule
import ProjecturedGraphics.GraphicsModule: GraphicsCanvas, GraphicsText, GraphicsRect, GraphicsLine,
                         GraphicsCircle, GraphicsPolyline, GraphicsPolygon, GraphicsSpline,
                         GraphicsViewport, GraphicsImage, GraphicsFence,
                         _bounds_elem!, _accumulate_bounds!, tessellate_spline
import ProjecturedCollection.CollectionModule: ListNode, CellVector
import ProjecturedStyle.StyleModule: StyleColor
import ProjecturedStyle.StyleModule: AffineTransform, affine_identity
import ProjecturedStyle.StyleModule: StyleFont, font_logical_size, compute_text_extent,
                                    compute_caret_offsets, FontFileMeasure, get_fallback_font_files
import ProjecturedKernel.CellModule: Cell, Computation, is_cell_up_to_date
import ProjecturedKernel.DocumentModule: is_view_state_field
import ProjecturedKernel.EventModule: WindowInput, ModifierKeys,
                               WindowQuit, WindowClose, WindowResize, WindowDefocus,
                               WindowLeave
import ProjecturedScreen.ScreenModule: ScreenDocument, WindowDocument
import ProjecturedKernel.EventModule: KeyDown, KeyUp, KeyPress
import ProjecturedKernel.EventModule: MouseButtons, MouseDown, MouseUp, MouseMove, MouseScroll

include("../../../source/web/Web.jl")

end # module Web
