"""
    RstFileModule

`RstFile`: a `FileDocument` whose `content` is an `RstDocument` (the
projectured reStructuredText tree). Parse uses `rstparse`; emit runs the
standard `RstToSyntax(style=:source) → SyntaxToText → TextToString`
projection chain through `print_natural_text`.

This module also registers this domain's natural notation — the rung it starts
at, the format, the extension and the parser — and `.rst` as a file document
type, so `import_document` and `export_document` reach the slice by extension.

**Marker syntax in RST.** A cross-file reference reads as a directive
whose argument is the marker:

    .. pred-ref:: <<file("child.json")>>

The directive needs no parser rule: a name the parser does not know
already becomes an `RstDirective` carrying its name and its argument,
and emit writes it back as it was. Load walks the block tree for an
`RstDirective` named `pred-ref` whose argument parses as a marker, and
rewrites each into a `ReferenceStub`. Emit is symmetric through the
projection (see `RstToSyntax.jl`).

A marker written **in a line of prose** is not read yet: a block is
what a marker stands for here, and the markdown slice's text-run
splitting has no RST counterpart.
"""
module RstFileModule

import ..CellModule: Cell, AbstractCell
import ..DocumentModule: @document
import ..CollectionModule: CellVector
import ..ReferenceModule: Reference
import ..RstModule: RstDocument, RstRoot, RstSection, RstText, RstLiteral, RstRole,
                    RstStrong, RstEmphasis, RstDirective, RstListItem, RstBulletList,
                    RstEnumeratedList, RstDefinitionList, RstDefinitionItem,
                    RstFieldList, RstField, RstBlockQuote, RstFootnote, RstAdmonition,
                    RstGridTable, RstTableRow, RstTableCell
import ..RstParserModule: rstparse
import ..RstToSyntaxModule: RstToSyntax, PRED_REF_DIRECTIVE
import ..NaturalNotationModule: register_natural_domain!, print_natural_text
import ..FileProjectModule: FileDocument, emit_text, populate_file!, get_file_content,
                            LoaderContext, register_file_document_type!,
                            get_document_section, parse_marker_text, ReferenceStub

export RstFile, rst_section, rst_title_text, PRED_REF_DIRECTIVE

"""
    RstFile(filename, content)

A file document whose `content` is an `RstDocument`.
"""
@document struct RstFile <: FileDocument
    filename::String
    content::RstDocument = RstRoot()
end

emit_text(f::RstFile) = print_natural_text(get_file_content(f))

function populate_file!(f::RstFile, filename::AbstractString, ctx::LoaderContext)
    text = read(joinpath(ctx.base_dir, filename), String)
    getfield(f, :content)[] = _substitute_markers(rstparse(text), ctx)
    f
end

# ── Markers ───────────────────────────────────────────────────────────────────

# A cell may still be a cell mid-walk: a CellVector holds cells.
_unwrap(x) = x isa AbstractCell ? x[] : x

# Traversal: every container rewrites its own child slots in place, and a node
# that owns no blocks passes through. A marker directive becomes a stub; a
# `pred-ref` whose argument is not a marker stays the directive it was, so a
# typing mistake shows on the page instead of vanishing.
_substitute_markers(node, ctx::LoaderContext) = node

function _substitute_markers(node::RstDirective, ctx::LoaderContext)
    if _unwrap(getfield(node, :name)) == PRED_REF_DIRECTIVE
        source = parse_marker_text(strip(_unwrap(getfield(node, :argument))))
        source === nothing || return ReferenceStub(source, ctx)
    end
    _visit_vector!(node, :elements, ctx)
end

function _visit_vector!(node, field::Symbol, ctx::LoaderContext)
    elements = getfield(node, field)[]
    for i in eachindex(elements)
        elements[i] = _substitute_markers(elements[i], ctx)
    end
    node
end

