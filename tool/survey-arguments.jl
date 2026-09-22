# How many positional arguments each definition of the code takes, and which
# definitions break the rule of three (see documentation/rule/code-quality-rules.md,
# "Arguments: three positional, then names").
#
#     julia tool/survey-arguments.jl               # source and example
#     julia tool/survey-arguments.jl source/pane   # one folder
#
# It reads the syntax tree that Julia's own parser builds, so it tells a
# definition from a call and a keyword argument from a positional one. It counts
# every definition, also a private helper and one inside another definition.
#
# A definition over the line is excused by the marker `# @positional: <reason>`
# on the line above it, and by the protocol list below. The report names every
# public definition over the line that has neither.

const DEFAULT_ROOTS = ["source", "example"]
const LIMIT = 3          # positional arguments a definition may take

# The generic functions of a protocol: every method takes the arity of the
# contract, so the rule of three is not the question there.
const PROTOCOL = Set(Symbol[
    :print_document, :print_document_pure, :print_child, :print_child_pure,
    :read_intent, :map_reference_forward, :map_reference_backward, :read_gesture,
    :evaluate_operation, :reroot_operation, :retarget_operation, :operation_reference,
    :match_reference_step, :match_reference_step_value, :solve_constraint_layout,
    :splice_value!, :copy_document, :copy_shadow_element, :get_frozen_extent,
    # Methods of Base and of the standard library.
    :getproperty, :setproperty!, :getindex, :setindex!, :iterate, :length, :show,
    :hash, :isequal, :print, :size, :handle_message, :shouldlog,
])

struct Definition
    file::String
    line::Int
    name::String
    required::Int          # a positional argument with no default
    optional::Int          # a positional argument with a default
    keywords::Int
    types::Vector{String}  # the declared type of each positional, "" for none
    excused::Bool          # the `# @positional:` marker stands above it
end

get_positional_count(definition::Definition) = definition.required + definition.optional
is_protocol(definition::Definition) = Symbol(definition.name) in PROTOCOL
is_private(definition::Definition) = startswith(definition.name, "_")
get_slice(definition::Definition) = join(splitpath(definition.file)[1:min(2, end)], "/")
is_over_limit(definition::Definition) =
    get_positional_count(definition) > LIMIT && !is_protocol(definition) && !definition.excused

_get_name(x::Symbol) = String(x)
_get_name(x::QuoteNode) = _get_name(x.value)
_get_name(x::Expr) = x.head === :. ? _get_name(x.args[2]) :
                     x.head === :curly ? _get_name(x.args[1]) :
                     x.head === :quote ? _get_name(x.args[1]) :
                     x.head === :(::) ? "(callable)" : "(other)"
_get_name(::Any) = "(other)"

# The declared type of one positional argument, "" when it declares none.
function _get_type(x)
    x isa Expr || return ""
    x.head === :(::) && return string(x.args[end])
    x.head === :kw && return _get_type(x.args[1])
    x.head === :... && return _get_type(x.args[1])
    ""
end

_strip_where(signature) =
    signature isa Expr && signature.head === :where ? _strip_where(signature.args[1]) : signature

function _make_definition(signature, file, line, markers)
    signature = _strip_where(signature)
    (signature isa Expr && signature.head === :call) || return nothing
    required = optional = keywords = 0
    types = String[]
    for argument in signature.args[2:end]
        if argument isa Expr && argument.head === :parameters
            keywords += length(argument.args)
            continue
        end
        argument isa Expr && argument.head === :kw ? (optional += 1) : (required += 1)
        push!(types, _get_type(argument))
    end
    Definition(file, line, _get_name(signature.args[1]), required, optional, keywords,
               types, line in markers)
end

_is_definition(expression::Expr) =
    expression.head === :function ||
    (expression.head === :(=) && length(expression.args) == 2 &&
     _strip_where(expression.args[1]) isa Expr && _strip_where(expression.args[1]).head === :call)

function _collect_definitions!(found, expression, file, line, markers)
    expression isa Expr || return line
    if _is_definition(expression)
        definition = _make_definition(expression.args[1], file, line, markers)
        definition === nothing || push!(found, definition)
        expression = expression.args[end]
        expression isa Expr || return line
    end
    for argument in expression.args
        argument isa LineNumberNode && (line = argument.line; continue)
        line = _collect_definitions!(found, argument, file, line, markers)
    end
    line
end

# The lines that a `# @positional:` marker excuses: the first line under each
# marker that is not a comment and not blank.
function _find_marker_lines(text::AbstractString)
    lines = split(text, '\n')
    marked = Set{Int}()
    for (number, line) in enumerate(lines)
        occursin(r"^\s*#\s*@positional:", line) || continue
        for next in (number + 1):length(lines)
            stripped = strip(lines[next])
            (isempty(stripped) || startswith(stripped, "#")) && continue
            push!(marked, next)
            break
        end
    end
    marked
end

function survey_definitions(roots)
    found = Definition[]
    for root in roots, (directory, _, files) in walkdir(root), file in files
        endswith(file, ".jl") || continue
        path = joinpath(directory, file)
        text = read(path, String)
        parsed = try
            Meta.parseall(text; filename = path)
        catch error
            println("the parser refused ", path, ": ", error)
            continue
        end
        _collect_definitions!(found, parsed, path, 0, _find_marker_lines(text))
    end
    found
end

function report(found)
    println("definitions: ", length(found), " in ", length(unique(d.file for d in found)), " files")
    println("\npositional arguments, count of definitions:")
    for k in 0:8
        n = k == 8 ? count(d -> get_positional_count(d) >= 8, found) :
                     count(d -> get_positional_count(d) == k, found)
        println("  ", k == 8 ? ">= 8" : string(k), "  ", n)
    end
    println("\ndefinitions taking a keyword argument: ", count(d -> d.keywords > 0, found))
    wide = [d for d in found if get_positional_count(d) > LIMIT]
    println("over the limit of $LIMIT: ", length(wide),
            " (protocol ", count(is_protocol, wide),
            ", excused by a marker ", count(d -> d.excused, wide), ")")
    over = [d for d in found if is_over_limit(d)]
    public = [d for d in over if !is_private(d)]
    println("to answer for: ", length(over), " (public ", length(public),
            ", private ", length(over) - length(public), ")")
    println("\nby slice, the public ones:")
    counts = Dict(slice => count(d -> get_slice(d) == slice, public) for slice in unique(get_slice.(public)))
    for (slice, n) in sort(collect(counts); by = last, rev = true)
        println("  ", rpad(slice, 26), n)
    end
    println("\nthe public ones, widest first:")
    for d in sort(public; by = get_positional_count, rev = true)
        println("  ", rpad(string(d.required) * "+" * string(d.optional) * "+" * string(d.keywords), 9),
                rpad(d.name, 34), rpad(d.file * ":" * string(d.line), 54),
                join([isempty(t) ? "?" : t for t in d.types], " "))
    end
end

report(survey_definitions(isempty(ARGS) ? DEFAULT_ROOTS : ARGS))
