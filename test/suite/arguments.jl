# ============================================================================
# The argument guard — the rule of three positional arguments, where a machine
# can read it.
#
# `documentation/rule/code-quality-rules.md` §4 says it: a function takes at
# most three positional arguments, and the fourth and every one after it takes a
# name. Four kinds of signature keep more — a method of a protocol, a
# conventional tuple, a port, and the painter family of a backend — and each one
# says so with a `# @positional: <reason>` marker above the definition.
#
# **It fails on every public definition over the line** that neither a marker
# nor the protocol list below excuses.
#
# **A private helper is out of scope for now**, by the owner's decision of
# 2026-09-22: a helper inside one file costs one reader one file, and a public
# function costs every call site.
#
# **Static, and deliberately.** It parses each file with the parser of Julia and
# loads nothing, so it runs in about a second and reads a definition rather than
# a line of text.
# ============================================================================

"The folders the rule covers: the code a person writes, and not the tests."
const ARGUMENT_ROOTS = ["source", "example"]

"How many positional arguments a definition may take."
const POSITIONAL_LIMIT = 3

# The generic functions of a protocol: every method takes the arity of the
# contract, so the rule is not about them. A method of Base is here as well.
const ARGUMENT_PROTOCOL = Set(String[
    "print_document", "print_document_pure", "print_child", "print_child_pure",
    "read_intent", "map_reference_forward", "map_reference_backward", "read_gesture",
    "evaluate_operation", "reroot_operation", "retarget_operation", "operation_reference",
    "match_reference_step", "match_reference_step_value", "solve_constraint_layout",
    "splice_value!", "copy_document", "copy_shadow_element", "get_frozen_extent",
    "getproperty", "setproperty!", "getindex", "setindex!", "iterate", "length",
    "show", "hash", "isequal", "print", "size", "handle_message", "shouldlog",
    "sync_document!", "layout_graph",
])

"One definition of a file: where it stands, what it is called, and what it takes."
struct ArgumentDefinition
    file::String
    line::Int
    name::String
    required::Int          # a positional argument with no default
    optional::Int          # a positional argument with a default
    keywords::Int
    types::Vector{String}  # the declared type of each positional, "" for none
    excused::Bool          # a `# @positional:` marker stands above it
end

get_positional_count(d::ArgumentDefinition) = d.required + d.optional
is_protocol_name(name::AbstractString) = name in ARGUMENT_PROTOCOL
is_private_name(name::AbstractString) = startswith(name, "_")
is_over_positional_limit(d::ArgumentDefinition) =
    get_positional_count(d) > POSITIONAL_LIMIT && !is_protocol_name(d.name) && !d.excused

_argument_name(x::Symbol) = String(x)
_argument_name(x::QuoteNode) = _argument_name(x.value)
_argument_name(x::Expr) = x.head === :. ? _argument_name(x.args[2]) :
                          x.head === :curly ? _argument_name(x.args[1]) :
                          x.head === :quote ? _argument_name(x.args[1]) :
                          x.head === :(::) ? "(callable)" : "(other)"
_argument_name(::Any) = "(other)"

"The declared type of one positional argument, empty when it declares none."
function _argument_type(x)
    x isa Expr || return ""
    x.head === :(::) && return string(x.args[end])
    x.head === :kw && return _argument_type(x.args[1])
    x.head === :... && return _argument_type(x.args[1])
    ""
end

_argument_signature(signature) =
    signature isa Expr && signature.head === :where ?
        _argument_signature(signature.args[1]) : signature

function _make_argument_definition(signature, file, line, markers)
    signature = _argument_signature(signature)
    (signature isa Expr && signature.head === :call) || return nothing
    required = optional = keywords = 0
    types = String[]
    for argument in signature.args[2:end]
        if argument isa Expr && argument.head === :parameters
            keywords += length(argument.args)
            continue
        end
        argument isa Expr && argument.head === :kw ? (optional += 1) : (required += 1)
        push!(types, _argument_type(argument))
    end
    ArgumentDefinition(file, line, _argument_name(signature.args[1]),
                       required, optional, keywords, types, line in markers)
end

_is_argument_definition(expression::Expr) =
    expression.head === :function ||
    (expression.head === :(=) && length(expression.args) == 2 &&
     _argument_signature(expression.args[1]) isa Expr &&
     _argument_signature(expression.args[1]).head === :call)

