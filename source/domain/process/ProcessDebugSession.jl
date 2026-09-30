# Fragment of `ProcessModule`.
#
# Where a realized process **is**, as a document — the one thing both views read
# to draw the live position, and the one thing the UI writes to drive execution.
#
# A session is live view state, never content: a running process's position is
# not part of the process, exactly as a running machine's state is not part of
# the machine (`FsmDiagram`'s rule). It never serializes.
#
# It is a document of its own rather than a field of `ProcessDiagram` because
# "where the process is" belongs in the notation as much as in the flowchart —
# and the notation is the primary edit surface. The diagram holds one; the
# notation is handed the same one.
#
# The cells:
#
# - `status` — `:detached` (nothing realized), `:running`, `:paused` (stopped in
#   a probe), `:finished`, or `:stale` (see `node_count`),
# - `node` — the node index of the probe last reached, in the domain's position
#   vocabulary (`process_nodes`); 0 when nowhere,
# - `previous` — the node stepped from, which is what lets the diagram derive
#   *which arrow* was just taken without the runtime ever learning a picture
#   vocabulary,
# - `current` / `previous_document` — the same two positions as the **documents**
#   they name. Indices are the vocabulary the runtime speaks; documents are what
#   a view can compare against the node it is drawing, without having to walk
#   the tree from a root it does not have. `set_process_position!` is the one
#   place the two representations are set, so they cannot disagree,
# - `step_count` — how many probes have been reached,
# - `breakpoints` — the **nodes** to stop at, held by identity. They live here
#   rather than on `ProcessStep` because a breakpoint is debug state, not process
#   content, and they are documents rather than indices because that is what a
#   view has in hand when it draws one, and what survives an edit that renumbers
#   the tree. The bridge converts them to indices for the runtime,
# - `locals` — the `NamedTuple` captured at the last probe under the `:locals`
#   instrumentation level, or `nothing`,
# - `node_count` — how many nodes the tree had when the code was realized. Node
#   indices belong to the tree they were realized from; when this stops matching,
#   the position is meaningless and the views must show **no** highlight rather
#   than a plausible wrong one,
# - `command` — what the UI has asked for and the bridge has not applied yet:
#   `:none`, `:continue`, `:step`, `:pause` or `:stop`. A gesture writes it; the
#   next `sync_process_debug!` turns it into a runtime write and clears it.
#
# ## The bridge
#
# [`sync_process_debug!`](@ref) is the *only* place the session and a running
# `ProcessTrace` meet, and it goes both ways in one call: UI intent down,
# position up. Call it **from the editor's refresh hook, never from a cell** —
# it writes document cells, and the rule that only the editor's own task does
# that is what makes the threading model safe (an embedder's own refresh
# hook is the precedent). Pause latency is one refresh, which buys a
# design with no locks and no races.
using ..KernelModule
using ..PlatformModule



@document struct ProcessDebugSession <: ProcessDocument
    status::Symbol = :detached
    node::Int = 0
    previous::Int = 0
    step_count::Int = 0
    breakpoints::CellVector = CellVector()
    locals::Any = nothing
    node_count::Int = 0
    command::Symbol = :none
    current::Any = nothing
    previous_document::Any = nothing
end

DomainModule.insertable(::Type{ProcessDebugSession}) = false

"""
    is_stale(session, model) -> Bool

Whether `session`'s indices still describe `model`. A structural edit while a
realization is attached invalidates every index after the edit; editing an
embedded Julia expression does not, which is why the node *count* is the stamp.
"""
is_stale(session::ProcessDebugSession, model) =
    session.node_count != 0 && session.node_count != length(process_nodes(model))

"Whether execution should stop at `node`, compared by identity."
has_breakpoint(session::ProcessDebugSession, node) =
    node !== nothing && any(b -> b === node, session.breakpoints)

"""
    toggle_breakpoint!(session, node) -> Bool

Add or remove a breakpoint on `node`; returns whether it is now set.
"""
function toggle_breakpoint!(session::ProcessDebugSession, node)
    node === nothing && return false
    for (position, value) in enumerate(session.breakpoints)
        if value === node
            deleteat!(session.breakpoints, position)
            return false
        end
    end
    push!(session.breakpoints, node)
    true
end

"""
    set_process_position!(session, model; node, previous) -> session

Move the session to node index `node`, coming from `previous`, resolving both
against `model`. The only place the index and document representations of a
position are written, so a view reading either sees the same thing. An index
naming nothing (0, out of range, a node that has since moved) resolves to
`nothing`, which every view draws as no highlight at all.
"""
function set_process_position!(session::ProcessDebugSession, model; node, previous)
    session.node = Int(node)
    session.previous = Int(previous)
    session.current = model === nothing ? nothing : find_node_at_index(model, Int(node))
    session.previous_document = model === nothing ? nothing : find_node_at_index(model, Int(previous))
    session
end

"""
    sync_process_debug!(session, trace, model = nothing) -> session

Carry UI intent down into the running process and its position back up. One
call, both directions, from the refresh hook.

Down: the breakpoint set, and whatever `session.command` asks for (which is
cleared once applied, so a command is obeyed once). Up: `node`, `previous`,
`step_count`, `locals` and the derived `status`.

When `model` is given and the tree has changed shape since realization, the
session goes `:stale` and its position is cleared instead of updated — every
index now means a different node, and a plausible wrong highlight is worse
than none.
"""
function sync_process_debug!(session::ProcessDebugSession, trace::ProcessTrace,
                             model = nothing)
    # Documents down here, indices from here on: the runtime speaks positions,
    # and only the bridge knows the tree well enough to translate.
    model === nothing ||
        set_process_breakpoints!(trace, Int[get_node_index(model, b) for b in session.breakpoints])

    command = session.command
    if command !== :none
        if command === :pause
            pause_process!(trace)
        elseif command === :stop
            stop_process!(trace)
        elseif command === :step
            resume_process!(trace, :step)
        elseif command === :continue
            resume_process!(trace, :run)
        end
        session.command = :none
    end

    if model !== nothing && is_stale(session, model)
        session.status = :stale
        set_process_position!(session, model; node = 0, previous = 0)
        return session
    end

    set_process_position!(session, model; node = trace.node, previous = trace.previous)
    session.step_count = trace.step_count
    session.locals = trace.locals
    session.status = trace.finished ? :finished : trace.paused ? :paused : :running
    session
end

"""
    detach_process_debug!(session) -> session

Forget a run: no position, no status, no staleness stamp. The breakpoints stay
— they belong to the author, not to the run.
"""
function detach_process_debug!(session::ProcessDebugSession)
    session.status = :detached
    set_process_position!(session, nothing; node = 0, previous = 0)
    session.step_count = 0
    session.locals = nothing
    session.node_count = 0
    session.command = :none
    session
end
