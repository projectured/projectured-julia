# Fragment of `FormulaModule` — a math tree read as a Julia expression.
#
# The math domain is notation: it holds an integral and a set operator as
# readily as a fraction, and it evaluates nothing. A formula evaluates a Julia
# tree. This is the reading between the two, one rule per node type, and a
# refusal by name for every node that has no value.

"""
    MathReadingException(message)

Thrown when a math tree has no Julia reading: an integral, a derivative, a set
operator, a matrix, an accent. The message names the node.
"""
struct MathReadingException <: Exception
    message::String
end

Base.showerror(io::IO, e::MathReadingException) = print(io, e.message)

_refuse_reading(what::AbstractString) =
    throw(MathReadingException(what * " has no value here"))

"""
    convert_math_to_julia(tree::MathDocument) -> JuliaDocument

The Julia expression a math tree stands for. A variable, a symbol and a word
are identifiers; a subscript on a name is part of the name, `p_{block}` is
`p_block`; a superscript is a power; a fraction is a division; a row is a
product; a radical is `sqrt` or a fractional power; a function is a call,
`log_{2}(x)` is `log(2, x)`; a sum or a product with limits is `sum(k -> body,
a:b)`; a case list is a chain of `ifelse`; an assignment answers its value
side. Every other node throws a [`MathReadingException`](@ref).
"""
convert_math_to_julia(tree::MathDocument) = _julia_of(tree)

_julia_of(node::MathVariable) = JuliaIdentifier(_name_of(node.name, "the variable"))
_julia_of(node::MathSymbol) = JuliaIdentifier(_symbol_name(node.name))
_julia_of(node::MathText) = JuliaIdentifier(_name_of(node.content, "the text"))
_julia_of(node::PrimitiveNumber) = _julia_number(node.value)
_julia_of(node::MathParenthesized) = _julia_of(node.content)
_julia_of(node::MathAssignment) = _julia_of(node.value)
_julia_of(node::MathFraction) =
    JuliaBinaryOperation(:/, _julia_of(node.numerator), _julia_of(node.denominator))

function _julia_of(node::MathRow)
    elements = collect(node.elements)
    isempty(elements) && _refuse_reading("an empty row")
    product = _julia_of(first(elements))
    for element in elements[2:end]
        product = JuliaBinaryOperation(:*, product, _julia_of(element))
    end
    product
end

# The Julia operator a math operator reads as. A relation reads as the
# comparison; the operators of sets and of approximation have no reading.
const _JULIA_OPERATORS = Dict{Symbol,Symbol}(
    :+ => :+, :- => :-, :* => :*, :/ => :/, :times => :*, :cdot => :*, :divide => :/,
    :(=) => :(==), :ne => :(!=), :lt => :<, :gt => :>, :le => :<=, :ge => :>=,
)

function _julia_of(node::MathBinaryOperation)
    operator = get(_JULIA_OPERATORS, node.operator, nothing)
    operator === nothing && _refuse_reading("the operator " * get_math_operator_glyph(node.operator))
    JuliaBinaryOperation(operator, _julia_of(node.left), _julia_of(node.right))
end

function _julia_of(node::MathUnaryOperation)
    operator = node.operator
    operator === :- && return JuliaUnaryOperation(:-, _julia_of(node.operand))
    operator === :not && return JuliaUnaryOperation(:!, _julia_of(node.operand))
    operator === :factorial &&
        return JuliaCall(JuliaIdentifier("factorial"), Any[_julia_of(node.operand)])
    _refuse_reading("the operator " * get_math_operator_glyph(operator))
end

function _julia_of(node::MathScript)
    base = node.base
    subscript = node.subscript
    superscript = node.superscript
    if subscript !== nothing
        name = _subscripted_name(base, subscript)
        base = JuliaIdentifier(name)
    else
        base = _julia_of(base)
    end
    superscript === nothing && return base
    JuliaBinaryOperation(:^, base, _julia_of(superscript))
end

function _julia_of(node::MathRadical)
    radicand = _julia_of(node.radicand)
    index = node.index
    index === nothing && return JuliaCall(JuliaIdentifier("sqrt"), Any[radicand])
    JuliaBinaryOperation(:^, radicand, JuliaBinaryOperation(:/, JuliaInteger(1), _julia_of(index)))
