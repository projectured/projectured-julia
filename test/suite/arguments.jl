# ============================================================================
# The argument guard — the clause on optional positional arguments, where a
# machine can read it.
#
# `documentation/rule/code-quality-rules.md` §4 says it: anything that a caller
# may leave out is a keyword, so a definition takes at most one optional
# positional argument, and never one beside a keyword argument. It is a
# recommendation, and an exception says why with a `# @optional: <reason>`
# marker above the definition.
#
# **It fails on every public definition that breaks the clause** with no marker,
# outside a port, and on every `# @positional:` marker, which no rule needs: the
# count of positional arguments is advice, and `--report` prints it.
#
# **A private helper is out of scope**, by the owner's decision of 2026-09-22: a
# helper inside one file costs one reader one file, and a public function costs
# every call site.
#
# **It also fails on a call of `get_evaluation_editor` that is not the default of
# an `editor` keyword** of a definition, private or public. PAR-PER-EDITOR-STATE
# says it: only a verb reads the editor of an evaluation, and only when its
# caller names no editor.
#
# **Static, and deliberately.** It parses each file with the parser of Julia and
# loads nothing, so it runs in about a second and reads a definition rather than
# a line of text.
# ============================================================================

"The folders the rule covers: the code a person writes, and not the tests."
const ARGUMENT_ROOTS = ["source", "example"]

"The count of positional arguments that the report counts as over the advice."
const POSITIONAL_LIMIT = 3

