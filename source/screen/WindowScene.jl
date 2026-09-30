# Fragment of `ScreenModule`.
#
# ── One window on one document ──────────────────────────────────────────────
#
# **The wrapper `window`.** `build_editor` puts the root document in one window
# of a screen when the backend draws windows. The wrapper is on by default, and
# a caller turns it off with `window = false`. `make_editor` applies no wrapper,
# so a caller that wants a screen of its own builds it with `make_window_scene`
# and `make_window_scene_projection`, and passes it.
#
# It lives here because a window on a screen is what this package is about, and
# it costs nothing: `ProjecturedProjection` was already in this package's closure
# through `ProjecturedGraphics`, so naming it directly adds no package to any
# image.
#
# A wrapper can open a window of its own, such as the gesture help that F1
# opens. That wrapper, or the caller, names what draws the content of that
# window in `opened_window_projections`, because this package does not know the
# wrapper.
using ProjecturedProjection.ProjectionAlgebraModule: ReferenceDispatchingProjection
using ProjecturedProjection.ProjectionAlgebraModule: NestingProjection
using ProjecturedProjection.ProjectionAlgebraModule: IdentityProjection
using ProjecturedProjection.ProjectionAlgebraModule: RecursiveProjection
using ProjecturedProjection.ProjectionAlgebraModule: TypeDispatchingProjection


"""
    make_window_scene(document, title; width, height) -> ScreenDocument

The screen a program is drawn on: one window, holding `document`. The screen is
the new root, so it holds the selection that `document` holds, rooted at the
screen, and the window holds its part of that path.
"""
function make_window_scene(document, title::AbstractString; width::Integer, height::Integer)
    window = WindowDocument(; id = Symbol(title), title = String(title),
                            x = 100, y = 100, width = Int(width), height = Int(height),
                            content = document)
    screen = ScreenDocument([window])
    inner = get_selection(document)
    inner === nothing || replace_selection!(screen,
        concat_references(ConcreteReference(FieldReferenceStep("windows"),
                              ConcreteReference(ElementReferenceStep(1),
                                  ConcreteReference(FieldReferenceStep("content"), EmptyReference()))),
                          strip_reference_types(inner)))
    screen
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
The content of the first window is chosen by its place before any entry by type,
so an entry for a type that the first window's content also has, such as a
widget, draws only the windows opened later.
"""
function make_window_scene_projection(projection;
                                      opened_window_projections = Pair{Type,Any}[])
    target = @reference ::ScreenDocument.windows::CellVector[1]::WindowDocument.content::Document
    # A window carries a `WindowDocument` of its own, and it recurses through
    # `ScreenToScreen`. The content of a window opened later is drawn by the entry
    # that names the content's type.
    opened = TypeDispatchingProjection(
        WindowDocument => ScreenToScreen(),
        opened_window_projections...,
        Any            => IdentityProjection())
    # The place decides first: the screen goes to the manager, and the content of
    # the first window to `projection`, whatever its type.
    RecursiveProjection(ReferenceDispatchingProjection(reference -> begin
        is_reference_equal(strip_reference_types(reference),
                                           strip_reference_types(target)) &&
            return NestingProjection(projection; recursion = IdentityProjection())
        reference isa EmptyReference &&
            return WindowManagingProjection(inner = ScreenToScreen())
        opened
    end))
end

"""
    window = true | (; title, width, height, opened_window_projections)

The wrapper of `build_editor` that puts the root document in one window of a
screen, drawn with [`make_window_scene_projection`](@ref). It is on by default.
It does nothing when the root is a `ScreenDocument` already, or when the backend
declares an output that is not `:windows`, such as the text of a console.

- `title` names the window and gives its id. The default is the title of the
  document, else "ProjecturEd".
- `width` and `height` default to the size of the display that the backend
  reports.
- `opened_window_projections` adds rows to those of the other wrappers, for the
  windows that open later.
"""
# @positional: the arity of the wrapper seam of the kernel.
function wrap_editor!(::Val{:window}, layer::Symbol, setting, parts::EditorParts)
    _is_window_backend(parts.backend) || return parts
    parts.document isa ScreenDocument && return parts
    options = setting === true ? (;) : setting
    title = get(options, :title, nothing)
    title === nothing &&
        (title = something(get_document_title(parts.document), "ProjecturEd"))
    width = get(options, :width, nothing)
    height = get(options, :height, nothing)
    if width === nothing || height === nothing
        display_width, display_height = get_display_size(parts.backend)
        width = something(width, display_width)
        height = something(height, display_height)
    end
    append!(parts.opened_window_projections,
            get(options, :opened_window_projections, Pair{Type,Any}[]))
    parts.document = make_window_scene(parts.document, string(title);
                                       width = width, height = height)
    parts.projection = make_window_scene_projection(parts.projection;
        opened_window_projections = parts.opened_window_projections)
    parts
end

get_wrapper_layers(::Val{:window}) = (:window => 0,)
is_wrapper_default(::Val{:window}) = true

# A backend that declares no output, such as a recorder or a test double, draws
# what the editor gives it, and a screen of windows is what an editor gives.
_is_window_backend(backend::Backend) =
    !hasmethod(get_backend_output, Tuple{Type{typeof(backend)}}) ||
    get_backend_output(typeof(backend)) === :windows
