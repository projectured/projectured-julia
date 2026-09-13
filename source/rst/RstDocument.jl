"""
    RstModule

The reStructuredText document domain — inlines (text, literal, emphasis,
strong, role, reference, substitution, footnote reference), blocks (section,
paragraph, list, literal block, line block, table, quote, transition,
comment, target), and directives.

**Sections nest.** The RST source is flat: a title line followed by an
adornment line, where the adornment character alone decides the depth. The
document is a tree instead, so a section owns the blocks below it and can be
collapsed. `RstSection.adornment` keeps the character the file used, so emit
reproduces the file's own convention rather than imposing one.

**Directives are typed where it pays.** The twelve directives that carry
meaning for the rendered notation — a figure has a picture, a code block has
a language, an admonition has a kind — get their own struct with named
fields. Everything else is an `RstDirective` with a name, an argument, and an
option list. A typed directive still carries `extra`, the options it does not
name, so emit loses nothing.

**Roles hold a plain string.** `:ned:`Foo`` has no nested markup, so
`RstRole.content` is a `String` and not a child sequence. The name stays a
string too: the set of roles is open (a document defines its own with
`.. role::`), and the projection maps the name to a style through a table.
"""
module RstModule

using ..CellModule
import ..CellModule: set_cell_function!, set_cell_value!
using ..DocumentModule
using ..CollectionModule
using ..ReferenceModule
export RstDocument, set_cell_function!
export parse_rst, parse_rst_file
using ..ProjectionApiModule
import ..ProjectionApiModule: print_document, read_intent, map_reference_forward, map_reference_backward
using ..ProjectionModule
using ..TextModule
using ..StyleModule
using ..BackendModule
using ..IoMapModule
using ..PrinterContextModule
using ..ProjectionReferenceStepModule
using ..OperationModule
using ..PrimitiveModule
using ..SyntaxModule
using ..SerializationModule
import ..SerializationModule: emit_text, populate_file!, get_document_section
using ..ProjectionAlgebraModule
using ..ProjectionTemplateModule
using ..IntentModule
export RstInsertionToSyntaxLeaf, RstTextToSyntaxLeaf, RstLiteralToSyntaxLeaf,
       RstEmphasisToSyntaxNode, RstStrongToSyntaxNode, RstRoleToSyntaxNode,
       RstReferenceToSyntaxNode, RstSubstitutionReferenceToSyntaxLeaf,
       RstFootnoteReferenceToSyntaxLeaf, RstParagraphToSyntaxNode,
       RstLiteralBlockToSyntaxLeaf, RstLineBlockToSyntaxNode, RstListItemToSyntaxNode,
       RstBulletListToSyntaxNode, RstEnumeratedListToSyntaxNode,
       RstDefinitionItemToSyntaxNode, RstDefinitionListToSyntaxNode,
       RstFieldToSyntaxNode, RstFieldListToSyntaxNode, RstBlockQuoteToSyntaxNode,
       RstTransitionToSyntaxLeaf, RstCommentToSyntaxLeaf, RstTargetToSyntaxLeaf,
       RstSubstitutionDefinitionToSyntaxNode, RstFootnoteToSyntaxNode,
       RstTableCellToSyntaxNode, RstTableRowToSyntaxNode, RstGridTableToSyntaxNode,
       RstDirectiveOptionToSyntaxNode, RstLiteralIncludeToSyntaxNode,
       RstFigureToSyntaxNode, RstCodeBlockToSyntaxNode, RstImageToSyntaxNode,
       RstVideoToSyntaxNode, RstAudioToSyntaxNode, RstAdmonitionToSyntaxNode,
       RstToctreeToSyntaxNode, RstMathBlockToSyntaxLeaf, RstRawBlockToSyntaxLeaf,
       RstRoleDefinitionToSyntaxNode, RstDirectiveToSyntaxNode, RstSectionToSyntaxNode,
       RstRootToSyntaxNode, RstStyledTextToSyntaxLeaf, RstStyledInline,
       RstStrongToStyledNode, RstEmphasisToStyledNode, RstRoleToStyledLeaf,
       RstSectionToStyledNode, RstFigureToStyledNode, RstImageToStyledNode,
       RstLiteralIncludeToStyledLeaf, RstEnumeratedListToStyledNode,
       RstToSyntax
