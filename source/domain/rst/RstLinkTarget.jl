# Fragment of `RstModule` — a reference: the gestures that follow it, and what its
# target names, for a navigator whose content is a document: an `.. _name:` target
# names the part after it, a section its title, a relative path a file beside the
# file of the document, and a URL nothing here.

# ── The gestures of a reference ───────────────────────────────────────────────
#
# A reference answers the target form of `OpenPageOperation`: its embedded target,
# or its text for a named reference. In the source view a press puts the caret in
# its text, so Ctrl+click follows it and Ctrl+Shift+click opens it in a new tab;
# the rendered view, which shows no markers, follows it on a plain click and opens
# a new tab on Ctrl+click. Each is an `override` rule, which takes the click from
# the caret of the text. The tooltip of a reference shows its target.

_get_reference_target(reference::RstReference) =
    isempty(reference.target) ? reference.text : reference.target

_make_reference_binding(modifiers::Vector{Symbol}, place::Symbol, description::String) =
    GestureBinding(MouseClickPattern(:left; modifiers),
                   (reference, gesture) -> OpenPageOperation(nothing, EmptyReference(), place;
                                                             target = _get_reference_target(reference));
                   description, domain = "rst", override = true)

const _RST_REFERENCE_BINDINGS = GestureBinding[
    _make_reference_binding([:ctrl], :here, "Follow the reference"),
    _make_reference_binding([:ctrl, :shift], :new_tab, "Open the reference in a new tab"),
    make_tooltip_binding(reference -> isempty(_get_reference_target(reference)) ? nothing :
                                      PrimitiveString(_get_reference_target(reference));
                         description = "Show the target of the reference")]

@gestures RstReference begin
    splice(_RST_REFERENCE_BINDINGS)
end

const _RENDERED_REFERENCE_BINDINGS = GestureBinding[
    _make_reference_binding(Symbol[], :here, "Follow the reference"),
    _make_reference_binding([:ctrl], :new_tab, "Open the reference in a new tab")]

get_projection_gesture_bindings(p::RstReferenceToSyntaxNode, iomap) =
    p.show_markers ? GestureBinding[] : _RENDERED_REFERENCE_BINDINGS

# ── What a target names ───────────────────────────────────────────────────────

# A name as rst compares it: in lower case, with each run of space one space.
_normalize_rst_name(name::AbstractString) = lowercase(join(split(name), " "))

find_navigator_target(root::RstRoot, target::AbstractString) =
    _find_rst_target(root, _normalize_rst_name(target), ReferenceStep[])

# A file names the targets and the sections of its document first, and else a
# file beside it by a relative path, when that file exists.
function find_navigator_target(file::RstFile, target::AbstractString)
    found = _find_rst_target(get_file_content(file), _normalize_rst_name(target),
                             ReferenceStep[FieldReferenceStep("content")])
    found === nothing || return found
    path = first(split(target, '#'; limit = 2))
    (isempty(path) || occursin(r"^[A-Za-z][A-Za-z0-9+.\-]*:", path)) && return nothing
    candidate = normpath(joinpath(dirname(abspath(file.filename)), path))
    isfile(candidate) ? candidate : nothing
end

# The part of `document` that the name `name` labels, depth first: the part after
# a target of that name, the target itself when nothing follows it, or a section
# whose title reads the name.
function _find_rst_target(document, name::AbstractString, steps::Vector{ReferenceStep})
    isempty(name) && return nothing
    elements = collect(_elements_of(document))
    for (index, element) in enumerate(elements)
        here = vcat(steps, FieldReferenceStep("elements"), RangeReferenceStep(index - 1, index))
        if element isa RstTarget && _normalize_rst_name(element.name) == name
            index < length(elements) &&
                return extend_reference(EmptyReference(), steps..., FieldReferenceStep("elements"),
                                        RangeReferenceStep(index, index + 1))
            return extend_reference(EmptyReference(), here...)
        end
        element isa RstSection || continue
        _normalize_rst_name(get_rst_title_text(element)) == name && return extend_reference(EmptyReference(), here...)
        found = _find_rst_target(element, name, here)
        found === nothing || return found
    end
    nothing
end
