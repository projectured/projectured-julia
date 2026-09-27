"""
    MathModule

The math document domain: formulas as `Document`s.
`X = (3*A + B)/2` becomes
`MathAssignment(MathVariable("X"), MathBinaryOperation(:/, …))`.

The domain holds the *structure* of a formula, not its picture and not its
value. Two projections read it: `MathToSyntax` prints one line of text (the
save path), and `MathToGraphics` places real two-dimensional boxes.

A slot that can be absent holds `nothing` when it is absent and a
`MathInsertion` when it is present and empty. Both projections keep that rule:
`nothing` prints nothing, an insertion prints a placeholder.
"""
module MathModule

using ..CellModule
using ..CollectionModule
using ..DocumentModule
using ..EventModule
using ..EventModule
using ..GestureModule
using ..GraphicsModule
using ..IoMapModule
using ..NaturalModule
using ..OperationModule
using ..PrimitiveModule
using ..ProjectionAlgebraModule
using ..ProjectionModule
using ..SerializationModule
import ..SerializationModule: get_file_domain, is_file_domain_node, parse_file_content, emit_text
using ..ReferenceModule
using ..StyleModule
using ..SyntaxModule
using ..TextModule

# Imported to extend: this module adds a method to each of these.
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward

export MathDocument, _operator_string, get_math_operator_glyph, get_math_operator_class,
       get_math_symbol_glyph, get_math_big_operator_glyph, get_math_big_operator_name,
       is_math_big_operator_text,
       get_math_delimiter_strings, is_math_accent_wide, MathSubscript, MathSuperscript
export MathInsertionToSyntaxLeaf, MathVariableToSyntaxLeaf,
       MathBinaryOperationToSyntaxNode, MathParenthesizedToSyntaxNode,
       MathAssignmentToSyntaxNode, MathToSyntax,
       MathSymbolToSyntaxLeaf, MathTextToSyntaxLeaf, MathSpaceToSyntaxLeaf,
       MathRowToSyntaxNode, MathUnaryOperationToSyntaxNode,
       MathFractionToSyntaxNode, MathScriptToSyntaxNode, MathRadicalToSyntaxNode,
       MathBigOperatorToSyntaxNode, MathDifferentialToSyntaxNode,
       MathDerivativeToSyntaxNode, MathFunctionToSyntaxNode,
       MathAccentToSyntaxNode, MathMatrixToSyntaxNode,
       MathCaseToSyntaxNode, MathCasesToSyntaxNode
export MathIoMap, MathConfig, MathMetrics, compute_math_metrics, MathToGraphics,
       make_math_to_graphics_dispatch,
       MathVariableToGraphics, MathSymbolToGraphics, MathTextToGraphics,
       MathSpaceToGraphics, MathInsertionToGraphics, MathNumberToGraphics,
       MathRowToGraphics, MathBinaryOperationToGraphics,
       MathUnaryOperationToGraphics, MathAssignmentToGraphics,
       MathParenthesizedToGraphics, MathFractionToGraphics, MathScriptToGraphics,
       MathRadicalToGraphics, MathBigOperatorToGraphics,
       MathDifferentialToGraphics, MathDerivativeToGraphics,
       MathFunctionToGraphics, MathAccentToGraphics, MathMatrixToGraphics,
       MathCaseToGraphics, MathCasesToGraphics
export MathInsertion, MathVariable, MathBinaryOperation, MathParenthesized, MathAssignment, MathSymbol, MathText
export parse_math, MathFile


include("MathDocument.jl")
include("MathParser.jl")
include("MathToSyntax.jl")
include("MathToGraphics.jl")
include("MathFile.jl")

end # module
