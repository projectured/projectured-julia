"""
    JuliaModule

The Julia document domain — a Julia AST as reactive `Document`s. Leaves
(identifiers, literals), expressions (binary/call/index/…), and statements
(assign/for/if/function/block).
"""
module JuliaModule

using ..KernelModule
using ..PlatformModule
using ..ReferenceModule   # `@document` injects the implicit `selection::Union{Nothing, Reference}` field

# Imported to extend: this module adds a method to each of these.
import ..DocumentModule: has_document_duplicate
import ..GestureBindingModule: get_document_gesture_bindings_own
import ..FileFormatModule: make_document_seed
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward
import ..SerializationModule: emit_text,
                              get_file_domain, make_reference_leaf, find_reference_marker, parse_file_content
import ..WidgetModule: compute_code_pieces, make_graphics_projection

export _julia_operator_string
export parse_julia, parse_julia_file
export make_julia_expression, make_julia_file_code_projection
export compute_julia_signature
export JuliaTheme, ScaledJuliaTheme
export JuliaInsertionToSyntaxLeaf, get_julia_completion, make_julia_scaffold
export JuliaObjectToSyntaxLeaf
export JuliaFile, PRED_REF_FUNCTION_NAME, find_julia_definition, get_julia_definition_name
export JuliaIdentifierToSyntaxLeaf, JuliaIntegerToSyntaxLeaf,
       JuliaFloatToSyntaxLeaf, JuliaStringToSyntaxLeaf, JuliaBoolToSyntaxLeaf,
       JuliaNothingToSyntaxLeaf, JuliaSymbolToSyntaxLeaf, JuliaCharToSyntaxLeaf,
       JuliaBinaryOperationToSyntaxNode, JuliaUnaryOperationToSyntaxNode, JuliaCallToSyntaxNode,
       JuliaMacroCallToSyntaxNode, JuliaConstToSyntaxNode, JuliaDocstringToSyntaxNode,
       JuliaAbstractTypeToSyntaxNode, JuliaStructToSyntaxNode,
       JuliaSubtypeToSyntaxNode, JuliaCurlyToSyntaxNode,
       JuliaAnonymousTypeAnnotationToSyntaxNode, JuliaEmptyToSyntaxLeaf,
       JuliaTernaryToSyntaxNode, JuliaIndexToSyntaxNode, JuliaFieldAccessToSyntaxNode,
       JuliaTupleToSyntaxNode, JuliaArrayToSyntaxNode, JuliaRangeToSyntaxNode,
       JuliaTypeAnnotationToSyntaxNode,
       JuliaAssignmentToSyntaxNode, JuliaForToSyntaxNode, JuliaForIteratorToSyntaxNode,
       JuliaWhileToSyntaxNode, JuliaReturnToSyntaxNode,
       JuliaBreakToSyntaxLeaf, JuliaContinueToSyntaxLeaf,
       JuliaTryToSyntaxNode, JuliaBeginToSyntaxNode,
       JuliaIfToSyntaxNode, JuliaFunctionToSyntaxNode, JuliaBlockToSyntaxNode,
       JuliaToplevelToSyntaxNode,
       JuliaUsingToSyntaxNode, JuliaLambdaToSyntaxNode, JuliaModuleDefinitionToSyntaxNode,
       JuliaSplatToSyntaxNode, JuliaBroadcastToSyntaxNode,
       JuliaStringInterpolationToSyntaxNode, JuliaWhereToSyntaxNode,
       JuliaComprehensionToSyntaxNode, JuliaDoToSyntaxNode, JuliaLetToSyntaxNode,
       JuliaNamedTupleToSyntaxNode,
       JuliaStringChunkToSyntaxLeaf, JuliaInterpolationToSyntaxNode,
       JuliaFunctionDeclarationToSyntaxNode, JuliaWhereParametersToSyntaxNode,
       JuliaToSyntax
