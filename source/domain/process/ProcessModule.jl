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
specified in `documentation/package/domain/process/process.md`.
"""
module ProcessModule

using ..CellModule
using ..CollectionModule
using ..DocumentModule
using ..DomainModule
using ..EventModule
using ..GestureBindingModule
using ..GraphModule
using ..IoMapModule
using ..JuliaModule
using ..NaturalModule
using ..OperationModule
using ..ProjectionAlgebraModule
using ..ProjectionModule
using ..ReferenceModule
using ..SelectionModule
using ..StyleModule
using ..SyntaxModule
using ..TextModule

# Imported to extend: this module adds a method to each of these.
import ..ProjectionModule: print_document, map_reference_forward, map_reference_backward

export process_children, process_nodes, get_node_index, find_node_at_index, get_body_steps,
       get_unrefined_nodes, is_executable
export ProcessTrace, ProcessStoppedException, process_at!,
       resume_process!, pause_process!, stop_process!, set_process_breakpoints!,
       is_process_paused, is_process_finished
export ProcessDiagram, ProcessTerminal, ProcessEdgeLabel
export ProcessDebugSession, is_stale, has_breakpoint, toggle_breakpoint!,
       set_process_position!, sync_process_debug!, detach_process_debug!
export ProcessSequenceToSyntaxNode, ProcessModelToSyntaxNode,
       ProcessStepToSyntaxNode, ProcessDecisionToSyntaxNode,
       ProcessWhileToSyntaxNode, ProcessForeachToSyntaxNode,
       ProcessBreakToSyntaxLeaf, ProcessContinueToSyntaxLeaf,
       ProcessReturnToSyntaxNode, ProcessInsertionToSyntaxLeaf, ProcessToSyntax
export ProcessToProcessDiagram, ProcessToProcessDiagramIoMap
export ProcessDiagramToGraph, ProcessDiagramToGraphIoMap,
       ProcessStepToSyntaxLabel, ProcessDecisionToSyntaxLabel,
       ProcessWhileToSyntaxLabel, ProcessForeachToSyntaxLabel,
       ProcessTerminalToSyntaxLabel, ProcessEdgeLabelToSyntaxLeaf,
       ProcessToSyntaxLabel
export realize_process, realize_process_text, export_process,
       PROCESS_INSTRUMENTATION_LEVELS, TRACE_PARAMETER_NAME
export start_process, realize_into, ProcessRun
export ProcessDocument, ProcessNothing, ProcessInsertion, ProcessModel, ProcessSequence, ProcessStep, ProcessDecision, ProcessWhile, ProcessForeach, ProcessBreak, ProcessContinue, ProcessReturn


include("ProcessDocument.jl")
include("ProcessRuntime.jl")
include("ProcessDiagram.jl")
include("ProcessDebugSession.jl")
include("ProcessToSyntax.jl")
include("ProcessToProcessDiagram.jl")
include("ProcessDiagramToGraph.jl")
include("ProcessToJuliaCode.jl")
include("ProcessDebug.jl")

end # module
