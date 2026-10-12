# Fragment of `JuliaModule` — a Julia document as the `Expr` Julia runs.

"""
    make_julia_expression(document) -> Expr

The code of a Julia document as an `Expr(:toplevel, …)`, the shape
`Meta.parseall` gives, ready for `Core.eval` statement by statement.

A `JuliaObject` — an object a person pasted into the code, such as a widget —
becomes its value itself, in a `QuoteNode`, so the evaluation uses that very
object and never a copy of it. A document that is not Julia at all is such an
object alone. A hole of the Julia domain stands for the code typed
into it, and a hole whose text does not parse raises an error.

The document is printed in the Julia notation with a placeholder name where
each object stands, the text is parsed, and each placeholder is replaced by its
object.

# Example

    make_julia_expression(parse_julia("x = 1 + 2"))   # :(x = 1 + 2) in a :toplevel
"""
function make_julia_expression(document)
    document isa JuliaDocument || return Expr(:toplevel, QuoteNode(document))
    policy = JuliaExpressionCopyPolicy()
    shadow = copy_document(policy, document)
    expression = Meta.parseall(print_natural_text(shadow))
    _put_objects(expression, policy.objects)
end

# The walk that makes the shadow: it copies the Julia nodes, and where it meets
# a `JuliaObject` it keeps the value in `objects` and puts a placeholder
# identifier in its place.
struct JuliaExpressionCopyPolicy <: CopyPolicy
    objects::Dict{Symbol,Any}
end
JuliaExpressionCopyPolicy() = JuliaExpressionCopyPolicy(Dict{Symbol,Any}())

# A list of Julia nodes, such as the arguments of a call, is a collection and
# not an object.
DocumentModule.is_descendable_for_copy(::JuliaExpressionCopyPolicy, document) =
    !(document isa Document) || document isa JuliaDocument && !(document isa JuliaObject) ||
    is_element_collection(document)

DocumentModule.make_copy_placeholder(policy::JuliaExpressionCopyPolicy, object::JuliaObject) =
    _make_object_placeholder(policy, object.value)

# A document that is not Julia stands in the code bare only where the check of the
# declared type does not convert a write, in the modes `:record` and `:off`.
DocumentModule.make_copy_placeholder(policy::JuliaExpressionCopyPolicy, document) =
    _make_object_placeholder(policy, document)

function _make_object_placeholder(policy::JuliaExpressionCopyPolicy, object)
    name = Symbol("__projectured_object_", length(policy.objects) + 1)
    policy.objects[name] = object
    JuliaIdentifier(String(name))
end

# A hole prints its text with the completion it offers, so the shadow holds the
# code that was typed into it instead.
function DocumentModule.copy_document(::JuliaExpressionCopyPolicy, hole::JuliaInsertion)
    text = something(hole.value, "")
    try
        parse_julia(text)
    catch
        error("make_julia_expression: a hole holds code that does not parse: ", repr(text))
    end
end

_put_objects(value, objects) = value
_put_objects(symbol::Symbol, objects) =
    haskey(objects, symbol) ? QuoteNode(objects[symbol]) : symbol
_put_objects(expression::Expr, objects) =
    Expr(expression.head, Any[_put_objects(argument, objects) for argument in expression.args]...)
