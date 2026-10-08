# Fragment of `ScreenModule`.
#
# ── One window on one document ──────────────────────────────────────────────
#
# **The wrapper `window`.** `build_editor` puts the root document in one window
# of a screen when the backend draws windows, and puts the gesture tracker around
# that screen. The wrapper is on by default, and a caller turns it off with
# `window = false`. `make_editor` applies no wrapper, so a caller that wants a
# screen of its own builds it with `make_window_scene` and
# `make_window_scene_projection`, puts the gesture tracker around it with
# `make_tracking_screen`, and passes it.
#
# It lives here because a window on a screen is what this package is about, and
# it costs nothing: the projection slice was already in this package's closure
# through the graphics slice, so naming it directly adds no package to any
# image.
#
# A wrapper can open a window of its own, such as the gesture help that F1
# opens. That wrapper, or the caller, names what draws the content of that
# window in `opened_window_projections`, because this package does not know the
# wrapper.
using ProjecturedPlatform.ProjectionAlgebraModule: ReferenceDispatchingProjection
using ProjecturedPlatform.ProjectionAlgebraModule: NestingProjection
using ProjecturedPlatform.ProjectionAlgebraModule: IdentityProjection
using ProjecturedPlatform.ProjectionAlgebraModule: RecursiveProjection
using ProjecturedPlatform.ProjectionAlgebraModule: TypeDispatchingProjection


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
    make_tracking_screen(document, projection; inner_wrappers = [],
                         gesture_tracking = true,
                         recognitions = make_standard_recognitions())
        -> (document, projection)

Put the gesture tracker around a screen: `document` is the screen, and
`projection` draws it, for example the one of
[`make_window_scene_projection`](@ref). The tracker goes around the pair, and
its state document around the screen, so one tracker serves every window. The
screen gives each move to the window that the pointer leaves and to the window
at the point, and each document on the way keeps its `mouse_target`, the part
under the pointer. The keywords:

- `inner_wrappers` — `(document, projection) -> (document, projection)`
  functions that go around the screen and inside the gesture tracker, the first
  innermost. A wrapper there sees each gesture before the screen reads it, and
  each answer after it comes back, in every window: the wrappers that keep the
  tooltip window and the context menu window go there.
- `drag_tracking` — the drag tracking projection, just inside the gesture
  tracker: it keeps the part whose drag is on, and gives that part each move,
  the release and the end with no change of its drag, wherever the pointer is.
- `gesture_tracking` — the gesture tracking projection, which runs
  `recognitions`: by default the click with its count, the key chord and the
  mouse dwell. A host adds the recognition of a gesture of its own to the list.
  An editor with no gesture tracker gets the events of its devices and no
  gesture.

Use it wherever a host makes an editor over a screen. The wrapper `window` of
`build_editor` uses it. The document of the editor is then the outermost state
document; `get_wrapped_document` of it answers the screen.
"""
function make_tracking_screen(document, projection; inner_wrappers::Vector = [],
                              drag_tracking::Bool = true,
                              gesture_tracking::Bool = true,
                              recognitions::Vector = make_standard_recognitions())
    for wrap in inner_wrappers
        document, projection = wrap(document, projection)
    end
    if drag_tracking
        document = make_drag_tracking_document(document)
        projection = make_drag_tracking_projection(projection)
    end
    if gesture_tracking
        document = make_gesture_tracking_document(document)
        projection = make_gesture_tracking_projection(projection; recognitions)
    end
    (document, projection)
end

"""
    window = true | (; title, width, height, opened_window_projections, inner_wrappers)

The wrapper of `build_editor` that puts the root document in one window of a
screen, drawn with [`make_window_scene_projection`](@ref), and puts the gesture
tracker of [`make_tracking_screen`](@ref) around that screen. It is on by
default. It does nothing when the root is a screen already, with or without a
tracker around it, or when the backend declares an output that is not
`:windows`, such as the text of a console.

The gesture tracker makes the editor recognize clicks, chords and dwells; the
screen gives each move to its windows, so the part under the pointer lights.
The document of the editor is the state of the gesture tracker around the
documents of the inner wrappers around the screen.

- `title` names the window and gives its id. The default is the title of the
  document, else "ProjecturEd".
- `width` and `height` default to the size of the display that the backend
  reports.
- `opened_window_projections` puts rows in front of those of the other
  wrappers, for the windows that open later. A row matches by the first type
  that the document is, so the rows of the host decide first.
- `inner_wrappers` goes to `make_tracking_screen`, after the `window_wrappers`
  that the other wrappers of the editor give in the editor parts, such as the
  `tooltip` and `context_menu` wrappers, which keep the tooltip window and the
  context menu window.

The gesture tracker reads the limits of its recognitions from the
`PointerSettings` of the `settings` wrapper of the same editor, when that wrapper
is on.
"""
function wrap_editor!(::Val{:window}, layer::Symbol, argument, parts::EditorParts)
    _is_window_backend(parts.backend) || return parts
    get_wrapped_document(parts.document) isa ScreenDocument && return parts
    options = argument === true ? (;) : argument
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
    prepend!(parts.opened_window_projections,
             get(options, :opened_window_projections, Pair{Type,Any}[]))
    parts.document, parts.projection = make_tracking_screen(
        make_window_scene(parts.document, string(title); width = width, height = height),
        make_window_scene_projection(parts.projection;
            opened_window_projections = parts.opened_window_projections);
        inner_wrappers = vcat(parts.window_wrappers, get(options, :inner_wrappers, [])),
        recognitions = _make_window_recognitions(parts))
    parts
end

# The recognitions of the gesture tracker: those whose limits are the cells of the
# pointer settings of the `settings` wrapper, else the defaults.
function _make_window_recognitions(parts::EditorParts)
    settings = get(parts.arguments, :settings, nothing)
    settings isa Settings || return make_standard_recognitions()
    make_standard_recognitions(get_settings_group!(settings, PointerSettings))
end

get_wrapper_layers(::Val{:window}) = (:window => 0,)
is_wrapper_default(::Val{:window}) = true

# A backend that declares no output, such as a recorder or a test double, draws
# what the editor gives it, and a screen of windows is what an editor gives.
# Parts that `make_editor_parts` makes with no backend have no window.
_is_window_backend(::Nothing) = false
# The call goes through `invokelatest`: each backend package adds a method of
# `get_backend_output`, which would invalidate a resolved call.
_is_window_backend(backend::Backend) =
    !hasmethod(get_backend_output, Tuple{Type{typeof(backend)}}) ||
    Base.invokelatest(get_backend_output, typeof(backend)) === :windows
