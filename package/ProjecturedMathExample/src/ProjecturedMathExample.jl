"""
    ProjecturedMathExample

The Math tier of the example-package DAG: the document and projection
factories this domain's examples are built from.

The registry that names them (`examples`, `atomic_documents`) and the gallery
that runs them live in the `ProjecturedExample` umbrella, which is where a
cross-domain composition belongs.

The factories were written against the flat `Projectured` namespace, so the
loop below rebuilds that namespace over this package's sources.
"""
module ProjecturedMathExample

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
import ProjecturedMath
using ProjecturedKernelExample
using ProjecturedSubstrateExample
import ProjecturedKernelExample: Example, AtomicDocument, make_typein_gestures

const _SOURCES = (ProjecturedClipboard, ProjecturedCollection, ProjecturedComponent, ProjecturedConsole, ProjecturedDomain, ProjecturedDragging, ProjecturedFileFormat, ProjecturedFocus, ProjecturedGestureHelp, ProjecturedGestureLog, ProjecturedGraphics, ProjecturedInspector, ProjecturedKernel, ProjecturedLayout, ProjecturedMath, ProjecturedNatural, ProjecturedPane, ProjecturedPdf, ProjecturedPlot, ProjecturedPrimitive, ProjecturedProjection, ProjecturedReflection, ProjecturedScreen, ProjecturedSerialization, ProjecturedStyle, ProjecturedSyntax, ProjecturedText, ProjecturedTooltip, ProjecturedVersioning, ProjecturedWidget)

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

include("../../../example/math/MathDocumentExample.jl")
include("../../../example/math/MathProjectionExample.jl")

export make_math_variable_document_example, make_math_insertion_document_example, make_math_symbol_document_example
export make_math_text_document_example, make_math_space_document_example, make_math_binary_operation_document_example
export make_math_assignment_document_example, make_math_parenthesized_document_example, make_math_row_document_example
export make_math_unary_operation_document_example, make_math_fraction_document_example, make_math_script_document_example
export make_math_radical_document_example, make_math_big_operator_document_example, make_math_differential_document_example
export make_math_derivative_document_example, make_math_function_document_example, make_math_accent_document_example
export make_math_matrix_document_example, make_math_case_document_example, make_math_cases_document_example
export make_math_document_example, make_math_shannon_document_example, make_math_friis_document_example
export make_math_queue_document_example, make_math_erlang_document_example, make_math_delay_document_example
export make_math_error_rate_document_example, make_math_reliability_document_example, make_math_noise_document_example
export make_math_regime_document_example, make_math_display_document_example, make_math_projection_example
export make_math_display_projection_example

end # module ProjecturedMathExample
