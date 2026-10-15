"""
    FormulaModule

The Formula domain — named, cross-referencing, evaluated formulas whose code
is a Julia expression (the spreadsheet idea generalised). Each formula stores the
value that its code last computed, which the formula task of the editor computes
off the loop; a formula refers to another by its name.
"""
module FormulaModule

using ..JuliaModule
using ..KernelModule
using ..MathModule
using ..PlatformModule
import ..SerializationModule: pred_arguments, make_pred_document

# Imported to extend: this module adds a method to each of these.
import ..ProjectionModule: print_document, read_intent, map_reference_forward,
                           map_reference_backward
import ..OperationModule: evaluate_operation, make_inverse_operation, describe_operation,
                          is_self_contained_operation
import ..DomainModule: acquire_document!

export FormulaDocument, FormulaError, wire_result!, resolve, get_column_letter, get_cell_name,
       get_formula_dependencies, get_formula_names, would_create_cycle, compute_topological_order,
       convert_formula_to_expr, evaluate_formula, get_formula_value, get_formula_result,
       convert_math_to_julia, MathReadingException, get_formula_key, is_math_code
export compute_formula_key, ComputeFormulasOperation, ReplaceFormulaResultOperation
export BeginFormulaEditOperation, CancelFormulaEditOperation, CommitFormulaOperation
export FormulaTheme, ScaledFormulaTheme
export FormulaInsertionToSyntaxLeaf, FormulaIdentifierToSyntaxLeaf, FormulaFormulaToSyntaxNode,
       FormulaEnvironmentToSyntaxNode, FormulaToSyntax
export FormulaInsertion
export FormulaFormulaToLayout, FormulaEnvironmentToLayout, make_formula_graphics_entry
export FormulaEnvironmentToTable


include("MathToJulia.jl")
include("FormulaDocument.jl")
include("FormulaComputation.jl")
include("FormulaEdit.jl")
include("FormulaTheme.jl")
include("FormulaToSyntax.jl")
include("FormulaToGraphics.jl")
include("FormulaToTable.jl")

# The row that lets the natural renderer draw a formula. The registry is
# runtime state, so the row is added here and not at the top level.
function __init__()
    register_natural_graphics!(:formula, make_formula_graphics_entry)
end

end # module
