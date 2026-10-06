# Fragment of `MarkdownModule` — `MarkdownFile`, the `.md` file on disk.
#
# A cross-file reference is written in Markdown as a fenced block in the
# `pred-ref` language holding the marker. The file writes one where the save
# cuts, and the load splices the node it names into its place. The `section`
# verb, which names what a heading heads, lives here too.

"""
The info string that tags a fenced code block as a cross-file marker:

    ```pred-ref
    <<file("path")>>
    ```
"""
const PRED_REF_LANGUAGE = "pred-ref"

"""
    MarkdownFile(filename, content)

A file document whose `content` is a `MarkdownDocument`. See the
module docstring for the fenced-block marker convention.
"""
@document struct MarkdownFile <: FileDocument
    filename::String
    content::Document = MarkdownRoot()
end

emit_text(f::MarkdownFile) = print_natural_text(get_file_content(f))

_unwrap(x) = x isa AbstractCell ? x[] : x

_is_marker_block(node::MarkdownCodeBlock) =
    _unwrap(getfield(node, :language)) == PRED_REF_LANGUAGE

# What the file writes itself, and how it spells a reference to what it does
# not: a fenced block in the `pred-ref` language holding the marker.
get_file_domain(::Type{<:MarkdownFile}) = MarkdownDocument
make_reference_leaf(::MarkdownFile, marker::AbstractString) =
    MarkdownCodeBlock(PRED_REF_LANGUAGE, make_marker_text(marker))
find_reference_marker(node::MarkdownCodeBlock) =
    _is_marker_block(node) ? parse_marker_text(strip(_unwrap(getfield(node, :code)))) : nothing
parse_file_content(::Type{<:MarkdownFile}, text::AbstractString) = parse_markdown(text)

# ── The `section` vocabulary function ──────────────────────────────────────

"""
    get_markdown_section(document, title) -> MarkdownRoot

The section of `document` headed `title`: the heading itself and every block
after it up to the next heading of the same or a higher level.

Addressing by the words of the heading is the markdown counterpart of
addressing a definition by its name — a section survives being moved, and
fails loudly when it is renamed rather than silently embedding the wrong part
of a page. Duplicate headings error for the same reason.

The returned root shares the page's own element objects, so what is embedded is
the section itself and not a copy of it.
"""
function get_markdown_section(document, title::AbstractString)
    root = is_file_document(document) ? get_file_content(document) : document
    root isa MarkdownRoot ||
        error("section(…): expected a markdown document, got ", typeof(document))
    wanted = strip(String(title))
    # The page's element CELLS, so the section can be built out of the very
    # objects the page holds rather than copies of them.
    cells = getfield(root.elements::CellVector, :elements)[]
    elements = [_unwrap(cell) for cell in cells]
    starts = Int[]
    for (index, element) in enumerate(elements)
        element isa MarkdownHeading || continue
        _heading_text(element) == wanted && push!(starts, index)
    end
    isempty(starts) &&
        error("section(…): no heading reads ", repr(wanted),
              " — the page has (", join(_heading_texts(elements), ", "), ")")
    length(starts) > 1 &&
        error("section(…): ", repr(wanted), " heads ", length(starts),
              " sections — a marker must name exactly one")
    first_index = starts[1]
    level = _unwrap(getfield(elements[first_index], :level))
    last_index = length(elements)
    for index in (first_index + 1):length(elements)
        element = elements[index]
        if element isa MarkdownHeading && _unwrap(getfield(element, :level)) <= level
            last_index = index - 1
            break
        end
    end
    # Keyword form: the positional constructor's collection sugar would wrap the
    # CellVector in a second one.
    MarkdownRoot(elements = CellVector(Cell[cells[i] for i in first_index:last_index]))
end

# A heading's words, with whatever emphasis it carries flattened away.
function _heading_text(heading::MarkdownHeading)
    buffer = IOBuffer()
    _collect_heading_text!(buffer, heading, 0)
    strip(String(take!(buffer)))
end

function _collect_heading_text!(buffer, node, depth)
    depth > 8 && return
    node = _unwrap(node)
    if node isa MarkdownText
        return print(buffer, node.content)
    end
    for field in (:content,)
        hasproperty(node, field) || continue
        value = getproperty(node, field)
        value isa AbstractString && (print(buffer, value); continue)
        value isa CellVector || continue
        for child in value
            _collect_heading_text!(buffer, child, depth + 1)
        end
    end
end

_heading_texts(elements) =
    String[_heading_text(e) for e in elements if e isa MarkdownHeading]

# The `section` verb is one shared generic (`SerializationModule.get_document_section`),
# because the registry holds one function per verb name. Markdown adds its method
# here; RST adds its own.
get_document_section(root::MarkdownRoot, title::AbstractString) = get_markdown_section(root, title)
