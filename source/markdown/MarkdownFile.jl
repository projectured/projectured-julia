"""
    MarkdownFileModule

`MarkdownFile`: a `FileDocument` whose `content` is a
`MarkdownDocument` (the projectured Markdown AST). Parse uses
`parse_markdown`; emit runs the standard `MarkdownToSyntax(style=:source)
→ SyntaxToText → TextToString` projection chain via `print_natural_text`.
This module also registers this domain's natural notation — the rung it starts
at, the format, the extension and the parser — so `print_natural_text` works for
a `MarkdownDocument` the way it works for every other domain.

**Marker syntax in Markdown.** A cross-file reference reads as a
fenced code block with the info string `pred-ref`:

    ```pred-ref
    <<file("child.md")>>
    ```

Fenced blocks parse robustly (unlike inline link URLs, which the
markdown parser stops at the first `)`). Load walks the AST for
`MarkdownCodeBlock` with `language == "pred-ref"` and rewrites each
into a `ReferenceStub`. Emit is symmetric via a projection extension
(see `MarkdownToSyntax.jl`).
"""
module MarkdownFileModule

import ..CellModule: Cell, ComputedCell, AbstractCell
import ..DocumentModule: @document
import ..ReferenceModule: Reference
import ..CollectionModule: CellVector, ComputedCellVector
import ..MarkdownModule: MarkdownDocument, MarkdownRoot, MarkdownParagraph,
                         MarkdownHeading, MarkdownCodeBlock, MarkdownQuote,
                         MarkdownList, MarkdownListItem, MarkdownEmphasis,
                         MarkdownStrong, MarkdownLink, MarkdownText
import ..MarkdownParserModule: parse_markdown
import ..MarkdownToSyntaxModule: MarkdownToSyntax
import ..NaturalNotationModule: register_natural_domain!, print_natural_text
import ..SerializationModule: FileDocument, emit_text, populate_file!, get_file_content,
                            parse_marker_text, ReferenceStub, LoaderContext,
                            register_file_document_type!, get_document_section,
                            is_file_document

export MarkdownFile, PRED_REF_LANGUAGE, get_markdown_section

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
    content::MarkdownDocument = MarkdownRoot()
end

emit_text(f::MarkdownFile) = print_natural_text(get_file_content(f))

function populate_file!(f::MarkdownFile, filename::AbstractString, ctx::LoaderContext)
    text = read(joinpath(ctx.base_dir, filename), String)
    ast = parse_markdown(text)
    ast = _substitute_markers(ast, ctx)
    getfield(f, :content)[] = ast
    f
end

# Unwrap a cell if we've grabbed one via getfield (a `CellVector`'s
# elements are `Cell`s already, so mid-walk we may hold either).
_unwrap(x) = x isa AbstractCell ? x[] : x

_is_marker_block(node::MarkdownCodeBlock) =
    _unwrap(getfield(node, :language)) == PRED_REF_LANGUAGE

function _marker_stub(node::MarkdownCodeBlock, ctx::LoaderContext)
    body = _unwrap(getfield(node, :code))
    src = parse_marker_text(strip(body))
    src === nothing ? node : ReferenceStub(src, ctx)
end

# Traversal: every container replaces its child-slot values in place
# with substituted values. Non-container nodes pass through.
_substitute_markers(node, ctx::LoaderContext) = node

function _substitute_markers(node::MarkdownCodeBlock, ctx::LoaderContext)
    _is_marker_block(node) ? _marker_stub(node, ctx) : node
end

# CellVector-backed containers: rewrite each element in place. An INLINE
# container additionally splits its text runs, because a marker written in a
# line of prose becomes several elements where there was one.
function _visit_vector!(node, field::Symbol, ctx::LoaderContext; inline::Bool = false)
    v = getfield(node, field)[]
    for i in eachindex(v)
        v[i] = _substitute_markers(v[i], ctx)
    end
    inline && _split_inline_markers!(v, ctx)
    node
end

# `text <<marker>> more text` → three elements. The stub remembers that it was
# written inline, so the save path puts it back the way it was found.
function _split_inline_markers!(collection, ctx::LoaderContext)
    # The collection's raw storage: splicing needs the cells themselves, and a
    # CellVector offers indexing rather than the vector operations this wants.
    v = getfield(collection, :elements)[]
    any(cell -> _unwrap(cell) isa MarkdownText &&
                occursin(_INLINE_MARKER_RE, _unwrap(cell).content), v) || return collection
    rebuilt = Cell[]
    for cell in v
        node = _unwrap(cell)
        if !(node isa MarkdownText) || !occursin(_INLINE_MARKER_RE, node.content)
            push!(rebuilt, cell isa AbstractCell ? cell : Cell(cell))
            continue
        end
        text = node.content
        position = firstindex(text)
        for match in eachmatch(_INLINE_MARKER_RE, text)
            source = parse_marker_text(match.match)
            if source === nothing
                continue                       # `<<not a marker>>` stays text
            end
            before = text[position:prevind(text, match.offset)]
            isempty(before) || push!(rebuilt, Cell(MarkdownText(before)))
            push!(rebuilt, Cell(ReferenceStub(source, ctx; inline = true)))
            position = match.offset + ncodeunits(match.match)
        end
        rest = text[position:end]
        isempty(rest) || push!(rebuilt, Cell(MarkdownText(rest)))
    end
    empty!(v)
    append!(v, rebuilt)
    collection
end

# `<<…>>` inside a line. Non-greedy, so two markers in one line are two.
const _INLINE_MARKER_RE = r"<<.+?>>"

_substitute_markers(n::MarkdownRoot,      ctx::LoaderContext) = _visit_vector!(n, :elements, ctx)
_substitute_markers(n::MarkdownParagraph, ctx::LoaderContext) = _visit_vector!(n, :content,  ctx; inline=true)
_substitute_markers(n::MarkdownHeading,   ctx::LoaderContext) = _visit_vector!(n, :content,  ctx; inline=true)
_substitute_markers(n::MarkdownQuote,     ctx::LoaderContext) = _visit_vector!(n, :elements, ctx)
_substitute_markers(n::MarkdownList,      ctx::LoaderContext) = _visit_vector!(n, :items,    ctx)
_substitute_markers(n::MarkdownListItem,  ctx::LoaderContext) = _visit_vector!(n, :elements, ctx)
_substitute_markers(n::MarkdownEmphasis,  ctx::LoaderContext) = _visit_vector!(n, :content,  ctx; inline=true)
_substitute_markers(n::MarkdownStrong,    ctx::LoaderContext) = _visit_vector!(n, :content,  ctx; inline=true)
_substitute_markers(n::MarkdownLink,      ctx::LoaderContext) = _visit_vector!(n, :content,  ctx; inline=true)


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

# The `section` verb is one shared generic (`FileProjectModule.get_document_section`),
# because the registry holds one function per verb name. Markdown adds its method
# here; RST adds its own.
get_document_section(root::MarkdownRoot, title::AbstractString) = get_markdown_section(root, title)

function __init__()
    register_file_document_type!(".md",       MarkdownFile)
    register_file_document_type!(".markdown", MarkdownFile)
    # What this domain's natural notation is: the syntax rung, the format, and
    # how to read it back. The `:graphics` rung — a page of blocks — is
    # registered in `MarkdownToLayout.jl`, because a domain may reach more than
    # one rung and markdown reaches two.
    register_natural_domain!(MarkdownDocument;
                             rung      = :syntax,
                             make      = () -> MarkdownToSyntax(),
                             format    = :md,
                             extension = ".md",
                             parse     = parse_markdown)
end

end # module