end

function _julia_of(node::MathFunction)
    argument = _julia_of(node.argument)
    base = node.base
    base === nothing && return JuliaCall(JuliaIdentifier(_name_of(node.name, "the function")), Any[argument])
    node.name == "log" && return JuliaCall(JuliaIdentifier("log"), Any[_julia_of(base), argument])
    _refuse_reading("the function " * node.name * " with a base")
end

function _julia_of(node::MathBigOperator)
    operator = node.operator
    operator in (:sum, :prod) || _refuse_reading("the operator " * get_math_big_operator_name(operator))
    lower = node.lower
    upper = node.upper
    (lower === nothing || upper === nothing) &&
        _refuse_reading("a " * String(operator) * " without limits")
    (variable, start) = _bound_variable(lower)
    body = JuliaLambda(Any[JuliaIdentifier(variable)], _julia_of(node.body))
    range = JuliaRange(start, nothing, _julia_of(upper))
    JuliaCall(JuliaIdentifier(String(operator)), Any[body, range])
end

# The lower limit of a sum: `k = 0`, as an assignment or as a relation.
function _bound_variable(lower)
    if lower isa MathAssignment
        return (_name_of_node(lower.target), _julia_of(lower.value))
    elseif lower isa MathBinaryOperation && lower.operator === :(=)
        return (_name_of_node(lower.left), _julia_of(lower.right))
    end
    _refuse_reading("a sum whose lower limit names no start, like k = 0,")
end

function _julia_of(node::MathCases)
    cases = collect(node.cases)
    isempty(cases) && _refuse_reading("an empty case list")
    otherwise = nothing
    conditioned = Any[]
    for case in cases
        case.condition === nothing ? (otherwise = _julia_of(case.value)) :
                                     push!(conditioned, case)
    end
    otherwise === nothing && _refuse_reading("a case list without an otherwise")
    result = otherwise
    for case in reverse(conditioned)
        result = JuliaCall(JuliaIdentifier("ifelse"),
                           Any[_julia_of(case.condition), _julia_of(case.value), result])
    end
    result
end

_julia_of(::MathDifferential) = _refuse_reading("a differential")
_julia_of(::MathDerivative) = _refuse_reading("a derivative")
_julia_of(::MathAccent) = _refuse_reading("an accent")
_julia_of(::MathMatrix) = _refuse_reading("a matrix")
_julia_of(::MathSpace) = _refuse_reading("a space")
_julia_of(::MathInsertion) = _refuse_reading("an empty slot")
_julia_of(::MathCase) = _refuse_reading("a case outside a case list")
_julia_of(node) = _refuse_reading("a " * String(nameof(typeof(node))))

# ── Names ────────────────────────────────────────────────────────────────────

_julia_number(value::Integer) = JuliaInteger(Int(value))
_julia_number(value::Real) = isinteger(value) ? JuliaInteger(Int(value)) : JuliaFloat(Float64(value))
_julia_number(value) = _refuse_reading("the number " * repr(value))

# The identifier a name is, or a refusal: `bit/s` is a unit and not a name.
function _name_of(text::AbstractString, what::AbstractString)
    Base.isidentifier(String(text)) && return String(text)
    _refuse_reading(what * " " * repr(text) * ", which is not a name,")
end

# A symbol reads as its name: `ρ` is `rho`. Infinity is Julia's.
_symbol_name(name::Symbol) = name === :infty ? "Inf" : _name_of(String(name), "the symbol")

# The name a node is, for a subscript or a bound variable.
_name_of_node(node::MathVariable) = _name_of(node.name, "the variable")
_name_of_node(node::MathSymbol) = _symbol_name(node.name)
_name_of_node(node::MathText) = _name_of(node.content, "the text")
_name_of_node(node::PrimitiveNumber) = string(node.value)
_name_of_node(node) = _refuse_reading("a " * String(nameof(typeof(node))) * " as a name")

# `p_{block}` is one name, `p_block`; `x_{i}` is `x_i`.
_subscripted_name(base, subscript) = _name_of_node(base) * "_" * _name_of_node(subscript)
