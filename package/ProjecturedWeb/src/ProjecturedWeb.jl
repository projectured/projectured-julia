"""
    Web

Opt-in package: the HTTP/WebSocket web backend (browser-rendered editor). Depends
on `ProjecturedDomain` + HTTP/JSON3; `using ProjecturedWeb` exports `WebBackend`
(construct it directly). SDL-free — reuses the pure-Julia TrueType text metrics.
Relocated from the former program/src/backend/Web.jl (WebBackendModule).
"""
module ProjecturedWeb

using ProjecturedCollection
using ProjecturedGraphics
using ProjecturedCollection
using ProjecturedGraphics
using ProjecturedKernel
using ProjecturedScreen
using ProjecturedStyle
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
import ProjecturedCollection.CollectionModule: ListNode, CellVector, ComputedCellVector
import ProjecturedStyle.ColorModule: StyleColor
import ProjecturedStyle.GeometryModule: AffineTransform, affine_identity
import ProjecturedStyle.FontModule: StyleFont, font_logical_size
import ProjecturedKernel.CellModule: Cell, ComputedCell, is_cell_up_to_date
import ProjecturedKernel.EventModule: WindowInput, ModifierKeys,
                               WindowQuit, WindowClose, WindowResize, WindowDefocus
import ProjecturedScreen.ScreenDocumentModule: ScreenDocument, WindowDocument
import ProjecturedKernel.EventModule: KeyDown, KeyUp, KeyPress
import ProjecturedKernel.EventModule: MouseDown, MouseUp, MouseMove, MouseScroll
# SDL-free text measurement: reuse the pure-Julia TrueType metrics measurer from
# the SDL-free TrueType measurer, so the web backend needs no SDL/SDL_ttf at all.
# `truetype_measure_text` is the shared font-metrics utility (TrueTypeModule),
# also used by the PDF backend and every projection example.
import ProjecturedStyle.TrueTypeModule: truetype_measure_text

include("../../../source/web/Web.jl")

end # module Web
