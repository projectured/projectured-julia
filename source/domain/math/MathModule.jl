"""
    MathModule

Math documents: formulas as trees of assignments, variables, numbers and operations.
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

using ..KernelModule
using ..PlatformModule
import ..SerializationModule: is_file_domain_node, make_document_seed, get_file_format_extensions,
                              get_file_format_domain, parse_document_string
import ..NaturalModule: make_syntax_projection, find_natural_file_format
using ..KernelModule
using ..PlatformModule

# Imported to extend: this module adds a method to each of these.
import ..ProjectionModule: print_document, read_intent, map_operation_backward, map_reference_forward,
                           map_reference_backward
import ..GestureBindingModule: read_gesture
import ..GraphicsModule: find_first_baseline
import ..DisplayModule: make_workload_file

export MathDocument, _operator_string, get_math_operator_glyph, get_math_operator_class,
       get_math_symbol_glyph, find_math_symbol_name, get_math_big_operator_glyph, get_math_big_operator_name,
       is_math_big_operator_text,
       get_math_delimiter_strings, is_math_accent_wide, MathSubscript, MathSuperscript
export MathTheme, ScaledMathTheme
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
export parse_math, MathFileFormat, MathFile


include("MathDocument.jl")
include("MathParser.jl")
include("MathTheme.jl")
include("MathToSyntax.jl")
include("MathToGraphics.jl")
include("MathFile.jl")

# The file that a workload of the window opens (`run_file_workload`).
make_workload_file(::Type{MathFile}) = (; name = "a.math", text = "a + b", shown = "b")

end # module
