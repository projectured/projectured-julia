# Fragment of `AppearanceModule` — the `appearance` wrapper of `build_editor`.

"""
    appearance = true | Appearance

The wrapper of `build_editor` that puts the root document inside an
[`AppearanceDocument`](@ref) and the projection inside an
[`AppearanceManagingProjection`](@ref), around everything else, the window
manager too. It is on by default.

Its argument is the `Appearance` that the projection was built with. For `true`
the wrapper makes a new one before the editor is built, and `build_editor` gives
the same object to the projection that it makes when the caller names none. A
start step copies the zoom of the appearance into the `Display` of the editor,
so an editor starts at the zoom that its appearance holds.
"""
function wrap_editor!(::Val{:appearance}, layer::Symbol, argument, parts::EditorParts)
    parts.document isa AppearanceDocument && return parts
    appearance = make_wrapper_argument(Val(:appearance), argument)::Appearance
    parts.document = make_appearance_document(parts.document, appearance)
    parts.projection = AppearanceManagingProjection(parts.projection)
    push!(parts.start_steps, editor -> copy_zoom_to_display!(editor, appearance))
    parts
end

make_wrapper_argument(::Val{:appearance}, argument::Bool) = Appearance()
make_wrapper_argument(::Val{:appearance}, argument::Appearance) = argument

get_wrapper_layers(::Val{:appearance}) = (:screen => 0,)
is_wrapper_default(::Val{:appearance}) = true
