# Fragment of `FsmModule`.
#
# The state machine **diagram's presentation document** — what a machine looks
# like on screen, as opposed to what it is.
#
# `FsmDiagram` is projection output (`FsmToFsmDiagram` builds it once and keeps
# its identity across reprints, exactly as `ChartToChartPlot` does with
# `ChartPlot`), so the live fields below are never document content and never
# serialize: a running machine's position is not part of the machine.
#
# The three live fields are what a running simulation writes — one scalar cell
# each, so the monitor task's per-slice refresh is three comparisons and at most
# three writes:
#
# - `live_state` — 1-based index into the machine's states; 0 when nothing is
#   running,
# - `live_transition` — 1-based index into the machine's *flattened* transition
#   order (`get_fsm_transitions`), the last one taken; 0 when none yet,
# - `transition_count` — how many transitions the machine has taken.
#
# The diagram renders the current state as a ring and the last transition as a
# re-stroked edge. Both are drawn from these fields alone, never from a state's
# rendered content, so a transition arriving mid-run repaints the overlay without
# re-running the layout engine.
using ..KernelModule
using ..PlatformModule



@document struct FsmDiagram <: FsmDocument
    machine::Any
    live_state::Int = 0
    live_transition::Int = 0
    transition_count::Int = 0
end
