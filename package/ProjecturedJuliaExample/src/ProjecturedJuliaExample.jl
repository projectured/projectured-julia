"""
    ProjecturedJuliaExample

The Julia tier of the example-package DAG: the document and projection
factories this domain's examples are built from.

The registry that names them (`examples`, `atomic_documents`) and the gallery
that runs them live in the `ProjecturedExample` umbrella, which is where a
cross-domain composition belongs.

The factories were written against the flat `Projectured` namespace, so the
loop below rebuilds that namespace over this package's sources.
"""
module ProjecturedJuliaExample

import ProjecturedJulia
import ProjecturedKernel
import ProjecturedPdf
import ProjecturedConsole
import ProjecturedNatural
import ProjecturedFileFormat
import ProjecturedGestureLog
import ProjecturedGestureHelp
import ProjecturedInspector
import ProjecturedTooltip
import ProjecturedClipboard
import ProjecturedPane
import ProjecturedSyntax
import ProjecturedWidget
import ProjecturedText
import ProjecturedLayout
import ProjecturedScreen
import ProjecturedGraphics
import ProjecturedPlot
import ProjecturedVersioning
import ProjecturedFocus
import ProjecturedDragging
import ProjecturedReflection
import ProjecturedProjection
import ProjecturedComponent
import ProjecturedStyle
import ProjecturedSerialization
import ProjecturedDomain
import ProjecturedPrimitive
import ProjecturedCollection
using ProjecturedKernelExample
using ProjecturedSubstrateExample
import ProjecturedKernelExample: Example, AtomicDocument, make_typein_gestures

const _SOURCES = (ProjecturedClipboard, ProjecturedCollection, ProjecturedComponent, ProjecturedConsole, ProjecturedDomain, ProjecturedDragging, ProjecturedFileFormat, ProjecturedFocus, ProjecturedGestureHelp, ProjecturedGestureLog, ProjecturedGraphics, ProjecturedInspector, ProjecturedJulia, ProjecturedKernel, ProjecturedLayout, ProjecturedNatural, ProjecturedPane, ProjecturedPdf, ProjecturedPlot, ProjecturedPrimitive, ProjecturedProjection, ProjecturedReflection, ProjecturedScreen, ProjecturedSerialization, ProjecturedStyle, ProjecturedSyntax, ProjecturedText, ProjecturedTooltip, ProjecturedVersioning, ProjecturedWidget)

for _src in _SOURCES
    _srcname = nameof(_src)
    for _n in names(_src; all = true)
        isdefined(_src, _n) || continue
        _m = getfield(_src, _n)
        # Every submodule of a Projectured package this source binds: the ones it
        # defines, and the ones it re-aliases from a package below it.
        (_m isa Module && _m !== _src && parentmodule(_m) !== Main) || continue
        Core.eval(@__MODULE__, Expr(:const, Expr(:(=), _n, _m)))
        _syms = [s for s in names(_m) if s !== nameof(_m) && isdefined(_m, s)]
        isempty(_syms) && continue
        Core.eval(@__MODULE__, Expr(:using, Expr(:(:),
            Expr(:., _srcname, _n), (Expr(:., s) for s in _syms)...)))
    end
end

include("../../../example/julia/JuliaDocumentExample.jl")
include("../../../example/julia/JuliaProjectionExample.jl")

export make_julia_bool_document_example, make_julia_break_document_example, make_julia_char_document_example
export make_julia_continue_document_example, make_julia_float_document_example, make_julia_identifier_document_example
export make_julia_integer_document_example, make_julia_string_document_example, make_julia_symbol_document_example
export make_julia_nothing_document_example, make_julia_insertion_document_example, make_julia_binary_op_document_example
export make_julia_call_document_example, make_julia_assignment_document_example, make_julia_block_document_example
export make_julia_function_document_example, make_julia_array_document_example, make_julia_begin_document_example
export make_julia_field_access_document_example, make_julia_for_iterator_document_example, make_julia_for_document_example
export make_julia_if_document_example, make_julia_index_document_example, make_julia_lambda_document_example
export make_julia_range_document_example, make_julia_return_document_example, make_julia_ternary_document_example
export make_julia_try_document_example, make_julia_tuple_document_example, make_julia_type_annotation_document_example
export make_julia_unary_op_document_example, make_julia_using_document_example, make_julia_while_document_example
export make_julia_abstract_type_document_example, make_julia_anonymous_type_annotation_document_example, make_julia_broadcast_document_example
export make_julia_comprehension_document_example, make_julia_const_document_example, make_julia_curly_document_example
export make_julia_do_document_example, make_julia_docstring_document_example, make_julia_empty_document_example
export make_julia_function_declaration_document_example, make_julia_interpolation_document_example, make_julia_let_document_example
export make_julia_macro_call_document_example, make_julia_module_def_document_example, make_julia_named_tuple_document_example
export make_julia_splat_document_example, make_julia_string_chunk_document_example, make_julia_string_interpolation_document_example
export make_julia_struct_document_example, make_julia_subtype_document_example, make_julia_where_document_example
export make_julia_where_parameters_document_example, make_julia_document_example, make_julia_projection_example

end # module ProjecturedJuliaExample
