"""
    ProcessModule

The process document domain: an algorithm as a **structured flowchart** —
steps, decisions, loops and jumps that nest and run to completion.

A process is the run-to-completion complement of a state machine. An
`FsmState` is where control *rests*, waiting for an event; a `ProcessStep` is
work control *passes through*, and what advances a process is the completion
of the step before it, never an external event. Waiting stays in the fsm
domain by design, which is what keeps the two complementary rather than
overlapping.

The domain includes:
- **Structure**: `ProcessModel`, `ProcessSequence`
- **Nodes**: `ProcessStep`, `ProcessDecision`, `ProcessWhile`, `ProcessForeach`
- **Jumps**: `ProcessBreak`, `ProcessContinue`, `ProcessReturn`
- **Utility types**: `ProcessNothing` for an empty document, `ProcessInsertion`
  for cursor positioning

The tree is **structured, not a node/edge list**: sequences, decisions and
loops nest, and the flowchart picture is derived from that nesting rather than
stored. Two things follow. Node shapes align field-for-field with the julia
domain's structured control flow (`ProcessDecision` ↔ `JuliaIf`,
`ProcessWhile` ↔ `JuliaWhile`, `ProcessForeach` ↔ `JuliaFor`,
`ProcessSequence` ↔ `JuliaBlock`), so realization is a mechanical 1:1 walk;
and nothing here is held by identity, so a subtree copies structurally with no
alias fix-up (the limitation `FsmModule` records for machines).

A step may be **informal**: a `description` with no `action` yet is a spec
box ("wait for carrier") that has not been refined into code. That, not the
control flow, is why this is a domain rather than a flowchart projection over
julia function bodies.

Embedded code (a decision's condition, a step's action, a loop's variable and
iterable, the model's parameters) are `JuliaDocument` subtrees held here as
opaque `Document` values, so the slice has no julia edge at the document
level. Execution and realization semantics — what a tree *means* — are
specified in `package/domain/doc/process.md`.
"""
module ProcessModule

using ..DocumentModule
using ..CollectionModule
using ..ReferenceModule
using ..ProjectionReferenceStepModule
using ..OperationModule
using ..SelectionModule
using ..EventPatternModule
using ..GestureBindingModule
using ..DomainModule

import ..CellModule: Cell

export process_children, process_nodes, get_node_index, find_node_at_index, get_body_steps,
       get_unrefined_nodes, is_executable

@domain Process

# ── Structure ────────────────────────────────────────────────────────────

"""
A sequence of nodes run in order — the process domain's block. Every body in
the domain (a model's, a branch's, a loop's) is one of these, so recursion has
a single shape. An empty sequence is the natural insert point for the reader.
"""
@document struct ProcessSequence <: ProcessDocument
    steps::CellVector = CellVector()
end

"""
A process: the unit of realization (one generated Julia function).
`parameters` are embedded `JuliaDocument` items (an identifier, or an
identifier with a type annotation) and `body` is the `ProcessSequence` the
call runs.
"""
@document struct ProcessModel <: ProcessDocument
    name::String
    parameters::CellVector = CellVector()
    body::Any = nothing
end

# ── Nodes ────────────────────────────────────────────────────────────────

"""
One unit of work — the flowchart's process box.

- `description` — the prose face of the step, shown in the diagram; `""` for a
  step that is only its code.
- `action` — an embedded `JuliaDocument` statement or block; `nothing` marks
  the step **unrefined**: an informal box that has not been given code yet.
  A model containing one is a legal document but not an executable one
  ([`is_executable`](@ref)).
"""
@document struct ProcessStep <: ProcessDocument
    description::String
    action::Any = nothing
end

"""
A binary decision — the flowchart's diamond, and `JuliaIf`'s shape.

`condition` is an embedded `JuliaDocument` boolean expression (`nothing` =
not yet refined). `then_branch` is the sequence taken when it holds;
`else_branch` is `nothing` when the decision has no else branch at all, which
is what distinguishes it from an empty one.
"""
@document struct ProcessDecision <: ProcessDocument
    condition::Any = nothing
    then_branch::Any = nothing
    else_branch::Any = nothing
end

"""
A pre-test loop: run `body` while the embedded `condition` holds. `JuliaWhile`'s
shape.
"""
@document struct ProcessWhile <: ProcessDocument
    condition::Any = nothing
    body::Any = nothing
end

"""
An iteration loop: run `body` once for each element of `iterable`, bound to
`variable`. `variable` and `iterable` are embedded `JuliaDocument`s, so this is
`JuliaFor`'s single-clause shape.
"""
@document struct ProcessForeach <: ProcessDocument
    variable::Any = nothing
    iterable::Any = nothing
    body::Any = nothing
end

# ── Jumps ────────────────────────────────────────────────────────────────

"""
Leave the enclosing loop.
"""
@document struct ProcessBreak <: ProcessDocument
end

"""
Skip to the enclosing loop's next iteration.
"""
@document struct ProcessContinue <: ProcessDocument
end

"""
Leave the process, optionally with an embedded `JuliaDocument` result.
"""
@document struct ProcessReturn <: ProcessDocument
    value::Any = nothing
end

# ── Mixed positional+keyword constructors ────────────────────────────────
# The macro emits all-positional or all-keyword forms, never the mix, so the
# natural authoring shapes are hand-written. Typed arguments keep these
# strictly more specific than the generated `::Any` forms (the `FsmComponent`
# precedent) — shadowing a generated method would be a fatal precompile
# overwrite.

