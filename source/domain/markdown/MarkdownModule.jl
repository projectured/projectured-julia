"""
    MarkdownModule

Markdown documents: headings, paragraphs, code blocks, quotes and lists, with text,
code, emphasis, links and images inside them. They hold blocks (headings,
paragraphs, code blocks, quotes, lists) and inlines (text, code, emphasis, strong,
link, image).
"""
module MarkdownModule

using ..KernelModule
using ..PlatformModule

# Imported to extend: this module adds a method to each of these.
import ..CellModule: set_cell_computation!, set_cell_value!
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward,
                           get_projection_gesture_bindings
import ..NavigatorModule: find_navigator_target
import ..LinkModule: is_link, get_link_target, get_link_content
import ..SerializationModule: get_document_section, make_reference_leaf, find_reference_marker,
                              splice_named_file!, make_document_seed,
                              get_file_format_extensions, get_file_format_domain,
                              parse_document_string
import ..NaturalModule: make_syntax_projection, find_natural_file_format
import ..DisplayModule: make_workload_file
import ..DocumentModule: get_view_state_fields
import ..DomainModule: acquire_document!, release_document!

export MarkdownDocument, set_cell_computation!
export parse_markdown, parse_markdown_file, compute_markdown_heading_slug
export MarkdownTheme, ScaledMarkdownTheme
export MarkdownInsertionToSyntaxLeaf, MarkdownTextToSyntaxLeaf, MarkdownCodeToSyntaxLeaf,
       MarkdownThematicBreakToSyntaxLeaf, MarkdownEmphasisToSyntaxNode, MarkdownStrongToSyntaxNode,
       MarkdownParagraphToSyntaxNode, MarkdownHeadingToSyntaxNode, MarkdownQuoteToSyntaxNode,
       MarkdownListToSyntaxNode, MarkdownListItemToSyntaxNode, MarkdownRootToSyntaxNode,
       MarkdownTableToSyntaxNode, MarkdownTableRowToSyntaxNode,
       MarkdownLinkToSyntaxNode, MarkdownImageToSyntaxNode, MarkdownCodeBlockToSyntaxNode,
       MarkdownStyledTextToSyntaxLeaf, MarkdownStyledInline, MarkdownStrongToStyledNode,
       MarkdownEmphasisToStyledNode, MarkdownHeadingToStyledNode, MarkdownLinkToStyledNode,
       MarkdownImageToStyledNode, MarkdownListToStyledNode,
       MarkdownToSyntax
export PRED_REF_LANGUAGE, MarkdownFileFormat, MarkdownFile, get_markdown_section
export MarkdownRootToVerticalLayout
export MarkdownView, MarkdownTextView, MarkdownParagraphView, MarkdownHeadingView, MarkdownRootView
export MarkdownRoot, MarkdownHeading, MarkdownParagraph, MarkdownCodeBlock, MarkdownThematicBreak, MarkdownQuote, MarkdownList, MarkdownListItem, MarkdownTable, MarkdownTableRow, MarkdownText, MarkdownCode, MarkdownEmphasis, MarkdownStrong, MarkdownLink, MarkdownImage, MarkdownInsertion


include("MarkdownDocument.jl")
include("MarkdownParser.jl")
include("MarkdownTheme.jl")
include("MarkdownToSyntax.jl")
include("MarkdownFile.jl")
include("MarkdownLinkTarget.jl")
include("MarkdownToLayout.jl")
include("MarkdownView.jl")


# What this slice registers when it loads: the rows that draw a page in a tab.
function __init__()
    register_natural_syntax!(:markdown, (; appearance) -> Pair{Type,Any}[
        MarkdownDocument => MarkdownToSyntax(style = :rendered,
                                             theme = get_scaled_theme!(appearance, MarkdownTheme))])

    # A page is a stack of blocks, and a block of prose breaks its lines at the
    # width the page offers. The four prose blocks say so; a code block and a
    # thematic break do not, and fall to the fabric, which never breaks a line.
    register_natural_graphics!(:markdown_page, (; measure, appearance) -> Pair{Type,Any}[
        MarkdownRoot => ChainingProjection(MarkdownRootToVerticalLayout(
                                               gap = get_markdown_style(get_scaled_theme!(appearance, MarkdownTheme), :block_gap)),
                                           VerticalLayoutToGraphicsCanvas()),
        MarkdownHeading   => make_natural_prose_graphics(; measure, appearance),
        MarkdownParagraph => make_natural_prose_graphics(; measure, appearance),
        MarkdownQuote     => make_natural_prose_graphics(; measure, appearance),
        MarkdownList      => make_natural_prose_graphics(; measure, appearance),
    ])
end

# The file that a workload of the window opens (`run_file_workload`).
make_workload_file(::Type{MarkdownFile}) =
    (; name = "a.md", text = "# Title\n\nAlice writes a text.\n", shown = r"Alice")

end # module
