# Fragment of `ScreenModule`.
#
# ── One window on one document, and the loop that drives it ─────────────────
#
# `ProjecturedExample.run_example` opens the development gallery: one window per
# example, with options for introspection, the tooltip, the inspector, the
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
# A wrapper can open a window of its own, such as the gesture help that F1
# opens. The caller names what draws the content of that window, because this
# package does not know the wrapper.
using ProjecturedProjection.ProjectionAlgebraModule: ReferenceDispatchingProjection
using ProjecturedProjection.ProjectionAlgebraModule: NestingProjection
using ProjecturedProjection.ProjectionAlgebraModule: IdentityProjection
using ProjecturedProjection.ProjectionAlgebraModule: RecursiveProjection
using ProjecturedProjection.ProjectionAlgebraModule: TypeDispatchingProjection


"""
    make_window_scene(document, title; width, height) -> ScreenDocument

The screen a program is drawn on: one window, holding `document`.
"""
function make_window_scene(document, title::AbstractString; width::Integer, height::Integer)
    window = WindowDocument(; id = Symbol(title), title = String(title),
                            x = 100, y = 100, width = Int(width), height = Int(height),
                            content = document)
    ScreenDocument([window])
end

"""
    make_window_scene_projection(projection;
                                 opened_window_projections = Pair{Type,Any}[]) -> Projection

How that screen is drawn. The window's content goes through `projection`; the
screen around it goes through `ScreenToScreen`, wrapped in the manager that owns
opening, closing and resizing a window.

The seam is a reference dispatch and not a type dispatch, because the content of
a window is an ordinary document and the screen must not project it as one.

`opened_window_projections` draws the content of a window that a wrapper opens
later. Each entry is `ContentType => projection`, for example
`GestureMap => make_gesture_map_projection(measure)` for the window that F1 opens.

`screen_wrap` wraps the screen printer, inside the manager. It is how a caller
puts a reader on the window route without this package naming that reader: a
popup is placed in screen coordinates, so the projection that resolves one has
to map through the screen printer, and only a caller that knows the widget layer
can name it. The default changes nothing.
"""
function make_window_scene_projection(projection;
                                      opened_window_projections = Pair{Type,Any}[],
                                      screen_wrap = identity)
    target = @reference ::ScreenDocument.windows::CellVector[1]::WindowDocument.content::Document
    dispatch = ReferenceDispatchingProjection(reference -> begin
        is_reference_equal(strip_reference_types(reference),
                                           strip_reference_types(target)) &&
            return NestingProjection(projection; recursion = IdentityProjection())
        reference isa EmptyReference &&
            return WindowManagingProjection(inner = screen_wrap(ScreenToScreen()))
        IdentityProjection()
    end)
    # A window opened later carries a `WindowDocument` of its own, and it
    # recurses through `ScreenToScreen` rather than through the reference above,
    # which names the first window alone. Its content is drawn by the entry that
    # names the content's type.
    RecursiveProjection(TypeDispatchingProjection(
        WindowDocument => ScreenToScreen(),
        opened_window_projections...,
        Any            => dispatch))
end

"""
    run_window_editor(document, projection, title; backend, width, height, on_start,
                      mcp, mcp_instructions, opened_window_projections, screen_wrap)

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

`mcp` starts an MCP server beside the loop, so an external client drives the
same editor with the same tools; `mcp_instructions` is the prompt that server
gives the client, and the server's own generic one answers when it is `nothing`.
The server needs `ProjecturedMcp` loaded, which registers it.

`opened_window_projections` goes to [`make_window_scene_projection`](@ref).
"""
function run_window_editor(document, projection, title::AbstractString;
                           backend, width = nothing, height = nothing,
                           on_start = nothing, mcp::Bool = false,
                           mcp_instructions::Union{AbstractString,Nothing} = nothing,
                           opened_window_projections = Pair{Type,Any}[],
                           feeds::Vector{Feed} = Feed[],
                           screen_wrap = identity)
    backend === nothing &&
        error("run_window_editor: name the backend to draw on, " *
              "for example `backend = SdlBackend()`")
    if width === nothing || height === nothing
        display_width, display_height = get_display_size(backend)
        width = something(width, display_width)
        height = something(height, display_height)
    end
    scene = make_window_scene(document, title; width = width, height = height)
    run_editor!(backend,
                make_window_scene_projection(projection;
                    opened_window_projections = opened_window_projections,
                    screen_wrap = screen_wrap),
                scene;
                             mcp = mcp, mcp_instructions = mcp_instructions,
                             feeds = feeds, on_start = on_start)
end
