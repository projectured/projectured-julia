"""
    MarkdownModule

The Markdown document domain — blocks (headings, paragraphs, code blocks,
quotes, lists) and inlines (text, code, emphasis, strong, link, image).
"""
module MarkdownModule

import ..CellModule: Cell, ComputedCell, set_cell_function!, set_cell_value!
import ..DocumentModule: Document
import ..DocumentModule: @document, @forward_vector_protocol
import ..CollectionModule: CellVector, ComputedCellVector
import ..ReferenceModule: Reference
export MarkdownDocument, set_cell_function!
export parse_markdown, parse_markdown_file
import ..CellModule: Cell, ComputedCell, set_cell_function!
import ..ProjectionApiModule: Projection, print_document, print_child, read_intent,
                              map_reference_forward, map_reference_backward
import ..ProjectionModule: var"@projection"
import ..TextModule: TextString, make_hinted_text, TextGraphics
import ..StyleModule: ImageFile
import ..BackendModule: decode_image
import ..GraphicsModule: GraphicsDocument
import ..StyleModule: font_ubuntu_monospace_regular_20, font_ubuntu_monospace_bold_20,
                     font_ubuntu_regular_20, font_ubuntu_bold_20, font_ubuntu_italic_20,
                     font_ubuntu_bold_36, font_ubuntu_bold_24, font_ubuntu_bold_22, font_ubuntu_bold_18,
                     font_dejavu_monospace_regular_20
import ..StyleModule: color_black, color_solarized_blue, color_solarized_green,
                      color_solarized_magenta, color_solarized_cyan,
                      color_solarized_gray, color_solarized_violet
import ..StyleModule: StyleText
import ..SyntaxModule: SyntaxDocument, SyntaxLeaf, SyntaxNode, SyntaxConcatenation, SyntaxDelimitation
import ..ProjectionAlgebraModule: TypeDispatchingProjection
import ..ProjectionAlgebraModule: CopyingProjection
import ..IoMapModule: SimpleIoMap, ChildrenIoMap
import ..PrinterContextModule: make_child_context, with_property, get_property
import ..ReferenceModule: ConcreteReference, FieldReferenceStep, RangeReferenceStep, ElementReferenceStep,
                          EmptyReference
import ..ProjectionReferenceStepModule: ProjectionReferenceStep, is_introduced_reference
import ..ReferenceModule: var"@reference_case"
import ..ReferenceModule: var"@reference"
import ..OperationModule: ReplaceSelectionOperation
import ..PrimitiveModule: ReplaceStringRangeOperation
import ..ProjectionTemplateModule: var"@projection_template", bound, collection
import ..SerializationModule: FileDocument, ReferenceStub, format_marker_text, format_file_marker_text, get_filename
export MarkdownInsertionToSyntaxLeaf, MarkdownTextToSyntaxLeaf, MarkdownCodeToSyntaxLeaf,
       MarkdownThematicBreakToSyntaxLeaf, MarkdownEmphasisToSyntaxNode, MarkdownStrongToSyntaxNode,
       MarkdownParagraphToSyntaxNode, MarkdownHeadingToSyntaxNode, MarkdownQuoteToSyntaxNode,
       MarkdownListToSyntaxNode, MarkdownListItemToSyntaxNode, MarkdownRootToSyntaxNode,
       MarkdownLinkToSyntaxNode, MarkdownImageToSyntaxNode, MarkdownCodeBlockToSyntaxNode,
       MarkdownStyledTextToSyntaxLeaf, MarkdownStyledInline, MarkdownStrongToStyledNode,
       MarkdownEmphasisToStyledNode, MarkdownHeadingToStyledNode, MarkdownLinkToStyledNode,
       MarkdownImageToStyledNode, MarkdownListToStyledNode,
       ReferenceStubToMarkdownSyntaxLeaf, EmbeddedFileDocumentToMarkdownSyntaxLeaf,
       MarkdownToSyntax