function _collect_argument_definitions!(found, expression, file, line, markers)
    expression isa Expr || return line
    if _is_argument_definition(expression)
        definition = _make_argument_definition(expression.args[1], file, line, markers)
        definition === nothing || push!(found, definition)
        expression = expression.args[end]
        expression isa Expr || return line
    end
    for argument in expression.args
        argument isa LineNumberNode && (line = argument.line; continue)
        line = _collect_argument_definitions!(found, argument, file, line, markers)
    end
    line
end

"""
The lines a `# @positional:` marker excuses: under each marker, the first line
that is neither blank nor a comment.
"""
function _find_positional_markers(text::AbstractString)
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

"""
    find_argument_definitions(root) -> Vector{ArgumentDefinition}

Every definition under the folders the rule covers, a private helper and a
definition inside another definition included.
"""
function find_argument_definitions(root::AbstractString)
    found = ArgumentDefinition[]
    for folder in ARGUMENT_ROOTS
        full = joinpath(root, folder)
        isdir(full) || continue
        for (here, _dirs, names) in walkdir(full), name in names
            endswith(name, ".jl") || continue
            path = relpath(joinpath(here, name), root)
            text = read(joinpath(root, path), String)
            parsed = try
                Meta.parseall(text; filename = path)
            catch
                continue          # the naming guard reports a file the parser refuses
            end
            _collect_argument_definitions!(found, parsed, path, 0,
                                           _find_positional_markers(text))
        end
    end
    sort!(found; by = d -> (d.file, d.line))
end

"""
    argument_violations(root) -> Vector{String}

A public definition over the line that neither a marker nor the protocol list
excuses.
"""
function argument_violations(root::AbstractString)
    found = find_argument_definitions(root)
    over = [d for d in found if is_over_positional_limit(d) && !is_private_name(d.name)]
    out = String[]
    for d in over
        push!(out, "$(d.file):$(d.line) $(d.name) takes $(get_positional_count(d)) " *
                   "positional arguments — name the fourth and the rest, or write " *
                   "`# @positional: <reason>` above it; see code-quality-rules.md §4")
    end
    out
end

"""
    argument_report(root) -> Nothing

What the rule looks like across the code: how many definitions take how many
positional arguments, and every public one over the line. It fails nothing.
"""
function argument_report(root::AbstractString)
    found = find_argument_definitions(root)
    println("definitions: ", length(found), " in ",
            length(unique(d.file for d in found)), " files")
    println("\npositional arguments, count of definitions:")
    for k in 0:8
        n = k == 8 ? count(d -> get_positional_count(d) >= 8, found) :
                     count(d -> get_positional_count(d) == k, found)
        println("  ", k == 8 ? ">= 8" : string(k), "  ", n)
    end
    println("\ndefinitions taking a keyword argument: ", count(d -> d.keywords > 0, found))
    wide = [d for d in found if get_positional_count(d) > POSITIONAL_LIMIT]
    println("over the limit of ", POSITIONAL_LIMIT, ": ", length(wide),
            " (protocol ", count(d -> is_protocol_name(d.name), wide),
            ", excused by a marker ", count(d -> d.excused, wide), ")")
    over = [d for d in found if is_over_positional_limit(d)]
    public = [d for d in over if !is_private_name(d.name)]
    println("to answer for: ", length(over), " (public ", length(public),
            ", private ", length(over) - length(public), ")")
    println("\nthe public ones, widest first:")
    for d in sort(public; by = get_positional_count, rev = true)
        println("  ", rpad(string(d.required) * "+" * string(d.optional) * "+" *
                           string(d.keywords), 9),
                rpad(d.name, 34), rpad(d.file * ":" * string(d.line), 54),
                join([isempty(t) ? "?" : t for t in d.types], " "))
    end
    nothing
end

# Runnable on its own. It needs no environment and no dependency:
#
#     julia test/suite/arguments.jl
#     julia test/suite/arguments.jl --report
#
if abspath(PROGRAM_FILE) == @__FILE__
    root = normpath(joinpath(@__DIR__, "..", ".."))
    if "--report" in ARGS
        argument_report(root)
    else
        bad = argument_violations(root)
        if isempty(bad)
            println("every public definition keeps the rule of three, or says why not")
        else
            println("$(length(bad)) argument violation(s):")
            foreach(v -> println("  ", v), bad)
            exit(1)
        end
    end
end
