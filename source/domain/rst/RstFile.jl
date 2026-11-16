# Fragment of `RstModule` — `RstFile`, the `.rst` file on disk, and
# `RstFileFormat`, its format.
#
# A cross-file reference is written in reStructuredText as a `pred-ref`
# directive whose argument is the marker. The file writes one where the save
# cuts, and the load splices the node it names into its place. The `section`
# verb, which names a section by its title, and the pictures that the figures and
# the images of a file hold live here too.

"""
    RstFile(filename, content)

A file document whose `content` is an `RstDocument`.
"""
@document struct RstFile <: FileDocument
    filename::String
    content::Document = RstRoot()
    disk::FileDiskState = FileDiskState()
end

emit_text(f::RstFile) = print_natural_text(get_file_content(f))

# ── Markers ───────────────────────────────────────────────────────────────────

# A cell may still be a cell mid-walk: a CellVector holds cells.
_unwrap(x) = x isa AbstractCell ? x[] : x

# What the file writes itself, and how it spells a reference to what it does
# not: a `pred-ref` directive whose argument is the marker. A `pred-ref` whose
# argument is not a marker stays the directive it was, so a typing mistake shows
# on the page instead of vanishing.
get_file_domain(::Type{<:RstFile}) = RstDocument
make_reference_leaf(::RstFile, marker::AbstractString) =
    RstDirective(PRED_REF_DIRECTIVE, make_marker_text(marker))
find_reference_marker(node::RstDirective) =
    _unwrap(getfield(node, :name)) == PRED_REF_DIRECTIVE ?
        parse_marker_text(strip(_unwrap(getfield(node, :argument)))) : nothing
parse_file_content(::Type{<:RstFile}, text::AbstractString) = parse_rst(text)

"""
    RstFileFormat()

The format of a `.rst` file: its string is the reStructuredText of one
document, an `RstDocument`, and its file is an `RstFile`. A reference to another
file is a `pred-ref` directive whose argument is the marker.
"""
struct RstFileFormat <: FileFormat end

get_file_format_extensions(::RstFileFormat) = (".rst",)
get_file_format_domain(::RstFileFormat) = RstDocument
parse_document_string(::RstFileFormat, string::AbstractString) = parse_rst(string)
make_reference_leaf(::RstFileFormat, marker::AbstractString) =
    RstDirective(PRED_REF_DIRECTIVE, make_marker_text(marker))
get_file_type(::RstFileFormat) = RstFile
get_file_format(::RstFile) = RstFileFormat()

# ── Addressing a section by its title ─────────────────────────────────────────

"""
    get_rst_title_text(section) -> String

The plain text of a section's title, with every inline marker dropped. This is
what addresses a section by name, so `:ned:`Foo`` in a title reads as `Foo`.

Use it to read the words of a section title without its markup.

# Example

    rst_1 = parse_rst("Intro\\n=====\\n\\nText.")
    section_1 = find_rst_section(rst_1, "Intro")
    title_1 = get_rst_title_text(section_1)

See also `find_rst_section` and `parse_rst`.

For the assistant.
"""
function get_rst_title_text end

function get_rst_title_text(section::RstSection)
    buffer = IOBuffer()
    _collect_run_text!(buffer, section.title)
    String(take!(buffer))
end

get_rst_title_text(section::ReferencedDocument) = get_rst_title_text(get_document(section))

_collect_run_text!(buffer::IO, nodes) = (foreach(n -> _collect_title_text!(buffer, n), nodes); nothing)

_collect_title_text!(buffer::IO, node::RstText)     = (print(buffer, node.content); nothing)
_collect_title_text!(buffer::IO, node::RstLiteral)  = (print(buffer, node.content); nothing)
_collect_title_text!(buffer::IO, node::RstRole)     = (print(buffer, node.content); nothing)
_collect_title_text!(buffer::IO, node::RstStrong)   = _collect_run_text!(buffer, node.content)
_collect_title_text!(buffer::IO, node::RstEmphasis) = _collect_run_text!(buffer, node.content)
_collect_title_text!(::IO, ::Any) = nothing

"""
    find_rst_section(document, title) -> RstSection or nothing

The section of `document` whose title reads `title`, searched depth first.

The section tree already owns its blocks, so this returns the node itself —
unlike the markdown counterpart, which has to gather the blocks that follow a
heading because markdown headings do not nest.

Use it to take one section out of a reStructuredText page by its title.

# Example

    rst_1 = parse_rst("Intro\\n=====\\n\\nText.")
    section_1 = find_rst_section(rst_1, "Intro")

See also `get_rst_title_text`, `parse_rst` and `get_markdown_section`.

For the assistant.
"""
function find_rst_section end

function find_rst_section(document, title::AbstractString)
    for element in _elements_of(document)
        element isa RstSection || continue
        get_rst_title_text(element) == title && return element
        found = find_rst_section(element, title)
        found === nothing || return found
    end
    nothing
end

_elements_of(document::RstRoot)    = document.elements
_elements_of(document::RstSection) = document.elements
_elements_of(::Any)                = ()

# The `section` verb is one shared generic; RST adds its method here, markdown
# adds its own. A marker that names no section fails loudly rather than embed
# nothing, which is what `find_rst_section` answers for a caller that wants to look.
function get_document_section(document::Union{RstRoot,RstSection}, title::AbstractString)
    found = find_rst_section(document, title)
    found === nothing &&
        error("section(…): no title reads ", repr(title),
              " — the document has (", join(_section_titles(document), ", "), ")")
    found
end

# Every section title in the tree, depth first — the error message's inventory.
function _section_titles(document, acc = String[])
    for element in _elements_of(document)
        element isa RstSection || continue
        push!(acc, get_rst_title_text(element))
        _section_titles(element, acc)
    end
    acc
end

# ── The pictures of the figures and the images ─────────────────────────────
# A figure and an image hold the editor's one file document of the picture that their
# path names, as an image of a Markdown page does: the open and each load of the file
# give it, against the folder of the file; the root holds its figures and images while
# a holder holds the file, and each holds its picture. A url of the web and a path of a
# file that is not a picture name no picture. An edit changes no hold.

get_view_state_fields(::Type{<:Union{RstFigure, RstImage}}) = (:picture,)

function splice_named_file!(node::Union{RstFigure, RstImage}, find_file)
    path = node.path
    (find_web_url(path) === nothing && is_picture_file_path(path)) || return nothing
    file = find_file(path)
    file isa ImageFile && (node.picture = path => file)
    nothing
end

acquire_document!(editor, node::Union{RstFigure, RstImage}) =
    hold_documents!(editor, node, _collect_held_pictures(node))
release_document!(editor, node::Union{RstFigure, RstImage}) =
    release_held_documents!(editor, node, _collect_held_pictures(node))

# The picture file that `node` holds for its path now, as the only element.
function _collect_held_pictures(node::Union{RstFigure, RstImage})
    file = find_held_picture(node.picture, node.path)
    file === nothing ? Any[] : Any[file]
end

acquire_document!(editor, root::RstRoot) = hold_documents!(editor, root, _collect_rst_pictured_nodes(root))
release_document!(editor, root::RstRoot) =
    release_held_documents!(editor, root, _collect_rst_pictured_nodes(root))

# Each figure and each image of the file `root`, at any depth.
_collect_rst_pictured_nodes(root::RstRoot) =
    Any[walk_document(DocumentWalk(), root, node -> node isa Union{RstFigure, RstImage};
                      limit = nothing, enter_matches = false)...]