using ..NaturalModule
export RstFile, find_rst_section, get_rst_title_text, PRED_REF_DIRECTIVE
using ..LayoutModule
using ..WidgetModule
export RstRootToVerticalLayout, RstSectionToVerticalLayout
export RstRoot, RstSection, RstParagraph, RstText, RstLiteral, RstEmphasis, RstStrong, RstRole, RstReference, RstSubstitutionReference, RstFootnoteReference, RstLiteralBlock, RstLineBlock, RstListItem, RstBulletList, RstEnumeratedList, RstDefinitionItem, RstDefinitionList, RstField, RstFieldList, RstBlockQuote, RstTransition, RstComment, RstTarget, RstSubstitutionDefinition, RstFootnote, RstTableCell, RstTableRow, RstGridTable, RstDirectiveOption, RstLiteralInclude, RstFigure, RstCodeBlock, RstImage, RstVideo, RstAudio, RstAdmonition, RstToctree, RstMathBlock, RstRawBlock, RstRoleDefinition, RstDirective, RstInsertion



abstract type RstDocument <: Document end

# Wrap a plain vector as a `CellVector`, the way the hand-written keyword
# constructors below need. The macro does this for a struct with exactly one
# collection field (Rule C); a struct with two needs it by hand.
_rst_cellvector(items) =
    items isa CellVector ? items :
    CellVector(Cell[x isa Cell ? x : Cell(x) for x in items])

# ── Insertion cursor ──────────────────────────────────────────────────────────

"""
A placeholder for an RST node being entered (the insert-by-typing cursor);
type-to-replace swaps it for concrete content.
"""
@document struct RstInsertion <: RstDocument
    value::Any = nothing
end

# ── Inline nodes ──────────────────────────────────────────────────────────────

"""
A run of plain inline text. Supports `[]` / `[]=` on the content.
"""
@document struct RstText <: RstDocument
    content::String
end

Base.getindex(t::RstText) = t.content::String
Base.setindex!(t::RstText, v::AbstractString) = (t.content = String(v))
set_cell_function!(t::RstText, f::Function) = (set_cell_function!(getfield(t, :content), f); t)
set_cell_value!(t::RstText, v::AbstractString) = (set_cell_value!(getfield(t, :content), String(v)); t)

"""
An inline literal (`` ``code`` ``). Supports `[]` / `[]=` on the content.
"""
@document struct RstLiteral <: RstDocument
    content::String
end

Base.getindex(l::RstLiteral) = l.content::String
Base.setindex!(l::RstLiteral, v::AbstractString) = (l.content = String(v))
set_cell_function!(l::RstLiteral, f::Function) = (set_cell_function!(getfield(l, :content), f); l)
set_cell_value!(l::RstLiteral, v::AbstractString) = (set_cell_value!(getfield(l, :content), String(v)); l)

"""
Emphasised (italic) inline content (`*…*`), a sequence of inline nodes.
"""
@document struct RstEmphasis <: RstDocument
    content::CellVector = CellVector()
end

@forward_vector_protocol on RstEmphasis to content

"""
Strong (bold) inline content (`**…**`), a sequence of inline nodes.
"""
@document struct RstStrong <: RstDocument
    content::CellVector = CellVector()
end

@forward_vector_protocol on RstStrong to content

"""
An interpreted text role — `:ned:`Foo``. `name` is the role name without its
colons and `content` the interpreted text. A role body carries no nested
markup, so `content` is a plain string.

The role set is open: a document declares its own with `.. role::`, which
parses to an [`RstRoleDefinition`](@ref). The projection maps `name` to a
style through a table and falls back to a neutral style for an unknown name.
"""
@document struct RstRole <: RstDocument
    name::String
    content::String
end

"""
A hyperlink reference. Two source forms map here:

- `` `text <url>`_ `` — an embedded target; `target` is the URL.
- `` `name`_ `` — a named reference resolved elsewhere; `target` is empty.

`anonymous` marks the double-underscore form (`` `text <url>`__ ``), which
the corpus uses for its "Source files location" links.
"""
@document struct RstReference <: RstDocument
    text::String
    target::String = ""
    anonymous::Bool = false
end

"""
A substitution reference (`|name|`), replaced at build time by the body of
the matching [`RstSubstitutionDefinition`](@ref).
"""
@document struct RstSubstitutionReference <: RstDocument
    name::String
end

"""
A footnote reference (`[1]_`, `[#]_`, `[#label]_`). `label` is the text
between the brackets.
"""
@document struct RstFootnoteReference <: RstDocument
    label::String
end

# ── Block nodes ───────────────────────────────────────────────────────────────

"""
A prose paragraph — a sequence of inline nodes.
"""
@document struct RstParagraph <: RstDocument
    content::CellVector = CellVector()
end

@forward_vector_protocol on RstParagraph to content

