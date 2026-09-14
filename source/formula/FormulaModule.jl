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

# Imported to extend: this module adds a method to each of these.
import ..ProjectionModule: print_document, map_reference_forward, map_reference_backward

export FormulaDocument, make_formula_result_text, wire_result!, resolve, get_column_letter, get_cell_name,
       get_formula_references, get_formula_dependencies, would_create_cycle, compute_topological_order,
       convert_formula_to_expr, evaluate_formula
export FormulaInsertionToSyntaxLeaf, FormulaReferenceToSyntaxLeaf,
       FormulaFormulaToSyntaxNode, FormulaEnvironmentToSyntaxNode, FormulaToSyntax
export FormulaInsertion, FormulaReference


include("FormulaDocument.jl")
include("FormulaToSyntax.jl")

end # module
