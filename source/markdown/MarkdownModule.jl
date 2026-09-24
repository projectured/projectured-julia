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
import ..CellModule: set_cell_computation!, set_cell_value!
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward
import ..SerializationModule: emit_text, get_document_section,
                              get_file_domain, make_reference_leaf, find_reference_marker, parse_file_content

export MarkdownDocument, set_cell_computation!
export parse_markdown, parse_markdown_file
export MarkdownInsertionToSyntaxLeaf, MarkdownTextToSyntaxLeaf, MarkdownCodeToSyntaxLeaf,
       MarkdownThematicBreakToSyntaxLeaf, MarkdownEmphasisToSyntaxNode, MarkdownStrongToSyntaxNode,
       MarkdownParagraphToSyntaxNode, MarkdownHeadingToSyntaxNode, MarkdownQuoteToSyntaxNode,
       MarkdownListToSyntaxNode, MarkdownListItemToSyntaxNode, MarkdownRootToSyntaxNode,
       MarkdownLinkToSyntaxNode, MarkdownImageToSyntaxNode, MarkdownCodeBlockToSyntaxNode,
       MarkdownStyledTextToSyntaxLeaf, MarkdownStyledInline, MarkdownStrongToStyledNode,
       MarkdownEmphasisToStyledNode, MarkdownHeadingToStyledNode, MarkdownLinkToStyledNode,
       MarkdownImageToStyledNode, MarkdownListToStyledNode,
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

    # A page is a stack of blocks, and a block of prose breaks its lines at the
    # width the page offers. The four prose blocks say so; a code block and a
    # thematic break do not, and fall to the fabric, which never breaks a line.
    register_natural_graphics!(:markdown_page, (; measure) -> Pair{Type,Any}[
        MarkdownRoot => ChainingProjection(MarkdownRootToVerticalLayout(),
                                           VerticalLayoutToGraphicsCanvas()),
        MarkdownHeading   => make_natural_prose_graphics(; measure),
        MarkdownParagraph => make_natural_prose_graphics(; measure),
        MarkdownQuote     => make_natural_prose_graphics(; measure),
        MarkdownList      => make_natural_prose_graphics(; measure),
    ])
end

end # module