"""
A literal block — the indented verbatim text introduced by a paragraph that
ends with `::`. The body keeps its own relative indentation.
"""
@document struct RstLiteralBlock <: RstDocument
    content::String
end

Base.getindex(b::RstLiteralBlock) = b.content::String
Base.setindex!(b::RstLiteralBlock, v::AbstractString) = (b.content = String(v))

"""
A line block (`| …`) — lines whose breaks are significant. Each line is an
[`RstParagraph`](@ref) of inline nodes.
"""
@document struct RstLineBlock <: RstDocument
    lines::CellVector = CellVector()
end

@forward_vector_protocol on RstLineBlock to lines

"""
One item of a bullet or enumerated list. `elements` holds its child blocks (a
list item may itself contain paragraphs and nested lists); `collapsed` hides
them in the projection.
"""
@document struct RstListItem <: RstDocument
    elements::CellVector = CellVector()
    collapsed::Bool = false
end

@forward_vector_protocol on RstListItem to elements

"""
A bullet list. `marker` is the character the source used (`-`, `*` or `+`),
kept so emit reproduces it. `marker` is a required leading argument so
`items` reaches the `CellVector`-wrapping constructor:
`RstBulletList("-", [RstListItem(…), …])`.
"""
@document struct RstBulletList <: RstDocument
    marker::String
    items::CellVector = CellVector()
    collapsed::Bool = false
end

@forward_vector_protocol on RstBulletList to items

"""
An enumerated list. `style` is the source's numbering form, `"1."` or `"1)"`.
`start` is the first number.
"""
@document struct RstEnumeratedList <: RstDocument
    style::String
    items::CellVector = CellVector()
    start::Int = 1
    collapsed::Bool = false
end

@forward_vector_protocol on RstEnumeratedList to items

"""
One entry of a definition list: a term and the indented blocks that define it.
"""
@document struct RstDefinitionItem <: RstDocument
    term::CellVector = CellVector()
    elements::CellVector = CellVector()
    collapsed::Bool = false
end

RstDefinitionItem(term::AbstractVector; elements = [], collapsed::Bool = false) =
    RstDefinitionItem(_rst_cellvector(term), _rst_cellvector(elements),
                      Cell(collapsed), Cell(nothing))

"""
A definition list — a sequence of [`RstDefinitionItem`](@ref)s.
"""
@document struct RstDefinitionList <: RstDocument
    items::CellVector = CellVector()
end

@forward_vector_protocol on RstDefinitionList to items

"""
One field of a field list (`:name: value`). `elements` holds the field body
as blocks.
"""
@document struct RstField <: RstDocument
    name::String
    elements::CellVector = CellVector()
end

@forward_vector_protocol on RstField to elements

"""
A field list — a sequence of [`RstField`](@ref)s. Directive options are *not*
field lists: they belong to the directive that owns them.
"""
@document struct RstFieldList <: RstDocument
    fields::CellVector = CellVector()
end

@forward_vector_protocol on RstFieldList to fields

"""
A block quote — an indented run of blocks with no other marker. `attribution`
is the `-- Author` line, empty when absent.
"""
@document struct RstBlockQuote <: RstDocument
    elements::CellVector = CellVector()
    attribution::String = ""
    collapsed::Bool = false
end

@forward_vector_protocol on RstBlockQuote to elements

# Every field defaults, so the macro emits only the "fill everything" form
# `RstBlockQuote([...])` — the positional-defaults rule needs a required
# leading field and there is none. An attributed quote needs the arity-2 form
# by hand.
RstBlockQuote(elements::AbstractVector, attribution::AbstractString; collapsed::Bool = false) =
    RstBlockQuote(_rst_cellvector(elements), Cell(String(attribution)),
                  Cell(collapsed), Cell(nothing))

"""
A transition — a horizontal rule between blocks, written as a run of four or
more punctuation characters standing alone.
"""
@document struct RstTransition <: RstDocument
end

"""
A comment (`.. text that is not markup`). `content` keeps the body verbatim,
without the leading `.. `.
"""
@document struct RstComment <: RstDocument
    content::String
end

Base.getindex(c::RstComment) = c.content::String
Base.setindex!(c::RstComment, v::AbstractString) = (c.content = String(v))

"""
An internal hyperlink target (`.. _ug:cha:queueing:`). `name` is the target
name, which may itself contain colons.
"""
@document struct RstTarget <: RstDocument
    name::String
end

"""
A substitution definition (`.. |name| image:: …`). `body` is the directive
the substitution expands to.
"""
@document struct RstSubstitutionDefinition <: RstDocument
    name::String
    body::Any = nothing