_process_cellvector(items) =
    items isa CellVector ? items :
    CellVector(Cell[x isa Cell ? x : Cell(x) for x in items])

ProcessModel(name::AbstractString; parameters = [], body = nothing) =
    ProcessModel(Cell(String(name)), _process_cellvector(parameters), Cell(body), Cell(nothing))

ProcessStep(description::AbstractString; action = nothing) =
    ProcessStep(Cell(String(description)), Cell(action), Cell(nothing))

ProcessDecision(condition; then_branch = nothing, else_branch = nothing) =
    ProcessDecision(Cell(condition), Cell(then_branch), Cell(else_branch), Cell(nothing))

ProcessWhile(condition; body = nothing) =
    ProcessWhile(Cell(condition), Cell(body), Cell(nothing))

ProcessForeach(variable, iterable; body = nothing) =
    ProcessForeach(Cell(variable), Cell(iterable), Cell(body), Cell(nothing))

ProcessReturn(value) = ProcessReturn(Cell(value), Cell(nothing))

# ── The tree walk ────────────────────────────────────────────────────────
# One vocabulary, used by the notation, the diagram, realization and the
# debugger: a node's index in the flattened document order. `get_fsm_states` /
# `get_fsm_transitions` play the same role for fsm.

"""
    process_children(node) -> iterable

A node's **structural** children, in document order. Embedded
`JuliaDocument`s (conditions, actions, iterables, parameters) are opaque and
are not children — nothing in this domain walks into them.
"""
process_children(::Any) = ()
process_children(node::ProcessModel) = (node.body,)
process_children(node::ProcessSequence) = node.steps
process_children(node::ProcessDecision) = (node.then_branch, node.else_branch)
process_children(node::ProcessWhile) = (node.body,)
process_children(node::ProcessForeach) = (node.body,)

"""
    process_nodes(root) -> Vector{Any}

Every node of the tree in **document order** (a node before its children,
children left to right). A node's 1-based index in this vector is the domain's
position vocabulary: it is what realized code reports, what a breakpoint
names, and what both views resolve back to a node.

Placeholders (`ProcessInsertion`, `ProcessNothing`) count as nodes — a
document being edited is a legal document, and skipping them would shift
every index after the caret.
"""
function process_nodes(root)
    result = Any[]
    _collect_process_nodes!(result, root)
    result
end

# A non-process child (`nothing` for an absent branch, an embedded Julia
# subtree) contributes no node and is not descended into.
_collect_process_nodes!(result, ::Any) = nothing

function _collect_process_nodes!(result, node::ProcessDocument)
    push!(result, node)
    for child in process_children(node)
        _collect_process_nodes!(result, child)
    end
    nothing
end

"""
    get_node_index(root, node) -> Int

`node`'s 1-based index in `root`'s document order, by identity; 0 when it is
not in the tree.
"""
function get_node_index(root, node)
    for (index, candidate) in enumerate(process_nodes(root))
        candidate === node && return index
    end
    0
end

"""
    node_at(root, index) -> node or nothing

The node `index` names, or `nothing` when the index is out of range — which is
what a stale position looks like, and why this returns rather than throws.
"""
function find_node_at_index(root, index)
    nodes = process_nodes(root)
    (index < 1 || index > length(nodes)) ? nothing : nodes[index]
end

"""
    get_body_steps(body) -> Vector{Any}

The nodes of a body. `nothing` is an empty body and a `ProcessSequence` is its
steps; anything else is a one-node body, so a branch that holds a bare node
still renders and still runs.
"""
get_body_steps(body) =
    body === nothing ? Any[] :
    body isa ProcessSequence ? Any[step for step in body.steps] :
    Any[body]

# ── Executability ────────────────────────────────────────────────────────

"""
    get_unrefined_nodes(root) -> Vector{Any}

The nodes that have no code behind them yet: a step with no action, a
decision or `while` with no condition, a `foreach` with no variable or no
iterable. A model with none is executable; realization reports the rest rather
than emitting something that silently does nothing.
"""
function get_unrefined_nodes(root)
    result = Any[]
    for node in process_nodes(root)
        if node isa ProcessStep
            node.action === nothing && push!(result, node)
        elseif node isa ProcessDecision || node isa ProcessWhile
            node.condition === nothing && push!(result, node)
        elseif node isa ProcessForeach
            (node.variable === nothing || node.iterable === nothing) && push!(result, node)
        elseif node isa ProcessInsertion || node isa ProcessNothing
            push!(result, node)
        end
    end
    result
end

"""
    is_executable(root) -> Bool

Whether every node of `root` has been refined into code.
"""
is_executable(root) = isempty(get_unrefined_nodes(root))

# ── Insertion factories ──────────────────────────────────────────────────
# Only the types with a required field need one; everything else is zero-arg
# constructible, which is what `insertable(T)`'s probe asks for.

@insertion ProcessModel = @with_selection ProcessModel("") name{0}
@insertion ProcessStep  = @with_selection ProcessStep("") description{0}

# ── Structural-insert gestures ───────────────────────────────────────────

@gestures ProcessSequence begin
    KeyPress(',') => "Insert a new step" => append_insertion_operation(doc, :steps, ProcessInsertion)
end

end # module
