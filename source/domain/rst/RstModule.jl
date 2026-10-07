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

**Directives are typed where it pays.** The eleven directives that carry
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

using ..KernelModule
using ..PlatformModule

# Imported to extend: this module adds a method to each of these.
import ..CellModule: set_cell_computation!, set_cell_value!
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward,
                           get_projection_gesture_bindings
import ..NavigatorModule: find_navigator_target
import ..SerializationModule: emit_text, get_document_section,
                              get_file_domain, make_reference_leaf, find_reference_marker, parse_file_content

export RstDocument, set_cell_computation!
export parse_rst, parse_rst_file
export RstTheme, ScaledRstTheme
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
export RstFile, find_rst_section, get_rst_title_text, PRED_REF_DIRECTIVE
export RstRootToVerticalLayout, RstSectionToVerticalLayout
export RstRoot, RstSection, RstParagraph, RstText, RstLiteral, RstEmphasis, RstStrong, RstRole, RstReference, RstSubstitutionReference, RstFootnoteReference, RstLiteralBlock, RstLineBlock, RstListItem, RstBulletList, RstEnumeratedList, RstDefinitionItem, RstDefinitionList, RstField, RstFieldList, RstBlockQuote, RstTransition, RstComment, RstTarget, RstSubstitutionDefinition, RstFootnote, RstTableCell, RstTableRow, RstGridTable, RstDirectiveOption, RstLiteralInclude, RstFigure, RstCodeBlock, RstImage, RstVideo, RstAudio, RstAdmonition, RstToctree, RstMathBlock, RstRawBlock, RstRoleDefinition, RstDirective, RstInsertion


include("RstDocument.jl")
include("RstParser.jl")
include("RstTheme.jl")
include("RstToSyntax.jl")
include("RstFile.jl")
include("RstLinkTarget.jl")
include("RstToLayout.jl")


# What this slice registers when it loads: the file extensions it owns, and
# the natural notation it reads and writes.
function __init__()
    register_natural_syntax!(:rst, (; appearance) -> Pair{Type,Any}[
        RstDocument => RstToSyntax(style = :rendered,
                                   theme = get_scaled_theme!(appearance, RstTheme))])

    register_file_document_type!(".rst", RstFile)
    # What this domain's natural notation is: the syntax rung, the format, and
    # how to read it back. The `:graphics` rung — a page of blocks — is
    # the call below it.
    register_natural_domain!(RstDocument;
                             rung      = :syntax,
                             make      = (; appearance) -> RstToSyntax(
                                 theme = get_scaled_theme!(appearance, RstTheme)),
                             format    = :rst,
                             extension = ".rst",
                             parse     = parse_rst)

    register_natural_graphics!(:rst_page, (; measure, appearance) -> begin
        theme = get_scaled_theme!(appearance, RstTheme)
        get_style(name) = get_rst_style(theme, name)
        title_styles = (title_1_font = get_style(:title_1_font), title_2_font = get_style(:title_2_font),
                        title_3_font = get_style(:title_3_font), title_font = get_style(:title_font),
                        title_color = get_style(:title_color))
        Pair{Type,Any}[
            RstRoot    => ChainingProjection(RstRootToVerticalLayout(; gap = get_style(:block_gap)),
                                             VerticalLayoutToGraphicsCanvas()),
            RstSection => ChainingProjection(RstSectionToVerticalLayout(; gap = get_style(:block_gap),
                                                                        title_styles...),
                                             VerticalLayoutToGraphicsCanvas()),
        ]
    end)
end

end # module
