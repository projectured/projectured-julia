"""
    FormulaModule

The Formula domain — named, cross-referencing, evaluated formulas whose code
is a Julia expression (the spreadsheet idea generalised). Each formula's
`result` is a reactive `Cell` evaluating the Julia body against a named
environment; other formulas cite each other by identity.
"""
module FormulaModule

using ..CellModule
using ..CollectionModule
using ..DocumentModule
using ..IoMapModule
using ..JuliaModule
using ..ProjectionAlgebraModule
using ..ProjectionModule
using ..ReferenceModule
using ..StyleModule
using ..SyntaxModule
using ..TextModule
using ..NaturalModule
using ..SerializationModule
using ..MathModule
using ..PrimitiveModule
import ..SerializationModule: pred_arguments, make_pred_document

# Imported to extend: this module adds a method to each of these.
import ..ProjectionModule: print_document, map_reference_forward, map_reference_backward

export FormulaDocument, make_formula_result_text, wire_result!, resolve, get_column_letter, get_cell_name,
       get_formula_references, get_formula_dependencies, get_formula_names, would_create_cycle,
       compute_topological_order, convert_formula_to_expr, evaluate_formula, get_formula_value,
       convert_math_to_julia, MathReadingException
export FormulaInsertionToSyntaxLeaf, FormulaReferenceToSyntaxLeaf,
       FormulaFormulaToSyntaxNode, FormulaEnvironmentToSyntaxNode, FormulaToSyntax
export FormulaInsertion, FormulaReference


include("MathToJulia.jl")
include("FormulaDocument.jl")
include("FormulaToSyntax.jl")

# A file may name a formula and a sheet. The registry is runtime state, so the
# offer is made here and not at the top level.
function __init__()
    register_pred_type!(FormulaFormula)
    register_pred_type!(FormulaEnvironment)
end

end # module
