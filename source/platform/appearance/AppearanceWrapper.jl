# Fragment of `AppearanceModule` — the `appearance` wrapper of `build_editor`.

"""
    appearance = true | Appearance

The wrapper of `build_editor` that puts the root document inside an
[`AppearanceDocument`](@ref) and the projection inside an
[`AppearanceManagingProjection`](@ref), around everything else, the window
manager too. It is on by default.

Its argument is the `Appearance` that the projection was built with. For `true`
the wrapper makes a new one before the editor is built, and `build_editor` gives
the same object to the projection that it makes when the caller names none.

The wrapper copies the colour settings of the operating system that the backend
of the parts finds into the appearance before the editor exists, so a setting
`:system` follows them from the first print, which the editor makes when it is
made. A start step copies the zoom of the appearance into the `Display` of the
editor, so an editor starts at the zoom that its appearance holds; and one gives
each window of the screen of the editor the colour of the role `background` as
its background, which follows a change of the colour settings.
"""
function wrap_editor!(::Val{:appearance}, layer::Symbol, argument, parts::EditorParts)
    parts.document isa AppearanceDocument && return parts
    appearance = make_wrapper_argument(Val(:appearance), argument)::Appearance
    copy_system_colors!(parts.backend, appearance)
    parts.document = make_appearance_document(parts.document, appearance)
    parts.projection = AppearanceManagingProjection(parts.projection)
    push!(parts.start_steps, editor -> copy_zoom_to_display!(editor, appearance))
    push!(parts.start_steps, editor -> follow_window_backgrounds!(editor.document, appearance))
    parts
end

"""
    copy_system_colors!(backend, appearance) -> nothing

Copy the colour settings of the operating system, as `backend` finds them, into
the `system_colors` of `appearance`. A missing backend, or a backend that finds
nothing, changes nothing. Call it before the first print: a style field of a
projection reads the colours with no edge, so a part that the first print drew
keeps the colours of that print until the view prints again. A later change
comes as a `SystemColorsChange`, which `AppearanceManagingProjection` reads, and
which prints the view again.
"""
function copy_system_colors!(backend, appearance::Appearance)
    backend === nothing && return nothing
    # Through `invokelatest`: each backend package adds a method, and a call that
    # inference resolves would be invalidated when such a package loads.
    colors = Base.invokelatest(find_system_colors, backend)
    colors === nothing || (appearance.system_colors = colors)
    nothing
end

"""
    follow_window_backgrounds!(document, appearance) -> nothing

Give each window of the screen that `document` holds, through its wrappers, the
colour of the role `background` of `appearance` as its background: a computed
cell, so the background follows a change of the mode, the palette and the
neutral. A document that holds no screen changes nothing.
"""
function follow_window_backgrounds!(document, appearance::Appearance)
    screen = _find_screen_document(document)
    screen === nothing && return nothing
    for window in screen.windows
        window isa Cell && (window = window[])
        set_cell_computation!(getfield(window, :bg), () -> _get_background_bytes(appearance))
    end
    nothing
end

# The screen inside `document`: the document itself, the content of an appearance
# document, or the screen inside a document that wraps another; `nothing` for
# none.
function _find_screen_document(document)
    for _ in 1:16
        document isa ScreenDocument && return document
        document = document isa AppearanceDocument ? document.content :
                   hasmethod(get_wrapped_document, Tuple{typeof(document)}) ?
                       get_wrapped_document(document) : nothing
        document === nothing && return nothing
    end
    nothing
end

# The colour of the role `background` of `appearance` as the four bytes of the
# background of a window.
function _get_background_bytes(appearance::Appearance)
    color = resolve_theme_color(ColorRole(:background), appearance)
    Tuple(UInt8(round(Int, clamp(c, 0, 1) * 255))
          for c in (color.red, color.green, color.blue, color.alpha))::NTuple{4,UInt8}
end

make_wrapper_argument(::Val{:appearance}, argument::Bool) = Appearance()
make_wrapper_argument(::Val{:appearance}, argument::Appearance) = argument

get_wrapper_layers(::Val{:appearance}) = (:screen => 0,)
is_wrapper_default(::Val{:appearance}) = true
