"""
    FsmModule

The state machine document domain: an `FsmComponent` groups extended-state
variables, timers, event declarations and one or more `FsmMachine`s (PLCA needs
two machines over one variable set), plus arbitrary Julia helper items so a
component projects to a complete, runnable module.

The domain includes:
- **Declarations**: `FsmVariable`, `FsmTimer`, `FsmEvent`
- **Structure**: `FsmComponent`, `FsmMachine`, `FsmState`, `FsmTransition`
- **Utility types**: `FsmNothing` for an empty document, `FsmInsertion` for
  cursor positioning

Execution semantics (what a transition list *means*) are specified in
`documentation/package/domain/fsm/fsm.md` — the contract both the code generator and
the runtime support module implement. Embedded code (guards, actions, entry,
variable types/defaults, helpers) are `JuliaDocument` subtrees; this file only
holds them as opaque `Document` values, so the slice has no julia edge at the
document level.

References between parts (a transition's `trigger`/`target`, a machine's
`initial`) are held **by identity** (the `GraphEdge.source/target` model), so
renaming a state or event never dangles a reference. Known limitation, recorded
in the plan: `copy_document` has no alias table, so pasting a copied machine
must re-resolve identity references by name within the pasted subtree.
"""
module FsmModule

using ..GraphModule
using ..JuliaModule
using ..KernelModule
using ..PlatformModule

# Imported to extend: this module adds a method to each of these.
import ..ProjectionModule: print_document, map_reference_forward, map_reference_backward

export get_fsm_states, get_fsm_transitions, find_fsm,
       find_state, find_event, find_timer, get_fsm_transition_index
export FsmDiagram
export FsmTheme, ScaledFsmTheme
export FsmVariableToSyntaxNode, FsmTimerToSyntaxLeaf, FsmEventToSyntaxLeaf,
       FsmTransitionToSyntaxNode, FsmStateToSyntaxNode, FsmMachineToSyntaxNode,
       FsmComponentToSyntaxNode, FsmInsertionToSyntaxLeaf, FsmToSyntax
export FsmToFsmDiagram, FsmToFsmDiagramIoMap
export FsmDiagramToGraph, FsmDiagramToGraphIoMap,
       FsmStateToSyntaxLabel, FsmTransitionToSyntaxLabel, FsmToSyntaxLabel
export generate_component, generate_component_text, export_component,
       get_fsm_state_constant_name, get_fsm_field_name, dispatch_function_name,
       get_fsm_event_constant_name
export FsmDocument, FsmNothing, FsmInsertion, FsmComponent, FsmMachine, FsmState, FsmTransition, FsmVariable, FsmTimer, FsmEvent


include("FsmDocument.jl")
include("FsmDiagram.jl")
include("FsmTheme.jl")
include("FsmToSyntax.jl")
include("FsmToFsmDiagram.jl")
include("FsmDiagramToGraph.jl")
include("FsmToJuliaCode.jl")

end # module
