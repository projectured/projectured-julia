# Fragment of `MarkdownModule` — a link: the gestures that follow it, and what its
# target names, for a navigator whose content is a page: `#slug` names a heading
# of the page, a relative path names a file beside the file of the page, and a URL
# names nothing here.

# ── The gestures of a link ────────────────────────────────────────────────────
#
# A link answers the target form of `OpenPageOperation`, and the nearest navigator
# resolves it. In the source view a press puts the caret in the text of the link,
# so Ctrl+click follows the link and Ctrl+Shift+click opens it in a new tab; the
# rendered view follows it on a plain click and opens a new tab on Ctrl+click, as a
# browser does. Each is an `override` rule, which takes the click from the caret of
# the text. The tooltip of a link shows its target.

_make_link_open(link::MarkdownLink, place::Symbol) =
    OpenPageOperation(nothing, EmptyReference(), place; target = link.url)

_make_link_binding(modifiers::Vector{Symbol}, place::Symbol, description::String) =
    GestureBinding(MouseClickPattern(:left; modifiers), (link, gesture) -> _make_link_open(link, place);
                   description, domain = "markdown", override = true)

const _MARKDOWN_LINK_BINDINGS = GestureBinding[
    _make_link_binding([:ctrl], :here, "Follow the link"),
    _make_link_binding([:ctrl, :shift], :new_tab, "Open the link in a new tab"),
    make_tooltip_binding(link -> isempty(link.url) ? nothing : PrimitiveString(link.url);
                         description = "Show the target of the link")]

@gestures MarkdownLink begin
    splice(_MARKDOWN_LINK_BINDINGS)
end

const _RENDERED_LINK_BINDINGS = GestureBinding[
    _make_link_binding(Symbol[], :here, "Follow the link"),
    _make_link_binding([:ctrl], :new_tab, "Open the link in a new tab")]

get_projection_gesture_bindings(::MarkdownLinkToStyledNode, iomap) = _RENDERED_LINK_BINDINGS

# ── What a target names ───────────────────────────────────────────────────────

"""
    compute_markdown_heading_slug(heading) -> String

The anchor of `heading`, as GitHub writes it: the words of the heading in lower
case, a hyphen for each space, and no character that is not a letter, a digit, a
hyphen or an underscore. `[Install](#install-the-editor)` names the heading
"Install the editor".
"""
function compute_markdown_heading_slug(heading::MarkdownHeading)
    buffer = IOBuffer()
    for character in lowercase(_heading_text(heading))
        if isletter(character) || isdigit(character) || character in ('-', '_')
            print(buffer, character)
        elseif character == ' '
            print(buffer, '-')
        end
    end
    String(take!(buffer))
end

# A page names its headings; it has no file, so it names no file.
find_navigator_target(root::MarkdownRoot, target::AbstractString) =
    _find_markdown_heading(root, target, ReferenceStep[])

# A file names the headings of its page, and a file beside it by a relative path,
# when that file exists; the part after `#` in such a path is not followed.
function find_navigator_target(file::MarkdownFile, target::AbstractString)
    startswith(target, "#") &&
        return _find_markdown_heading(get_file_content(file), target, ReferenceStep[FieldReferenceStep("content")])
    _find_link_file(file.filename, target)
end

function _find_markdown_heading(root, target::AbstractString, steps::Vector{ReferenceStep})
    (startswith(target, "#") && root isa MarkdownRoot) || return nothing
    slug = target[2:end]
    for (index, element) in enumerate(root.elements)
        element isa MarkdownHeading && compute_markdown_heading_slug(element) == slug &&
            return extend_reference(EmptyReference(), steps..., FieldReferenceStep("elements"),
                                    RangeReferenceStep(index - 1, index))
    end
    nothing
end

# The file that `target` names beside the file `filename`, or `nothing` for a URL,
# an anchor, or a file that does not exist.
function _find_link_file(filename::AbstractString, target::AbstractString)
    path = first(split(target, '#'; limit = 2))
    (isempty(path) || occursin(r"^[A-Za-z][A-Za-z0-9+.\-]*:", path)) && return nothing
    found = normpath(joinpath(dirname(abspath(filename)), path))
    isfile(found) ? found : nothing
end
