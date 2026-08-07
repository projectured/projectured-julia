"""
    ProcessToJuliaCodeModule

**Realization**: a `ProcessModel` → a runnable Julia function, built as a
`JuliaDocument` tree and written out through the ordinary `document_to_text`
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
                        body_steps, unrefined_nodes, is_executable
import ..JuliaModule: JuliaDocument, JuliaIdentifier, JuliaString, JuliaCall,
                      JuliaBlock, JuliaIf, JuliaWhile, JuliaFor, JuliaForIterator,
                      JuliaReturn, JuliaBreak, JuliaContinue, JuliaFunction,
                      JuliaNothing
import ..NaturalFormatModule: document_to_text

export realize_process, realize_process_text, export_process

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

# ── The walk ─────────────────────────────────────────────────────────────────

"""
    realize_node(node) -> Vector{JuliaDocument}

One process node as the Julia statements it runs. A vector because a step
splices its action's statements — everything else contributes exactly one.
"""
function realize_node(node)
    if node isa ProcessStep
        action = node.action
        action === nothing && return JuliaDocument[_unrefined("step", node.description)]
        return _statements(action)
    elseif node isa ProcessDecision
        condition = node.condition
        JuliaDocument[JuliaIf(condition === nothing ? _unrefined("condition") : condition,
                              realize_body(node.then_branch),
                              node.else_branch === nothing ?
                              JuliaBlock(JuliaDocument[]) : realize_body(node.else_branch))]
    elseif node isa ProcessWhile
        condition = node.condition
        JuliaDocument[JuliaWhile(condition === nothing ? _unrefined("condition") : condition,
                                 realize_body(node.body))]
    elseif node isa ProcessForeach
        variable = node.variable
        iterable = node.iterable
        JuliaDocument[JuliaFor(JuliaDocument[JuliaForIterator(
                                   variable === nothing ? _id("_") : variable,
                                   iterable === nothing ? _unrefined("iterable") : iterable)],
                               realize_body(node.body))]
    elseif node isa ProcessBreak
        JuliaDocument[JuliaBreak()]
    elseif node isa ProcessContinue
        JuliaDocument[JuliaContinue()]
    elseif node isa ProcessReturn
        value = node.value
        JuliaDocument[value === nothing ? JuliaReturn() : JuliaReturn(value)]
    elseif node isa ProcessSequence
        JuliaDocument[realize_body(node)]
    elseif node isa ProcessInsertion || node isa ProcessNothing
        JuliaDocument[_unrefined("node")]
    else
        # A foreign document in a body is already Julia (or is nothing this
        # module can improve on), so it is spliced as it stands.
        JuliaDocument[node]
    end
end

"""
    realize_body(body) -> JuliaBlock

A body as a Julia block. `nothing` is an empty body, which is a legal —
if pointless — thing to write, and realizes to an empty block rather than to
an error.
"""
function realize_body(body)
    statements = JuliaDocument[]
    for node in body_steps(body)
        append!(statements, realize_node(node))
    end
    JuliaBlock(statements)
end

"""
    realize_process(model::ProcessModel) -> JuliaDocument

The whole process as a `JuliaFunction`: its name, its parameters spliced into
the header verbatim, and its body walked into the function's block.
"""
realize_process(model::ProcessModel) =
    JuliaFunction(_id(model.name),
                  JuliaDocument[p for p in model.parameters],
                  realize_body(model.body))

"""
    realize_process_text(model::ProcessModel) -> String

The realized code as Julia source, through the ordinary `document_to_text`
path, with a header naming the process it came from.
"""
realize_process_text(model::ProcessModel) =
    "# Realized from the process `" * model.name *
    "` — edit the process, not this file.\n\n" *
    document_to_text(realize_process(model)) * "\n"

"""
    export_process(model::ProcessModel, path::AbstractString)

Write the realized code to `path`.
"""
function export_process(model::ProcessModel, path::AbstractString)
    write(path, realize_process_text(model))
    path
end

end # module
