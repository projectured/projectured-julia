# Fragment of `DataFramesModule`.
#
# The expression filter of a view: a Julia expression over the columns of the
# frame, such as `age > 30 && startswith(city, "B")`, where the name of a column
# is its value in a row. A name that is no identifier is written as Julia writes
# one, `var"unit price"`, and `:age` is the column too, as DataFramesMeta.jl
# writes it. Inside the expression a column wins over a global of the same name,
# which `Main.name` reaches. The text is parsed once and compiled into
# one function over the vectors of the columns that it names, which loops over
# the rows, so a frame of ten million rows costs one call. It compiles in `Main`,
# so the expression can call a function of the session. A row passes when the
# expression is `true`; `missing` hides it, and any other value is an error. A
# text that does not parse, or that raises an error, keeps every row, and its
# reason marks the bar. An expression that assigns to a column, such as
# `age = 30` for `age == 30`, does not compile, because it would write the value
# into the frame.

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

# `expression` with each name of a column in `columns`, bare or as a symbol,
# replaced by the element `row` of a vector of that column. A name that Julia
# uses for something else stays: the function of a call or of a broadcast, the
# field after a dot, the name of a keyword argument and of a macro. `used`
# collects the columns in the order of their vectors, and `vectors` the names of
# the vectors.
function _rewrite_column_references(expression, columns::Set{String}, used::Vector{String},
                                    vectors::Vector{Symbol}, row::Symbol)
    name = _get_column_name(expression, columns)
    name === nothing || return _make_column_element(name, used, vectors, row)
    expression isa Expr || return expression
    rewrite(argument) = _rewrite_column_references(argument, columns, used, vectors, row)
    head, arguments = expression.head, expression.args
    if head === :call
        rewritten = (_rewrite_call_argument(argument, rewrite) for argument in arguments[2:end])
        return Expr(head, arguments[1], rewritten...)
    elseif head === :. && length(arguments) == 2
        # `object.field` keeps its field, and `f.(x)` its function.
        field = arguments[2]
        field isa QuoteNode && return Expr(head, rewrite(arguments[1]), field)
        return Expr(head, arguments[1], rewrite(field))
    elseif head === :macrocall
        return Expr(head, arguments[1:2]..., (rewrite(argument) for argument in arguments[3:end])...)
    end
    Expr(head, (rewrite(argument) for argument in arguments)...)
end

# The name of the column of `columns` that `expression` names, bare or as a
# symbol, or `nothing`.
function _get_column_name(expression, columns::Set{String})
    name = expression isa Symbol ? String(expression) :
           (expression isa QuoteNode && expression.value isa Symbol) ? String(expression.value) : nothing
    (name !== nothing && name in columns) ? name : nothing
end

# The column of `columns` that `expression` assigns to, with `=`, an update such
# as `+=`, or in a tuple on the left of one; `nothing` when there is none.
function _find_assigned_column(expression, columns::Set{String})
    expression isa Expr || return nothing
    if endswith(String(expression.head), "=")
        target = expression.args[1]
        targets = (target isa Expr && target.head === :tuple) ? target.args : Any[target]
        for target in targets
            name = _get_column_name(target, columns)
            name === nothing || return name
        end
    end
    for argument in expression.args
        name = _find_assigned_column(argument, columns)
        name === nothing || return name
    end
    nothing
end

# An argument of a call: a keyword argument keeps its name.
function _rewrite_call_argument(argument, rewrite)
    argument isa Expr || return rewrite(argument)
    argument.head === :kw && return Expr(:kw, argument.args[1], rewrite(argument.args[2]))
    argument.head === :parameters &&
        return Expr(:parameters, (_rewrite_call_argument(inner, rewrite) for inner in argument.args)...)
    rewrite(argument)
end

# The element `row` of the vector of column `name`, which gets a vector of its
# own the first time that it is named.
function _make_column_element(name::String, used::Vector{String}, vectors::Vector{Symbol}, row::Symbol)
    k = findfirst(==(name), used)
    if k === nothing
        push!(used, name)
        push!(vectors, gensym("column"))
        k = length(used)
    end
    Expr(:ref, vectors[k], row)
end

# The compiled function of `text` over the columns of a frame named `columns`,
# and the columns that it reads, in the order of its arguments after the vector
# of the rows that pass; a `String`, the reason, for a text that does not parse.
function _compile_expression(text::AbstractString, columns::Vector{String})
    parsed = Meta.parse(String(text); raise = false)
    parsed isa Expr && parsed.head in (:error, :incomplete) &&
        return "the expression does not parse: " * string(first(parsed.args))
    assigned = _find_assigned_column(parsed, Set(columns))
    assigned === nothing ||
        return "the expression assigns to the column " * assigned * "; write == to compare"
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

# The name of column `name` in an expression: the name itself when it is an
# identifier that parses as itself, which a keyword such as `end` does not, else
# `var"name"`.
function _get_expression_name(name)
    name = String(name)::String
    (Base.isidentifier(name) && Meta.parse(name; raise = false) === Symbol(name)) ? name : "var" * repr(name)
end

# The first value of `column` that is not `missing`, among its first rows, or
# `nothing`.
function _get_example_value(column::AbstractVector)
    for value in Iterators.take(column, 100)
        ismissing(value) || return value
    end
    nothing
end

# An example of an expression over the columns of `frame`, which the empty field
# of the expression shows: a comparison of its first column of numbers with a
# value of that column, and a test of the first letter of its first column of
# strings; `nothing` for a frame that has neither.
function _make_expression_example(frame)
    columns = names(frame)::Vector{String}
    get_type(name) = nonmissingtype(eltype(frame[!, name]))
    clauses = String[]
    number = findfirst(name -> _is_number_type(get_type(name)), columns)
    if number !== nothing
        value = _get_example_value(frame[!, columns[number]])
        push!(clauses, _get_expression_name(columns[number]) * " > " * (value === nothing ? "0" : string(value)))
    end
    text = findfirst(name -> get_type(name) <: AbstractString, columns)
    if text !== nothing
        value = _get_example_value(frame[!, columns[text]])
        letter = (value === nothing || isempty(value)) ? "A" : string(first(value))
        push!(clauses, "startswith(" * _get_expression_name(columns[text]) * ", " * repr(letter) * ")")
    end
    isempty(clauses) ? nothing : join(clauses, " && ")
end