# The generic functions of a protocol: every method takes the arity of the
# contract. The report counts them apart. A method of Base is here as well.
const ARGUMENT_PROTOCOL = Set(String[
    "print_document", "print_document_pure", "print_child", "print_child_pure",
    "read_intent", "map_reference_forward", "map_reference_backward", "read_gesture",
    "evaluate_operation", "reroot_operation", "retarget_operation", "operation_reference",
    "match_reference_step", "match_reference_step_value", "solve_constraint_layout",
    "splice_value!", "copy_document",
    "getproperty", "setproperty!", "getindex", "setindex!", "iterate", "length",
    "show", "hash", "isequal", "print", "size", "handle_message", "shouldlog",
    "sync_document!", "layout_graph", "recognize", "read_child_by_route",
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
    marked::Bool           # a `# @optional:` marker stands above it
end

# The folders of a port: code that keeps the signature of the program it mirrors.
const PORT_FOLDERS = ["source/domain/graph/cpp/"]

get_positional_count(d::ArgumentDefinition) = d.required + d.optional
is_port_definition(d::ArgumentDefinition) = any(folder -> startswith(d.file, folder), PORT_FOLDERS)
"At most one optional positional argument, and never one beside a keyword argument."
keeps_optional_clause(d::ArgumentDefinition) =
    d.optional <= 1 && !(d.optional == 1 && d.keywords > 0)
is_protocol_name(name::AbstractString) = name in ARGUMENT_PROTOCOL
is_private_name(name::AbstractString) = startswith(name, "_")
is_over_positional_limit(d::ArgumentDefinition) =
    get_positional_count(d) > POSITIONAL_LIMIT && !is_protocol_name(d.name)

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
The lines a `# @optional:` marker stands above: under each marker, the first line
that is neither blank nor a comment.
"""
function _find_optional_markers(text::AbstractString)
    lines = split(text, '\n')
    marked = Set{Int}()
    for (number, line) in enumerate(lines)
        occursin(r"^\s*#\s*@optional:", line) || continue
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
                                           _find_optional_markers(text))
        end
    end
    sort!(found; by = d -> (d.file, d.line))
end

"""
    find_positional_markers(root) -> Vector{String}

Every `# @positional:` marker under the folders the rule covers, as `file:line`.
"""
function find_positional_markers(root::AbstractString)
    found = String[]
    for folder in ARGUMENT_ROOTS
        full = joinpath(root, folder)
        isdir(full) || continue
        for (here, _dirs, names) in walkdir(full), name in names
            endswith(name, ".jl") || continue
            path = relpath(joinpath(here, name), root)
            for (number, line) in enumerate(eachline(joinpath(root, path)))
                occursin(r"^\s*#\s*@positional:", line) &&
                    push!(found, "$(path):$(number)")
            end
        end
    end
    sort!(found)
end

_is_evaluation_editor_call(x) =
    x isa Expr && x.head === :call && _argument_name(x.args[1]) == "get_evaluation_editor"

# A keyword of a signature that is `editor = get_evaluation_editor()`, with or
# without a type on `editor`.
function _is_editor_keyword_default(parameter)
    (parameter isa Expr && parameter.head === :kw) || return false
    name = parameter.args[1]
    name isa Expr && name.head === :(::) && (name = name.args[1])
    name === :editor && _is_evaluation_editor_call(parameter.args[2])
end

# The calls of `get_evaluation_editor` in `expression`, as `file:line`. The
# default of an `editor` keyword of a definition is skipped. The signature of a
# definition names its function and calls nothing, so it is not reported, but
# the walk reads its other defaults.
function _collect_evaluation_editor_reads!(found, expression, file, line,
                                           signatures = Base.IdSet{Any}(),
                                           defaults = Base.IdSet{Any}())
    expression isa Expr || return line
    expression in defaults && return line
    if _is_argument_definition(expression)
        signature = _argument_signature(expression.args[1])
        if signature isa Expr && signature.head === :call
            push!(signatures, signature)
            for argument in signature.args[2:end]
                (argument isa Expr && argument.head === :parameters) || continue
                for parameter in argument.args
                    _is_editor_keyword_default(parameter) && push!(defaults, parameter.args[2])
                end
            end
        end
    end
    _is_evaluation_editor_call(expression) && !(expression in signatures) &&
        push!(found, "$(file):$(line)")
    for argument in expression.args
        argument isa LineNumberNode && (line = argument.line; continue)
        line = _collect_evaluation_editor_reads!(found, argument, file, line,
                                                 signatures, defaults)
    end
    line
end

"""
    find_evaluation_editor_reads(root) -> Vector{String}

Every call of `get_evaluation_editor` under the folders the rule covers that is
not the default of an `editor` keyword of a definition, as `file:line`.
"""
function find_evaluation_editor_reads(root::AbstractString)
    found = String[]
    for folder in ARGUMENT_ROOTS
        full = joinpath(root, folder)
        isdir(full) || continue
        for (here, _dirs, names) in walkdir(full), name in names
            endswith(name, ".jl") || continue
            path = relpath(joinpath(here, name), root)
            parsed = try
                Meta.parseall(read(joinpath(root, path), String); filename = path)
            catch
                continue          # the naming guard reports a file the parser refuses
            end
            _collect_evaluation_editor_reads!(found, parsed, path, 0)
        end
    end
    sort!(found)
end

"""
    argument_violations(root) -> Vector{String}

A public definition outside a port that takes more than one optional positional
argument, or one beside a keyword argument, with no `# @optional:` marker; every
`# @positional:` marker; and every call of `get_evaluation_editor` that is not
the default of an `editor` keyword.
"""
function argument_violations(root::AbstractString)
    out = String[]
    for d in find_argument_definitions(root)
        (is_private_name(d.name) || is_port_definition(d) || d.marked) && continue
        keeps_optional_clause(d) && continue
        push!(out, "$(d.file):$(d.line) $(d.name) takes $(d.optional) optional " *
                   "positional " *
                   "argument(s)$(d.keywords > 0 ? " beside keyword arguments" : "") — " *
                   "make them keywords, or write `# @optional: <reason>` above it; " *
                   "see code-quality-rules.md §4")
    end
    for place in find_positional_markers(root)
        push!(out, "$(place) has a `# @positional:` marker, which no rule needs: the " *
                   "count of positional arguments is advice; remove the marker")
    end
    for place in find_evaluation_editor_reads(root)
        push!(out, "$(place) calls get_evaluation_editor outside the default of an " *
                   "`editor` keyword — pass the editor that the code has, or take it as " *
                   "`editor = get_evaluation_editor()`; see PAR-PER-EDITOR-STATE")
    end
    out
end

"""
    argument_report(root) -> Nothing

What the arguments look like across the code: how many definitions take how many
positional arguments, the public ones over the advice of three, and the
definitions that break the optional clause. It fails nothing.
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
    println("over the advice of ", POSITIONAL_LIMIT, ": ", length(wide),
            " (protocol ", count(d -> is_protocol_name(d.name), wide), ")")
    over = [d for d in found if is_over_positional_limit(d)]
    public = [d for d in over if !is_private_name(d.name)]
    println("over the advice, not a protocol: ", length(over), " (public ",
            length(public),
            ", private ", length(over) - length(public), ")")
    optional = [d for d in found if !keeps_optional_clause(d)]
    println("breaking the optional clause: ", length(optional), " (marked ",
            count(d -> d.marked, optional), ")")
    println("\nthe public ones over the advice, widest first:")
    for d in sort(public; by = get_positional_count, rev = true)
        println("  ", rpad(string(d.required) * "+" * string(d.optional) * "+" *
                           string(d.keywords), 9),
                rpad(d.name, 34), rpad(d.file * ":" * string(d.line), 54),
                join([isempty(t) ? "?" : t for t in d.types], " "))
    end
    nothing
end

# Runnable on its own. It needs no environment and no dependency. A path names
# the root of another repository, whose `source/` and `example/` it reads:
#
#     julia test/suite/arguments.jl
#     julia test/suite/arguments.jl --report
#     julia test/suite/arguments.jl ../omnet-julia
#
if abspath(PROGRAM_FILE) == @__FILE__
    paths = filter(argument -> !startswith(argument, "--"), ARGS)
    root = isempty(paths) ? normpath(joinpath(@__DIR__, "..", "..")) :
           abspath(first(paths))
    if "--report" in ARGS
        argument_report(root)
    else
        bad = argument_violations(root)
        if isempty(bad)
            println("every public definition keeps the optional clause, or says why not")
        else
            println("$(length(bad)) argument violation(s):")
            foreach(v -> println("  ", v), bad)
            exit(1)
        end
    end
end
