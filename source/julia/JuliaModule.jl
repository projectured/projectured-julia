"""
    JuliaModule

The Julia document domain — a Julia AST as reactive `Document`s. Leaves
(identifiers, literals), expressions (binary/call/index/…), and statements
(assign/for/if/function/block).
"""
module JuliaModule

using ..CellModule
using ..CollectionModule
using ..DocumentModule
using ..DomainModule
using ..EventModule
using ..GestureBindingModule
using ..IoMapModule
using ..NaturalModule
using ..OperationModule
using ..ProjectionAlgebraModule
using ..ProjectionModule
using ..ReferenceModule
using ..SelectionModule
using ..SerializationModule
using ..StyleModule
using ..SyntaxModule
using ..TextModule
using ..ReferenceModule   # `@document` injects the implicit `selection::Union{Nothing, Reference}` field

# Imported to extend: this module adds a method to each of these.
import ..FileFormatModule: make_document_seed
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward
import ..SerializationModule: emit_text, populate_file!

export _julia_operator_string
export parse_julia, parse_julia_file
export JuliaInsertionToSyntaxLeaf, get_julia_completion, make_julia_scaffold
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
       JuliaUsingToSyntaxNode, JuliaLambdaToSyntaxNode, JuliaModuleDefinitionToSyntaxNode,
       JuliaSplatToSyntaxNode, JuliaBroadcastToSyntaxNode,
       JuliaStringInterpolationToSyntaxNode, JuliaWhereToSyntaxNode,
       JuliaComprehensionToSyntaxNode, JuliaDoToSyntaxNode, JuliaLetToSyntaxNode,
       JuliaNamedTupleToSyntaxNode,
       JuliaStringChunkToSyntaxLeaf, JuliaInterpolationToSyntaxNode,
       JuliaFunctionDeclarationToSyntaxNode, JuliaWhereParametersToSyntaxNode,
       ReferenceStubToJuliaSyntaxLeaf, EmbeddedFileDocumentToJuliaSyntaxLeaf,
       JuliaToSyntax
export JuliaIdentifier, JuliaInteger, JuliaFloat, JuliaString, JuliaBool, JuliaNothing, JuliaSymbol, JuliaChar, JuliaBinaryOperation, JuliaUnaryOperation, JuliaCall, JuliaMacroCall, JuliaConst, JuliaDocstring, JuliaAbstractType, JuliaStruct, JuliaSubtype, JuliaCurly, JuliaAnonymousTypeAnnotation, JuliaEmpty, JuliaTernary, JuliaIndex, JuliaFieldAccess, JuliaTuple, JuliaArray, JuliaRange, JuliaTypeAnnotation, JuliaAssignment, JuliaFor, JuliaForIterator, JuliaWhile, JuliaReturn, JuliaBreak, JuliaContinue, JuliaTry, JuliaBegin, JuliaIf, JuliaFunction, JuliaBlock, JuliaUsing, JuliaLambda, JuliaModuleDefinition, JuliaDocument, JuliaSplat, JuliaBroadcast, JuliaStringInterpolation, JuliaWhere, JuliaComprehension, JuliaDo, JuliaLet, JuliaNamedTuple, JuliaStringChunk, JuliaInterpolation, JuliaFunctionDeclaration, JuliaWhereParameters, JuliaInsertion


include("JuliaDocument.jl")
include("JuliaParser.jl")
include("JuliaInsertionToSyntax.jl")
include("JuliaFile.jl")
include("JuliaToSyntax.jl")


# What this slice registers when it loads: the file extensions it owns, and
# the natural notation it reads and writes.
function __init__()
    register_file_document_type!(".jl", JuliaFile)
    register_marker_function!(:definition,
                              (ctx, document, name) -> find_julia_definition(document, name))

    register_natural_domain!(JuliaDocument;
                             rung      = :syntax,
                             make      = () -> JuliaToSyntax(),
                             format    = :jl,
                             extension = ".jl",
                             parse     = parse_julia)
end

end # module
