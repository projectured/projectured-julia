# Fragment of `DataFramesModule`.
#
# The expression filter of a view: a Julia expression over the columns of the
# frame, such as `:age > 30 && startswith(:city, "B")`, where `:name` is the
# value of the column `name` in a row. The text is parsed once and compiled into
# one function over the vectors of the columns that it names, which loops over
# the rows, so a frame of ten million rows costs one call. It compiles in `Main`,
# so the expression can call a function of the session. A row passes when the
# expression is `true`; `missing` hides it, and any other value is an error. A
# text that does not parse, or that raises an error, keeps every row, and its
# reason marks the bar.

# The compiled functions by the text and the columns that it names, because the
# view computes its rows again when any filter changes.
const _EXPRESSION_FUNCTIONS = Dict{Tuple{String,Vector{String}},Any}()
const _EXPRESSION_FUNCTIONS_LOCK = ReentrantLock()

# The result of an expression for one row: `true` passes, `false` and `missing`
# do not, and any other value is an error.
_is_expression_true(value::Bool) = value
_is_expression_true(::Missing) = false
_is_expression_true(value) =
    throw(ArgumentError("the expression gives a " * string(typeof(value)) * ", not true or false"))

# `expression` with each `:name` that names a column in `columns` replaced by the
# element `row` of a vector of that column; `used` collects the columns in the
# order of their vectors, and `vectors` the names of the vectors.
function _rewrite_column_references(expression, columns::Set{String}, used::Vector{String},
                                    vectors::Vector{Symbol}, row::Symbol)
    if expression isa QuoteNode && expression.value isa Symbol && String(expression.value) in columns
        name = String(expression.value)
        k = findfirst(==(name), used)
        if k === nothing
            push!(used, name)
            push!(vectors, gensym("column"))
            k = length(used)
        end
        return Expr(:ref, vectors[k], row)
    end
    expression isa Expr || return expression
    Expr(expression.head, (_rewrite_column_references(argument, columns, used, vectors, row)
                           for argument in expression.args)...)
end

# The compiled function of `text` over the columns of a frame named `columns`,
# and the columns that it reads, in the order of its arguments after the vector
# of the rows that pass; a `String`, the reason, for a text that does not parse.
function _compile_expression(text::AbstractString, columns::Vector{String})
    parsed = Meta.parse(String(text); raise = false)
    parsed isa Expr && parsed.head in (:error, :incomplete) &&
        return "the expression does not parse: " * string(first(parsed.args))
    used, vectors = String[], Symbol[]
    row, pass, value = gensym("row"), gensym("pass"), gensym("value")
    body = _rewrite_column_references(parsed, Set(columns), used, vectors, row)
    lock(_EXPRESSION_FUNCTIONS_LOCK) do
        get!(_EXPRESSION_FUNCTIONS, (String(text), used)) do
            check = GlobalRef(@__MODULE__, :_is_expression_true)
            loop = quote
                for $row in eachindex($pass)
                    $value = $body
                    $pass[$row] = $check($value)
                end
                $pass
            end
            Core.eval(Main, Expr(:->, Expr(:tuple, pass, vectors...), loop))
        end => used
    end
end

# The rows of `frame` that the expression `text` passes, as a `BitVector`, and
# `nothing`; or `nothing` and the reason when the text does not parse or raises
# an error; `(nothing, nothing)` for an empty text.
function _evaluate_expression(frame, text::AbstractString)
    isempty(strip(text)) && return (nothing, nothing)
    compiled = _compile_expression(text, names(frame))
    compiled isa String && return (nothing, compiled)
    f, used = compiled
    try
        pass = Base.invokelatest(f, trues(nrow(frame)), (frame[!, name] for name in used)...)
        (pass, nothing)
    catch exception
        (nothing, "the expression raises an error: " * first(split(sprint(showerror, exception), '\n')))
    end
end