import ..NaturalModule: register_natural_syntax!
import ..CellModule: Cell, ComputedCell, AbstractCell
import ..DocumentModule: @document
import ..NaturalModule: register_natural_domain!, print_natural_text
import ..SerializationModule: FileDocument, emit_text, populate_file!, get_file_content,
                            parse_marker_text, ReferenceStub, LoaderContext,
                            register_file_document_type!, get_document_section,
                            is_file_document
export MarkdownFile, PRED_REF_LANGUAGE, get_markdown_section
import ..CellModule: Cell, ComputedCell
import ..CollectionModule: CellVector
import ..LayoutModule: VerticalLayout
import ..ProjectionApiModule: print_document, map_reference_forward, map_reference_backward,
                              read_intent, Projection
import ..IoMapModule: SimpleIoMap
import ..WidgetModule: InvokeActionOperation
import ..ReferenceModule: ConcreteReference, FieldReferenceStep, RangeReferenceStep,
                          EmptyReference, is_element_reference_step
export MarkdownRootToVerticalLayout
import ..ProjectionAlgebraModule: ChainingProjection
import ..LayoutModule: VerticalLayoutToGraphicsCanvas
import ..NaturalModule: register_natural_graphics!
export MarkdownRoot, MarkdownHeading, MarkdownParagraph, MarkdownCodeBlock, MarkdownThematicBreak, MarkdownQuote, MarkdownList, MarkdownListItem, MarkdownText, MarkdownCode, MarkdownEmphasis, MarkdownStrong, MarkdownLink, MarkdownImage, MarkdownInsertion



abstract type MarkdownDocument <: Document end

# ── Insertion cursor ────────────────────────────────────────────────────────

"""
A placeholder for a Markdown node being entered (the insert-by-typing cursor);
type-to-replace swaps it for concrete content.
"""
@document struct MarkdownInsertion <: MarkdownDocument
    value::Any = nothing
end

# ── Inline nodes ──────────────────────────────────────────────────────────────

"""
A run of plain inline text. Supports `[]` / `[]=` on the content.
"""
@document struct MarkdownText <: MarkdownDocument
    content::String
end

Base.getindex(t::MarkdownText) = t.content::String
Base.setindex!(t::MarkdownText, v::AbstractString) = (t.content = String(v))
set_cell_function!(t::MarkdownText, f::Function) = (set_cell_function!(getfield(t, :content), f); t)
set_cell_value!(t::MarkdownText, v::AbstractString) = (set_cell_value!(getfield(t, :content), String(v)); t)

"""
An inline code span (`` `code` ``). Supports `[]` / `[]=` on the content.
"""
@document struct MarkdownCode <: MarkdownDocument
    content::String
end

Base.getindex(c::MarkdownCode) = c.content::String
Base.setindex!(c::MarkdownCode, v::AbstractString) = (c.content = String(v))
set_cell_function!(c::MarkdownCode, f::Function) = (set_cell_function!(getfield(c, :content), f); c)
set_cell_value!(c::MarkdownCode, v::AbstractString) = (set_cell_value!(getfield(c, :content), String(v)); c)

"""
Emphasised (italic) inline content (`*…*`), a sequence of inline nodes.
"""
@document struct MarkdownEmphasis <: MarkdownDocument
    content::CellVector = CellVector()
end

@forward_vector_protocol on MarkdownEmphasis to content

"""
Strong (bold) inline content (`**…**`), a sequence of inline nodes.
"""
@document struct MarkdownStrong <: MarkdownDocument
    content::CellVector = CellVector()
end

@forward_vector_protocol on MarkdownStrong to content

"""
An inline link (`[content](url)`). `content` is the inline text shown, `url` the
target.
"""
@document struct MarkdownLink <: MarkdownDocument
    content::CellVector = CellVector()
    url::String
end

@forward_vector_protocol on MarkdownLink to content

"""
An inline image (`![alt](url)`). `alt` is the alternative text, `url` the source.
"""
@document struct MarkdownImage <: MarkdownDocument
    alt::String
    url::String
end

# ── Block nodes ───────────────────────────────────────────────────────────────

