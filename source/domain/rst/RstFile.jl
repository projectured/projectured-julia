# Fragment of `RstModule` — `RstFile`, the `.rst` file on disk.
#
# A cross-file reference is written in reStructuredText as a `pred-ref`
# directive whose argument is the marker. The file writes one where the save
# cuts, and the load splices the node it names into its place. The `section`
# verb, which names a section by its title, lives here too.

"""
    RstFile(filename, content)

A file document whose `content` is an `RstDocument`.
"""
@document struct RstFile <: FileDocument
    filename::String
    content::Document = RstRoot()
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

# ── Addressing a section by its title ─────────────────────────────────────────

"""
    get_rst_title_text(section) -> String

The plain text of a section's title, with every inline marker dropped. This is
what addresses a section by name, so `:ned:`Foo`` in a title reads as `Foo`.
"""
function get_rst_title_text(section::RstSection)
    buffer = IOBuffer()
    _collect_run_text!(buffer, section.title)
    String(take!(buffer))
end

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
"""
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
