# Fragment of `RstModule` — a reference: the gestures that follow it, the link that
# it is, and what its target names, for a navigator whose content is a document: an
# `.. _name:` target names the part after it, a section its title, an address of
# the web or of mail a place outside the editor, and a relative path a file beside
# the file of the document.

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
                                      TooltipNote(; title = "Reference",
                                                  facts = ["Target" => _get_reference_target(reference)]);
                         description = "Show the target of the reference")]

@gestures RstReference begin
    splice(_RST_REFERENCE_BINDINGS)
end

const _RENDERED_REFERENCE_BINDINGS = GestureBinding[
    _make_reference_binding(Symbol[], :here, "Follow the reference"),
    _make_reference_binding([:ctrl], :new_tab, "Open the reference in a new tab")]

get_projection_gesture_bindings(p::RstReferenceToSyntaxNode, iomap) =
    p.show_markers ? GestureBinding[] : _RENDERED_REFERENCE_BINDINGS

# ── The link that it is ──────────────────────────────────────────────────────

# A reference of rst is a link. An embedded target is its address. A named
# reference names a target of its document, as the fragment `#name`, as the HTML
# of docutils writes an internal reference, so a name with a colon in it is no
# address. Its face is its text.
is_link(::RstReference) = true
get_link_target(reference::RstReference) =
    isempty(reference.target) ? Url("#" * reference.text) : Url(reference.target)
get_link_content(reference::RstReference) = reference.text

# ── What a target names ───────────────────────────────────────────────────────

# A name as rst compares it: in lower case, with each run of space one space.
_normalize_rst_name(name::AbstractString) = lowercase(join(split(name), " "))

# The name that a target gives, also as the fragment `#name`.
_get_rst_target_name(target::AbstractString) = startswith(target, "#") ? chop(target; head = 1, tail = 0) : target

# A document names its targets and its sections, and an address outside the editor.
find_navigator_target(root::RstRoot, target::AbstractString) =
    something(_find_rst_target(root, _normalize_rst_name(_get_rst_target_name(target)), ReferenceStep[]),
              find_web_url(target), Some(nothing))

# A file names the targets and the sections of its document first, then an address
# outside the editor, and else a file beside it by a relative path, when that file
# exists.
function find_navigator_target(file::RstFile, target::AbstractString)
    found = _find_rst_target(get_file_content(file), _normalize_rst_name(_get_rst_target_name(target)),
                             ReferenceStep[FieldReferenceStep("content")])
    found === nothing || return found
    web = find_web_url(target)
    web === nothing || return web
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
