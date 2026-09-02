"""
    ProcessToJuliaCodeModule

**Realization**: a `ProcessModel` → a runnable Julia function, built as a
`JuliaDocument` tree and written out through the ordinary `print_natural_text`
path.

This is deliberately **not** a registered bidirectional projection. Reading a
hand-edited generated file back into a process is not a goal — the process
document is the source, the `.jl` file is output — and the bidirectionality
convention applies to editor projections, not to exporters. What it *is* is a
document-to-document function, so realized code can also be shown in the editor
(through the stock Julia pipeline) without generating a string first.

The embedded code is **spliced verbatim**: a condition, an action, an iterable
is already a `JuliaDocument`, so it is placed into the realized tree as-is.
Nothing is stringified and re-parsed, and nothing is rewritten — what the
author sees in the notation is exactly what runs.

## The mapping

There is no cleverness in it, which is the point of the domain's shape: every
process node has a Julia counterpart with the same fields, so the walk is 1:1.

| process | julia |
|---|---|
| `ProcessModel(name, parameters, body)` | `JuliaFunction` |
| `ProcessSequence(steps)` | `JuliaBlock` |
| `ProcessStep(_, action)` | the action's statements, spliced |
| `ProcessDecision(c, t, e)` | `JuliaIf` |
| `ProcessWhile(c, body)` | `JuliaWhile` |
| `ProcessForeach(v, i, body)` | `JuliaFor` with one iterator clause |
| `ProcessBreak` / `ProcessContinue` / `ProcessReturn` | the same three |

An **unrefined** node — a step with no action, a decision or loop with no
condition — realizes to `error("unrefined …")` rather than to nothing: an
informal box that silently did nothing would be a process that lies about what
it does. [`is_executable`](@ref) is the check to run *before* realizing;
`unrefined_nodes` says which boxes are still prose.

Step descriptions do not survive into realized code — the julia domain has no
comment node — so the notation and the diagram are where the prose lives.
"""
module ProcessToJuliaCodeModule

import ..ProcessModule: ProcessModel, ProcessSequence, ProcessStep, ProcessDecision,
                        ProcessWhile, ProcessForeach, ProcessBreak, ProcessContinue,
                        ProcessReturn, ProcessNothing, ProcessInsertion,
                        body_steps, process_nodes, unrefined_nodes, is_executable
import ..JuliaModule: JuliaDocument, JuliaIdentifier, JuliaString, JuliaCall,
                      JuliaBlock, JuliaIf, JuliaWhile, JuliaFor, JuliaForIterator,
                      JuliaReturn, JuliaBreak, JuliaContinue, JuliaFunction,
                      JuliaNothing, JuliaInteger, JuliaAssignment, JuliaNamedTuple,
                      JuliaTypeAnnotation
import ..DocumentModule: search_documents
import ..NaturalNotationModule: print_natural_text

export realize_process, realize_process_text, export_process,
       PROCESS_INSTRUMENTATION_LEVELS, TRACE_PARAMETER_NAME

# ── Small AST helpers ────────────────────────────────────────────────────────

_id(name::AbstractString) = JuliaIdentifier(String(name))

# The statements of an embedded action: a block contributes its statements, a
# bare expression contributes itself, so a one-line action stays one line.
_statements(doc) =
    doc isa JuliaBlock ? JuliaDocument[s for s in doc.statements] : JuliaDocument[doc]

# What an unrefined hole realizes to. An expression, so it works in a
# condition slot as well as a statement slot.
_unrefined(what::AbstractString, detail::AbstractString = "") =
    JuliaCall(_id("error"),
              JuliaDocument[JuliaString("unrefined " * what *
                                        (isempty(detail) ? "" : ": " * detail))])

# ── Instrumentation ──────────────────────────────────────────────────────────

"The instrumentation levels `realize_process` accepts."
const PROCESS_INSTRUMENTATION_LEVELS = (:none, :position, :locals)

"The name of the parameter an instrumented realization threads its trace through."
const TRACE_PARAMETER_NAME = "trace"

