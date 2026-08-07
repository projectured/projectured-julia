"""
    ProcessDebugSessionModule

Where a realized process **is**, as a document — the one thing both views read
to draw the live position, and the one thing the UI writes to drive execution.

A session is live view state, never content: a running process's position is
not part of the process, exactly as a running machine's state is not part of
the machine (`FsmDiagram`'s rule). It never serializes.

It is a document of its own rather than a field of `ProcessDiagram` because
"where the process is" belongs in the notation as much as in the flowchart —
and the notation is the primary edit surface. The diagram holds one; the
notation is handed the same one.

The cells:

- `status` — `:detached` (nothing realized), `:running`, `:paused` (stopped in
  a probe), `:finished`, or `:stale` (see `node_count`),
- `node` — the node index of the probe last reached, in the domain's position
  vocabulary (`process_nodes`); 0 when nowhere,
- `previous` — the node stepped from, which is what lets the diagram derive
  *which arrow* was just taken without the runtime ever learning a picture
  vocabulary,
- `step_count` — how many probes have been reached,
- `breakpoints` — node indices to stop at. They live here rather than on
  `ProcessStep` because a breakpoint is debug state, not process content,
- `locals` — the `NamedTuple` captured at the last probe under the `:locals`
  instrumentation level, or `nothing`,
- `node_count` — how many nodes the tree had when the code was realized. Node
  indices belong to the tree they were realized from; when this stops matching,
  the position is meaningless and the views must show **no** highlight rather
  than a plausible wrong one.
"""
module ProcessDebugSessionModule

using ..DocumentModule
using ..CollectionModule
using ..ReferenceModule
using ..DomainModule

import ..CellModule: Cell
import ..ProcessModule: ProcessDocument, process_nodes

export ProcessDebugSession, is_stale, has_breakpoint, toggle_breakpoint!

@document struct ProcessDebugSession <: ProcessDocument
    status::Symbol = :detached
    node::Int = 0
    previous::Int = 0
    step_count::Int = 0
    breakpoints::CellVector = CellVector()
    locals::Any = nothing
    node_count::Int = 0
end

insertable(::Type{ProcessDebugSession}) = false

"""
    is_stale(session, model) -> Bool

Whether `session`'s indices still describe `model`. A structural edit while a
realization is attached invalidates every index after the edit; editing an
embedded Julia expression does not, which is why the node *count* is the stamp.
"""
is_stale(session::ProcessDebugSession, model) =
    session.node_count != 0 && session.node_count != length(process_nodes(model))

"Whether execution should stop at node `index`."
has_breakpoint(session::ProcessDebugSession, index::Integer) =
    any(b -> b == index, session.breakpoints)

"""
    toggle_breakpoint!(session, index) -> Bool

Add or remove a breakpoint on node `index`; returns whether it is now set.
"""
function toggle_breakpoint!(session::ProcessDebugSession, index::Integer)
    for (position, value) in enumerate(session.breakpoints)
        if value == index
            deleteat!(session.breakpoints, position)
            return false
        end
    end
    push!(session.breakpoints, Int(index))
    true
end

end # module