end

"""
A footnote (`.. [1] text`). `label` is the text between the brackets.
"""
@document struct RstFootnote <: RstDocument
    label::String
    elements::CellVector = CellVector()
end

@forward_vector_protocol on RstFootnote to elements

# ── Tables ────────────────────────────────────────────────────────────────────

"""
One cell of a grid table — a sequence of blocks.
"""
@document struct RstTableCell <: RstDocument
    elements::CellVector = CellVector()
end

@forward_vector_protocol on RstTableCell to elements

"""
One row of a grid table — a sequence of [`RstTableCell`](@ref)s.
"""
@document struct RstTableRow <: RstDocument
    cells::CellVector = CellVector()
end

@forward_vector_protocol on RstTableRow to cells

"""
A grid table (the `+---+---+` form). `header_rows` is how many leading rows
the `+===+` separator marks as the head; it is `0` for a headless table.
`widths` keeps the source's column widths so emit redraws the same grid.
"""
@document struct RstGridTable <: RstDocument
    header_rows::Int
    rows::CellVector = CellVector()
    widths::Any = Int[]
    collapsed::Bool = false
end

@forward_vector_protocol on RstGridTable to rows

# ── Directives ────────────────────────────────────────────────────────────────

"""
One option line of a directive (`   :language: ini`). `value` is empty for a
flag option such as `:titlesonly:`.
"""
@document struct RstDirectiveOption <: RstDocument
    name::String
    value::String = ""
end

"""
`.. literalinclude:: path` — the most frequent directive in the INET
documentation. The four slicing options are named fields because they decide
*which* lines the rendered notation would show; every other option lands in
`extra`.

Resolving the referenced file is out of scope: the projection shows the
reference, it does not read the file.
"""
@document struct RstLiteralInclude <: RstDocument
    path::String
    language::String = ""
    start_at::String = ""
    end_at::String = ""
    start_after::String = ""
    end_before::String = ""
    extra::CellVector = CellVector()
    collapsed::Bool = false
end

"""
`.. figure:: path` — a picture with a caption. The caption is the indented
block that follows the options.
"""
@document struct RstFigure <: RstDocument
    path::String
    align::String = ""
    width::String = ""
    caption::CellVector = CellVector()
    extra::CellVector = CellVector()
end

RstFigure(path::AbstractString; align::AbstractString = "", width::AbstractString = "",
          caption = [], extra = []) =
    RstFigure(Cell(String(path)), Cell(String(align)), Cell(String(width)),
              _rst_cellvector(caption), _rst_cellvector(extra), Cell(nothing))

"""
`.. code-block:: language` — a verbatim block with a language for colouring.
`collapsed` hides the body behind a marker in the projection.
"""
@document struct RstCodeBlock <: RstDocument
    language::String
    code::String = ""
    extra::CellVector = CellVector()
    collapsed::Bool = false
end

"""
`.. image:: path` — a picture with no caption.
"""
@document struct RstImage <: RstDocument
    path::String
    width::String = ""
    height::String = ""
    alt::String = ""
    extra::CellVector = CellVector()
end

"""
`.. video:: path` — a movie. `.. video_noloop::` is the same directive with
`loop` set to `false`, which is how emit tells the two apart.
"""
@document struct RstVideo <: RstDocument
    path::String
    width::String = ""
    height::String = ""
    loop::Bool = true
    extra::CellVector = CellVector()
end

"""
`.. audio:: path` — a sound file.
"""
@document struct RstAudio <: RstDocument
    path::String
    extra::CellVector = CellVector()
end

"""
An admonition — `.. note::`, `.. warning::`, `.. important::`,
`.. caution::` or `.. todo::`. `kind` is the directive name. A one-line
admonition writes its text on the directive line; the parser normalises that
to a paragraph in `elements`, and emit writes the indented form.
"""
@document struct RstAdmonition <: RstDocument
    kind::String
    elements::CellVector = CellVector()
    collapsed::Bool = false
end

@forward_vector_protocol on RstAdmonition to elements

"""
`.. toctree::` — the table of contents of a page. Each entry is an
[`RstText`](@ref) holding a document path without its extension.
"""
@document struct RstToctree <: RstDocument
    maxdepth::Int = 0
    titlesonly::Bool = false
    glob::Bool = false
    entries::CellVector = CellVector()
    extra::CellVector = CellVector()
end