# One realization's settings: how to number nodes, how much to report, and —
# for `:locals` — which variables are in scope where the walk currently is.
struct _Realization
    level::Symbol
    indices::IdDict{Any,Int}
    scope::Vector{String}
end

function _realization(model, level::Symbol)
    level in PROCESS_INSTRUMENTATION_LEVELS ||
        error("unknown instrumentation level `$level`; expected one of $PROCESS_INSTRUMENTATION_LEVELS")
    indices = IdDict{Any,Int}()
    if level !== :none && model isa ProcessModel
        for (index, node) in enumerate(process_nodes(model))
            indices[node] = index
        end
    end
    _Realization(level, indices, String[])
end

# The one statement instrumentation adds, in front of whatever the node does.
# Additive and always in statement position, which is what makes an
# instrumented realization behave identically to a plain one.
function _probe(realization::_Realization, node)
    realization.level === :none && return JuliaDocument[]
    index = get(realization.indices, node, 0)
    index == 0 && return JuliaDocument[]
    arguments = JuliaDocument[_id(TRACE_PARAMETER_NAME), JuliaInteger(index)]
    if realization.level === :locals && !isempty(realization.scope)
        push!(arguments, JuliaNamedTuple(
            JuliaDocument[JuliaAssignment(:(=), _id(name), _id(name))
                          for name in realization.scope]))
    end
    JuliaDocument[JuliaCall(_id("process_at!"), arguments)]
end

# A name the walk can report as a local from here on. The scope only ever
# grows: a variable assigned inside a branch is still a name that exists after
# it, and reporting one that happens to be undefined is a worse failure than
# reporting one too many.
function _bind_scope!(realization::_Realization, name::AbstractString)
    realization.level === :locals || return nothing
    isempty(name) && return nothing
    name in realization.scope || push!(realization.scope, String(name))
    nothing
end

_parameter_name(parameter) =
    parameter isa JuliaIdentifier ? parameter.name :
    parameter isa JuliaTypeAnnotation && parameter.value isa JuliaIdentifier ?
        parameter.value.name : ""

# Every plain-identifier assignment target inside an embedded expression: what
# a step adds to the scope by running.
function _assigned_names(document)
    names = String[]
    document === nothing && return names
    for assignment in search_documents(document, x -> x isa JuliaAssignment)
        target = assignment.target
        target isa JuliaIdentifier && push!(names, target.name)
    end
    names
end

# ── The walk ─────────────────────────────────────────────────────────────────

"""
    realize_node(node, realization) -> Vector{JuliaDocument}

One process node as the Julia statements it runs, its probe first. A vector
because a step splices its action's statements — everything else contributes
one statement plus its probe.

A loop is probed twice: once before it, and once as the first statement of its
body. That marks the header on entry and on every iteration, including the one
a `continue` jumps to. The final test — the one that fails and ends the loop —
is not marked, which is the one position a realized loop does not report.
"""
function realize_node(node, realization::_Realization = _realization(nothing, :none))
    probe = _probe(realization, node)
    if node isa ProcessStep
        action = node.action
        statements = action === nothing ?
            JuliaDocument[_unrefined("step", node.description)] : _statements(action)
        result = JuliaDocument[probe..., statements...]
        for name in _assigned_names(action)
            _bind_scope!(realization, name)
        end
        return result
    elseif node isa ProcessDecision
        condition = node.condition
        JuliaDocument[probe...,
                      JuliaIf(condition === nothing ? _unrefined("condition") : condition,
                              realize_body(node.then_branch, realization),
                              node.else_branch === nothing ?
                              JuliaBlock(JuliaDocument[]) :
                              realize_body(node.else_branch, realization))]
    elseif node isa ProcessWhile
        condition = node.condition
        JuliaDocument[probe...,
                      JuliaWhile(condition === nothing ? _unrefined("condition") : condition,
                                 _loop_body(node.body, realization, probe))]
    elseif node isa ProcessForeach
        variable = node.variable
        iterable = node.iterable
        JuliaDocument[probe...,
                      JuliaFor(JuliaDocument[JuliaForIterator(
                                   variable === nothing ? _id("_") : variable,
                                   iterable === nothing ? _unrefined("iterable") : iterable)],
                               _loop_body(node.body, realization, probe,
                                          _parameter_name(variable)))]
    elseif node isa ProcessBreak
        JuliaDocument[probe..., JuliaBreak()]
    elseif node isa ProcessContinue
        JuliaDocument[probe..., JuliaContinue()]
    elseif node isa ProcessReturn
        value = node.value
        JuliaDocument[probe..., value === nothing ? JuliaReturn() : JuliaReturn(value)]
    elseif node isa ProcessSequence
        JuliaDocument[realize_body(node, realization)]
    elseif node isa ProcessInsertion || node isa ProcessNothing
        JuliaDocument[probe..., _unrefined("node")]
    else
        # A foreign document in a body is already Julia (or is nothing this
        # module can improve on), so it is spliced as it stands.
        JuliaDocument[node]
    end