"""
A heading (`#`…`######`). `level` is 1–6 and `content` is a sequence of inline
nodes.
"""
@document struct MarkdownHeading <: MarkdownDocument
    level::Int
    content::CellVector = CellVector()
end

@forward_vector_protocol on MarkdownHeading to content

"""
A prose paragraph — a sequence of inline nodes.
"""
@document struct MarkdownParagraph <: MarkdownDocument
    content::CellVector = CellVector()
end

@forward_vector_protocol on MarkdownParagraph to content

"""
A fenced code block (```` ``` ````). `language` is the info string (may be `""`)
and `code` the verbatim body. `collapsed` hides the body behind a marker in the
projection.
"""
@document struct MarkdownCodeBlock <: MarkdownDocument
    language::String
    code::String
    collapsed::Bool = false
end

"""
A thematic break — a horizontal rule (`---`).
"""
@document struct MarkdownThematicBreak <: MarkdownDocument
end

"""
A block quote (`> …`). `elements` holds its child blocks; `collapsed` hides them
behind a marker in the projection.
"""
@document struct MarkdownQuote <: MarkdownDocument
    elements::CellVector = CellVector()
    collapsed::Bool = false
end

@forward_vector_protocol on MarkdownQuote to elements

"""
One item of a `MarkdownList`. `elements` holds its child blocks (a list item may
itself contain paragraphs, nested lists, …); `collapsed` hides them in the
projection.
"""
@document struct MarkdownListItem <: MarkdownDocument
    elements::CellVector = CellVector()
    collapsed::Bool = false
end

@forward_vector_protocol on MarkdownListItem to elements

"""
A list. `ordered` selects between a numbered (`1.`) and a bulleted (`-`) list;
`items` holds its `MarkdownListItem`s. `collapsed` hides them in the projection.
`ordered` is a required leading argument so `items` reaches the `CellVector`-
wrapping constructor: `MarkdownList(true, [MarkdownListItem(…), …])`.
"""
@document struct MarkdownList <: MarkdownDocument
    ordered::Bool
    items::CellVector = CellVector()
    collapsed::Bool = false
end

@forward_vector_protocol on MarkdownList to items

# ── Root ──────────────────────────────────────────────────────────────────────

"""
The whole Markdown document — a top-level sequence of block nodes. `collapsed`
hides the body behind a marker in the projection.
"""
@document struct MarkdownRoot <: MarkdownDocument
    elements::CellVector = CellVector()
    collapsed::Bool = false
end

@forward_vector_protocol on MarkdownRoot to elements

# Text-replace edits need no per-type method: the type-in target fields —
# `MarkdownText.content`, `MarkdownCode.content`, `MarkdownHeading.level` (a
# number reparsed from its text), `MarkdownCodeBlock.language`/`code`,
# `MarkdownLink.url`, and `MarkdownImage.alt`/`url` — are all plain strings (or a
# reparsed number), handled by the generic splice.


include("MarkdownParser.jl")
include("MarkdownToSyntax.jl")
include("MarkdownFile.jl")
include("MarkdownToLayout.jl")


# What this slice registers when it loads: the file extensions it owns, and
# the natural notation it reads and writes.
function __init__()
    register_natural_syntax!(:markdown, () -> Pair{Type,Any}[MarkdownDocument => MarkdownToSyntax(style = :rendered)])

    register_file_document_type!(".md",       MarkdownFile)
    register_file_document_type!(".markdown", MarkdownFile)
    # What this domain's natural notation is: the syntax rung, the format, and
    # how to read it back. The `:graphics` rung — a page of blocks — is
    # the call below it, because a domain may reach more than one rung and
    # markdown reaches two.
    register_natural_domain!(MarkdownDocument;
                             rung      = :syntax,
                             make      = () -> MarkdownToSyntax(),
                             format    = :md,
                             extension = ".md",
                             parse     = parse_markdown)

    register_natural_graphics!(:markdown_page, (; measure) -> Pair{Type,Any}[
        MarkdownRoot => ChainingProjection(MarkdownRootToVerticalLayout(),
                                           VerticalLayoutToGraphicsCanvas()),
    ])
end

end # module