export JuliaIdentifier, JuliaInteger, JuliaFloat, JuliaString, JuliaBool, JuliaNothing, JuliaSymbol, JuliaChar, JuliaBinaryOperation, JuliaUnaryOperation, JuliaCall, JuliaMacroCall, JuliaConst, JuliaDocstring, JuliaAbstractType, JuliaStruct, JuliaSubtype, JuliaCurly, JuliaAnonymousTypeAnnotation, JuliaEmpty, JuliaTernary, JuliaIndex, JuliaFieldAccess, JuliaTuple, JuliaArray, JuliaRange, JuliaTypeAnnotation, JuliaAssignment, JuliaFor, JuliaForIterator, JuliaWhile, JuliaReturn, JuliaBreak, JuliaContinue, JuliaTry, JuliaBegin, JuliaIf, JuliaFunction, JuliaBlock, JuliaToplevel, JuliaUsing, JuliaLambda, JuliaModuleDefinition, JuliaDocument, JuliaSplat, JuliaBroadcast, JuliaStringInterpolation, JuliaWhere, JuliaComprehension, JuliaDo, JuliaLet, JuliaNamedTuple, JuliaStringChunk, JuliaInterpolation, JuliaFunctionDeclaration, JuliaWhereParameters, JuliaInsertion


include("JuliaDocument.jl")
include("JuliaParser.jl")
include("JuliaExpression.jl")
include("JuliaTheme.jl")
include("JuliaInsertionToSyntax.jl")
include("JuliaFile.jl")
include("JuliaToSyntax.jl")
include("JuliaCodePieces.jl")


# The code of a Julia file in its tab: its lines numbered and its nodes folded
# as text, with the numbers and the triangles in a gutter that the scroll pane of
# the tab keeps at its left edge. A Julia document inside another document draws
# as code with no gutter, by the row of `:julia_code`.
make_graphics_projection(::Type{JuliaFile}; measure, appearance) =
    FileToContent(; content = make_julia_file_code_projection(; measure, appearance))

"""
    make_julia_file_code_projection(; measure, appearance) -> Projection

The view of the code of a Julia file: `JuliaToSyntax`, `SyntaxToText` with text
folds, `TextLineNumbering`, `TextFolding` and `TextBlockToScrollLayout`, whose
`ScrollLayout` the scroll pane of a file tab takes apart. Its recursion prints the
marks of the gutter.
"""
function make_julia_file_code_projection(; measure, appearance)
    syntax_theme = get_scaled_theme!(appearance, SyntaxTheme)
    text_theme = get_scaled_theme!(appearance, TextTheme)
    line_spacing = make_style_field(TextTheme, text_theme, LineSpacing; name = :code_line_spacing)
    code = ChainingProjection(
        RecursiveProjection(JuliaToSyntax(; theme = get_scaled_theme!(appearance, JuliaTheme), syntax_theme)),
        RecursiveProjection(SyntaxToText(; theme = syntax_theme, text_folds = true)),
        TextLineNumbering(; theme = text_theme),
        TextFolding(; theme = text_theme),
        TextBlockToScrollLayout(; measure, theme = text_theme, line_spacing))
    RecursiveProjection(TypeDispatchingProjection(
        JuliaDocument => code,
        TextGutter => TextGutterToGraphics(),
        TextBlock => TextToGraphics(; measure, theme = text_theme),
        GraphicsCanvas => GraphicsToGraphics()))
end

# What this slice registers when it loads: the file extensions it owns, the
# natural notation it reads and writes, and how its code draws as a whole.
function __init__()
    register_file_document_type!(".jl", JuliaFile)
    register_marker_function!(:definition,
                              (ctx, document, name) -> find_julia_definition(document, name))

    register_natural_domain!(JuliaDocument;
                             rung      = :syntax,
                             make      = (; appearance) -> JuliaToSyntax(;
                                 theme = get_scaled_theme!(appearance, JuliaTheme),
                                 syntax_theme = get_scaled_theme!(appearance, SyntaxTheme)),
                             format    = :jl,
                             extension = ".jl",
                             parse     = parse_julia,
                             expression = make_julia_expression)

    # Julia code draws as a whole: a document that stands in the code, such as
    # an object that a person pasted into a form, stays one leaf of the code,
    # `⟨Table⟩`, and does not draw as itself in the middle of a line.
    register_natural_graphics!(:julia_code, (; measure, appearance) -> Pair{Type,Any}[
        JuliaDocument => ChainingProjection(
            RecursiveProjection(JuliaToSyntax(;
                theme = get_scaled_theme!(appearance, JuliaTheme),
                syntax_theme = get_scaled_theme!(appearance, SyntaxTheme))),
            RecursiveProjection(SyntaxToText(; theme = get_scaled_theme!(appearance, SyntaxTheme))),
            TextToGraphics(; measure, theme = get_scaled_theme!(appearance, TextTheme),
                           line_spacing = make_style_field(TextTheme, get_scaled_theme!(appearance, TextTheme),
                                                           LineSpacing; name = :code_line_spacing)))])
end

end # module
