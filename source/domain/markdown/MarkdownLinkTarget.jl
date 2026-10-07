# Fragment of `MarkdownModule` — what the target of a link names, for a navigator
# whose content is a page: `#slug` names a heading of the page, a relative path
# names a file beside the file of the page, and a URL names nothing here.

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
