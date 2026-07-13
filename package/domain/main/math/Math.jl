"""
    MathModule

The math document domain: arithmetic formulas as `Document`s.
`X = (3*A + B)/2` becomes
`MathAssignment(MathVariable("X"), MathBinaryOperation(:/, …))`.
"""
module MathModule

import ..CellModule: Cell
import ..DocumentApiModule: Document
import ..DocumentModule: @document
import ..ReferenceModule: Reference
export MathDocument, _operator_string

abstract type MathDocument <: Document end

"""
A placeholder for a math value being entered (the insert-by-typing cursor).
"""
@document struct MathInsertion <: MathDocument
    value::Any = nothing
end

"""
A named variable (e.g. `X`, `A`).
"""
@document struct MathVariable <: MathDocument
    name::String
end

"""
A binary arithmetic operation; `operator` is one of `:+`, `:-`, `:*`, `:/`.
"""
@document struct MathBinaryOperation <: MathDocument
    operator::Symbol
    left::Document
    right::Document
end

"""
Explicit parenthesized grouping around a sub-expression.
"""
@document struct MathParenthesized <: MathDocument
    content::Document
end

"""
An assignment expression `target = value`.
"""
@document struct MathAssignment <: MathDocument
    target::Document
    value::Document
end

function _operator_string(op::Symbol)
    op === :+ && return "+"
    op === :- && return "-"
    op === :* && return "*"
    op === :/ && return "/"
    return string(op)
end

end # module
