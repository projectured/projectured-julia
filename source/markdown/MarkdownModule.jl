"""
    MarkdownModule

The Markdown document domain — blocks (headings, paragraphs, code blocks,
quotes, lists) and inlines (text, code, emphasis, strong, link, image).
"""
module MarkdownModule

using ..BackendModule
using ..CellModule
using ..CollectionModule
using ..DocumentModule
using ..GraphicsModule
using ..IoMapModule
using ..LayoutModule
using ..NaturalModule
using ..OperationModule
using ..PrimitiveModule
using ..ProjectionAlgebraModule
using ..ProjectionModule
using ..ReferenceModule
using ..SerializationModule
using ..StyleModule
using ..SyntaxModule
using ..TextModule
using ..WidgetModule

# Imported to extend: this module adds a method to each of these.
import ..CellModule: set_cell_function!, set_cell_value!
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward
import ..SerializationModule: emit_text, populate_file!, get_document_section

export MarkdownDocument, set_cell_function!
export parse_markdown, parse_markdown_file
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
export MarkdownFile, PRED_REF_LANGUAGE, get_markdown_section
export MarkdownRootToVerticalLayout
export MarkdownRoot, MarkdownHeading, MarkdownParagraph, MarkdownCodeBlock, MarkdownThematicBreak, MarkdownQuote, MarkdownList, MarkdownListItem, MarkdownText, MarkdownCode, MarkdownEmphasis, MarkdownStrong, MarkdownLink, MarkdownImage, MarkdownInsertion


include("MarkdownDocument.jl")
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
