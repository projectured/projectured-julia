# ── One window on one document, and the loop that drives it ─────────────────
#
# `ProjecturedExample.run_example` opens the development gallery: one window per
# example, with options for the workbench, the tooltip, the inspector, the
# clipboard, the gesture log and the profiler. Behind it stand the twenty-one
# domain example packages its umbrella registers, because a registry of every
# domain must depend on every domain.
#
# **A product opens one window.** This file builds that window and calls
# `run_editor!`, the kernel's own loop — the same loop the gallery ends in. What
# is left out is every option a person developing a projection wants and a person
# using the program does not.
#
# It lives here because a window on a screen is what this package is about, and
# it costs nothing: `ProjecturedProjection` was already in this package's closure
# through `ProjecturedGraphics`, so naming it directly adds no package to any
# image. Nothing optional is named — a wrapper such as dragging or the clipboard
# is applied by the caller, so a program holds the wrappers it asked for and no
# others.
#
# It was written twice before it was written here, as `CampaignScene.jl` and
# `QtenvWindowScene.jl` in omnet-julia, which differed only in their names.

module WindowSceneModule

import ..ScreenDocumentModule: ScreenDocument, WindowDocument
import ..ScreenToScreenModule: ScreenToScreen
import ..WindowManagingProjectionModule: WindowManagingProjection
import ..CollectionModule: CellVector
import ..DocumentModule: Document
import ..ReferenceModule: var"@reference", is_reference_equal, strip_reference_types,
                          EmptyReference
import ..BackendModule: get_display_size
import ..EditorModule: run_editor!

using ProjecturedProjection.ReferenceDispatchingProjectionModule: ReferenceDispatchingProjection
using ProjecturedProjection.NestingProjectionModule: NestingProjection
using ProjecturedProjection.IdentityProjectionModule: IdentityProjection
using ProjecturedProjection.RecursiveProjectionModule: RecursiveProjection
using ProjecturedProjection.TypeDispatchingProjectionModule: TypeDispatchingProjection

export window_scene, window_scene_projection, run_window_editor

"""
    window_scene(document, title; width, height) -> ScreenDocument

The screen a program is drawn on: one window, holding `document`.
"""
function window_scene(document, title::AbstractString; width::Integer, height::Integer)
    window = WindowDocument(; id = Symbol(title), title = String(title),
                            x = 100, y = 100, width = Int(width), height = Int(height),
                            content = document)
    ScreenDocument([window])
end

"""
    window_scene_projection(projection) -> Projection

How that screen is drawn. The window's content goes through `projection`; the
screen around it goes through `ScreenToScreen`, wrapped in the manager that owns
opening, closing and resizing a window.

The seam is a reference dispatch and not a type dispatch, because the content of
a window is an ordinary document and the screen must not project it as one.
"""
function window_scene_projection(projection)
    target = @reference ::ScreenDocument.windows::CellVector[1]::WindowDocument.content::Document
    dispatch = ReferenceDispatchingProjection(reference -> begin
        is_reference_equal(strip_reference_types(reference),
                                           strip_reference_types(target)) &&
            return NestingProjection(projection; recursion = IdentityProjection())
        reference isa EmptyReference &&
            return WindowManagingProjection(inner = ScreenToScreen())
        IdentityProjection()
    end)
    # A window opened later carries a `WindowDocument` of its own, and it
    # recurses through `ScreenToScreen` rather than through the reference above,
    # which names the first window alone.
    RecursiveProjection(TypeDispatchingProjection(
        WindowDocument => ScreenToScreen(),
        Any            => dispatch))
end

"""
    run_window_editor(document, projection, title; backend, width, height, on_start, mcp)

Open the window and run the loop until the person closes it.

`width` and `height` default to the display the backend reports, which is what a
window opened with no size wants.

`backend` is a CONSTRUCTED backend, so this package depends on none of them: the
caller loads the one it draws on. There is no reflection over the loaded backends
here — that is `ProjecturedExample`'s, and naming it would bring the example
umbrella back.

`on_start` runs once the editor exists. A document that drives itself needs it:
the thing that hands its progress to the editor cannot be built before there is
an editor to hand it to.
"""
function run_window_editor(document, projection, title::AbstractString;
                           backend, width = nothing, height = nothing,
                           on_start = nothing, mcp::Bool = false)
    backend === nothing &&
        error("run_window_editor: name the backend to draw on, " *
              "for example `backend = SdlBackend()`")
    if width === nothing || height === nothing
        display_width, display_height = get_display_size(backend)
        width = something(width, display_width)
        height = something(height, display_height)
    end
    scene = window_scene(document, title; width = width, height = height)
    run_editor!(backend, window_scene_projection(projection), scene;
                             mcp = mcp, on_start = on_start)
end

end # module WindowSceneModule