end

# A loop body, realized in its own scope. Julia gives a loop a scope of its
# own: the iteration variable and anything first assigned inside the body are
# gone once it ends, so reporting them afterwards would name variables that do
# not exist. A decision's branches get no such treatment — an `if` block
# introduces no scope, and a name assigned in one branch is live after it.
function _loop_body(body, realization::_Realization, leading, variable::AbstractString = "")
    depth = length(realization.scope)
    _bind_scope!(realization, variable)
    block = realize_body(body, realization; leading = leading)
    realization.level === :locals && resize!(realization.scope, depth)
    block
end

"""
    realize_body(body, realization; leading = JuliaDocument[]) -> JuliaBlock

A body as a Julia block. `nothing` is an empty body, which is a legal — if
pointless — thing to write, and realizes to an empty block rather than to an
error. `leading` is prepended inside the block, which is how a loop's header
probe reaches every iteration.
"""
function realize_body(body, realization::_Realization = _realization(nothing, :none);
                      leading = JuliaDocument[])
    statements = JuliaDocument[leading...]
    for node in body_steps(body)
        append!(statements, realize_node(node, realization))
    end
    JuliaBlock(statements)
end

"""
    realize_process(model::ProcessModel; instrumentation = :none) -> JuliaDocument

The whole process as a `JuliaFunction`: its name, its parameters spliced into
the header verbatim, and its body walked into the function's block.

`instrumentation` picks how much the realized code reports as it runs:

- `:none` — nothing at all. The artifact to ship; zero overhead.
- `:position` — `process_at!(trace, i)` per node: where execution is.
- `:locals` — the same plus a `NamedTuple` of the variables in scope there.
  It allocates per probe, which is why it is a level rather than the default.

Either instrumented level appends a `trace = nothing` parameter, so the
realized function is still callable with the process's own arguments alone and
still runs at full speed when nothing is attached.
"""
function realize_process(model::ProcessModel; instrumentation::Symbol = :none)
    realization = _realization(model, instrumentation)
    parameters = JuliaDocument[p for p in model.parameters]
    for parameter in parameters
        _bind_scope!(realization, _parameter_name(parameter))
    end
    if instrumentation !== :none
        push!(parameters, JuliaAssignment(:(=), _id(TRACE_PARAMETER_NAME), JuliaNothing()))
    end
    JuliaFunction(_id(model.name), parameters, realize_body(model.body, realization))
end

"""
    realize_process_text(model::ProcessModel; instrumentation = :none) -> String

The realized code as Julia source, through the ordinary `print_natural_text`
path, with a header naming the process it came from.
"""
realize_process_text(model::ProcessModel; instrumentation::Symbol = :none) =
    "# Realized from the process `" * model.name *
    "` — edit the process, not this file.\n\n" *
    print_natural_text(realize_process(model; instrumentation = instrumentation)) * "\n"

"""
    export_process(model::ProcessModel, path::AbstractString; instrumentation = :none)

Write the realized code to `path`.
"""
function export_process(model::ProcessModel, path::AbstractString;
                        instrumentation::Symbol = :none)
    write(path, realize_process_text(model; instrumentation = instrumentation))
    path
end

end # module