RstToctree(entries::AbstractVector; maxdepth::Integer = 0, titlesonly::Bool = false,
           glob::Bool = false, extra = []) =
    RstToctree(Cell(Int(maxdepth)), Cell(titlesonly), Cell(glob),
               _rst_cellvector(entries), _rst_cellvector(extra), Cell(nothing))

"""
`.. math::` — a display formula, kept as its LaTeX source.
"""
@document struct RstMathBlock <: RstDocument
    content::String
end

"""
`.. raw:: format` — verbatim output passed through to one builder.
"""
@document struct RstRawBlock <: RstDocument
    format::String
    content::String = ""
end

"""
`.. role:: name(base)` — a role declaration. The INET documentation declares
its own roles in `doc/src/global.rst` this way. `base` is the role the new
one derives from, empty when there is none.
"""
@document struct RstRoleDefinition <: RstDocument
    name::String
    base::String = ""
    extra::CellVector = CellVector()
end

"""
The generic directive — every directive without a struct of its own
(`only`, `graphviz`, `table`, `list-table`, `include`, `code`). `argument` is
the text on the directive line, `options` the `:name: value` lines, and
`elements` the indented body parsed as blocks.
"""
@document struct RstDirective <: RstDocument
    name::String
    argument::String = ""
    options::CellVector = CellVector()
    elements::CellVector = CellVector()
    collapsed::Bool = false
end

RstDirective(name::AbstractString, argument::AbstractString; options = [],
             elements = [], collapsed::Bool = false) =
    RstDirective(Cell(String(name)), Cell(String(argument)), _rst_cellvector(options),
                 _rst_cellvector(elements), Cell(collapsed), Cell(nothing))

# ── Section and root ──────────────────────────────────────────────────────────

"""
A section — a title and the blocks under it. The source is flat and the
document is a tree, so a section owns everything down to the next title at
its own depth or above.

`adornment` is the single character the source underlined the title with
(`=`, `-`, `~`, `^`, `+`, `*` or `#`). RST gives no fixed meaning to any of
them; the file's own order of first use decides the depth, and keeping the
character is what lets emit reproduce the file's convention. `overline` marks
a title that carries the adornment above as well as below.

`level` is the depth the parser resolved, counting from 1.
"""
@document struct RstSection <: RstDocument
    level::Int
    adornment::String = "="
    title::CellVector = CellVector()
    elements::CellVector = CellVector()
    overline::Bool = false
    collapsed::Bool = false
end

RstSection(level::Integer, adornment::AbstractString, title::AbstractVector;
           elements = [], overline::Bool = false, collapsed::Bool = false) =
    RstSection(Cell(Int(level)), Cell(String(adornment)), _rst_cellvector(title),
               _rst_cellvector(elements), Cell(overline), Cell(collapsed), Cell(nothing))

"""
The whole RST document — a top-level sequence of blocks. `collapsed` hides
the body behind a marker in the projection.
"""
@document struct RstRoot <: RstDocument
    elements::CellVector = CellVector()
    collapsed::Bool = false
end

@forward_vector_protocol on RstRoot to elements

# Text-replace edits need no per-type method: every type-in target field —
# `RstText.content`, `RstLiteral.content`, `RstRole.name`/`content`,
# `RstReference.text`/`target`, `RstCodeBlock.language`/`code`,
# `RstFigure.path`, `RstLiteralInclude.path` and its slice bounds, and
# `RstDirective.name`/`argument` — is a plain string, handled by the generic
# splice.


include("RstParser.jl")
include("RstToSyntax.jl")
include("RstFile.jl")
include("RstToLayout.jl")


# What this slice registers when it loads: the file extensions it owns, and
# the natural notation it reads and writes.
function __init__()
    register_natural_syntax!(:rst, () -> Pair{Type,Any}[RstDocument => RstToSyntax(style = :rendered)])

    register_file_document_type!(".rst", RstFile)
    # What this domain's natural notation is: the syntax rung, the format, and
    # how to read it back. The `:graphics` rung — a page of blocks — is
    # the call below it.
    register_natural_domain!(RstDocument;
                             rung      = :syntax,
                             make      = () -> RstToSyntax(),
                             format    = :rst,
                             extension = ".rst",
                             parse     = parse_rst)

    register_natural_graphics!(:rst_page, (; measure) -> Pair{Type,Any}[
        RstRoot    => ChainingProjection(RstRootToVerticalLayout(),
                                         VerticalLayoutToGraphicsCanvas()),
        RstSection => ChainingProjection(RstSectionToVerticalLayout(),
                                         VerticalLayoutToGraphicsCanvas()),
    ])
end

end # module