# Every container that can hold a block, and therefore a marker. An inline
# container is absent on purpose: an inline marker is not read (see the module
# docstring), so walking a paragraph's runs would find nothing to rewrite.
_substitute_markers(n::RstRoot,           ctx::LoaderContext) = _visit_vector!(n, :elements, ctx)
_substitute_markers(n::RstSection,        ctx::LoaderContext) = _visit_vector!(n, :elements, ctx)
_substitute_markers(n::RstListItem,       ctx::LoaderContext) = _visit_vector!(n, :elements, ctx)
_substitute_markers(n::RstField,          ctx::LoaderContext) = _visit_vector!(n, :elements, ctx)
_substitute_markers(n::RstBlockQuote,     ctx::LoaderContext) = _visit_vector!(n, :elements, ctx)
_substitute_markers(n::RstFootnote,       ctx::LoaderContext) = _visit_vector!(n, :elements, ctx)
_substitute_markers(n::RstAdmonition,     ctx::LoaderContext) = _visit_vector!(n, :elements, ctx)
_substitute_markers(n::RstTableCell,      ctx::LoaderContext) = _visit_vector!(n, :elements, ctx)
_substitute_markers(n::RstBulletList,     ctx::LoaderContext) = _visit_vector!(n, :items,    ctx)
_substitute_markers(n::RstEnumeratedList, ctx::LoaderContext) = _visit_vector!(n, :items,    ctx)
_substitute_markers(n::RstDefinitionList, ctx::LoaderContext) = _visit_vector!(n, :items,    ctx)
_substitute_markers(n::RstFieldList,      ctx::LoaderContext) = _visit_vector!(n, :fields,   ctx)
_substitute_markers(n::RstGridTable,      ctx::LoaderContext) = _visit_vector!(n, :rows,     ctx)
_substitute_markers(n::RstTableRow,       ctx::LoaderContext) = _visit_vector!(n, :cells,    ctx)
# A definition's body holds blocks; its term holds inline runs.
_substitute_markers(n::RstDefinitionItem, ctx::LoaderContext) = _visit_vector!(n, :elements, ctx)


# ── Addressing a section by its title ─────────────────────────────────────────

"""
    rst_title_text(section) -> String

The plain text of a section's title, with every inline marker dropped. This is
what addresses a section by name, so `:ned:`Foo`` in a title reads as `Foo`.
"""
function rst_title_text(section::RstSection)
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
    rst_section(document, title) -> RstSection or nothing

The section of `document` whose title reads `title`, searched depth first.

The section tree already owns its blocks, so this returns the node itself —
unlike the markdown counterpart, which has to gather the blocks that follow a
heading because markdown headings do not nest.
"""
function rst_section(document, title::AbstractString)
    for element in _elements_of(document)
        element isa RstSection || continue
        rst_title_text(element) == title && return element
        found = rst_section(element, title)
        found === nothing || return found
    end
    nothing
end

_elements_of(document::RstRoot)    = document.elements
_elements_of(document::RstSection) = document.elements
_elements_of(::Any)                = ()

# The `section` verb is one shared generic; RST adds its method here, markdown
# adds its own. A marker that names no section fails loudly rather than embed
# nothing, which is what `rst_section` answers for a caller that wants to look.
function get_document_section(document::Union{RstRoot,RstSection}, title::AbstractString)
    found = rst_section(document, title)
    found === nothing &&
        error("section(…): no title reads ", repr(title),
              " — the document has (", join(_section_titles(document), ", "), ")")
    found
end

# Every section title in the tree, depth first — the error message's inventory.
function _section_titles(document, acc = String[])
    for element in _elements_of(document)
        element isa RstSection || continue
        push!(acc, rst_title_text(element))
        _section_titles(element, acc)
    end
    acc
end

function __init__()
    register_file_document_type!(".rst", RstFile)
    # What this domain's natural notation is: the syntax rung, the format, and
    # how to read it back. The `:graphics` rung — a page of blocks — is
    # registered in `RstToLayout.jl`.
    register_natural_domain!(RstDocument;
                             rung      = :syntax,
                             make      = () -> RstToSyntax(),
                             format    = :rst,
                             extension = ".rst",
                             parse     = rstparse)
end

end # module
