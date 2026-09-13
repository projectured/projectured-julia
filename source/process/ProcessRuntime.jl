# ──────────────────────────────────────────────────────────────────────────
# Folded in from ProcessRuntime.jl.
#
# The probe runtime realized code calls — **plain Julia**. No `@document`, no
# cells, no ProjecturEd: a realized process must stay runnable outside the
# editor, and a runtime that could touch a document would make that untrue (and
# would let a probe write a document cell from the process's own task, which is
# the one thing the debug design forbids).
#
# The `Fsm` runtime an embedder supplies plays exactly this role for
# `FsmToJuliaCode`,
# and like it, **the protocol is the contract, not this file**: an embedder that
# wants its own recording or its own scheduler implements `process_at!` over its
# own trace type and realized code neither knows nor cares.
#
# ## The protocol
#
# Realized code carries one extra statement per node:
#
# ```julia
# process_at!(trace, 7)              # instrumentation = :position
# process_at!(trace, 7, (; x, y))    # instrumentation = :locals
# ```
#
# `trace` is the realized function's last parameter and defaults to `nothing`,
# and `process_at!(::Nothing, …)` is a no-op — so instrumented code runs
# standalone at full speed with no debug machinery attached.
#
# A probe does three things, in this order: it records where execution is, it
# calls the `on_step` hook if there is one, and then — only if the UI has asked
# for it — it **blocks** until the UI resumes it. Blocking is what makes a
# breakpoint a breakpoint, and it blocks the *calling task*: run a realized
# process on its own `Task` (see `start_process`) or the caller stops with it.
# A process realized into a simulation should run at `:none`, or with `:run`
# mode and no breakpoints, for exactly that reason.
"""
Thrown inside a realized process when the UI asks it to stop. The runner
catches it; nothing else should.
"""
struct ProcessStoppedException <: Exception end

"""
    ProcessTrace(; mode = :run, breakpoints = Set{Int}(), on_step = nothing)

Where a realized process is, as plain mutable data. The editor never reads
this directly — `sync_process_debug!` copies it into the session document from
the refresh hook, so document cells are only ever written by the editor's own
task.

- `node` / `previous` — node indices in the domain's position vocabulary
  (`process_nodes`), the second being what lets the diagram derive which arrow
  was just taken,
- `step_count` — probes reached so far,
- `locals` — the `NamedTuple` from the last `:locals` probe, or `nothing`,
- `mode` — `:run`, `:step` (stop at every probe), `:pause` (stop at the next
  one) or `:stop` (unwind),
- `breakpoints` — node indices to stop at,
- `resume` — the channel the UI's "go" arrives on,
- `on_step` — optional `(trace, index) -> nothing`, called after every probe;
  statistics and tracing hang off it rather than being tangled into the
  protocol (the `Fsm.on_transition` precedent),
- `paused` / `finished` — what the runner and the bridge read to report status.
"""
mutable struct ProcessTrace
    node::Int
    previous::Int
    step_count::Int
    locals::Any
    mode::Symbol
    breakpoints::Set{Int}
    resume::Channel{Symbol}
    on_step::Any
    paused::Bool
    finished::Bool
end

ProcessTrace(; mode::Symbol = :run, breakpoints = Set{Int}(), on_step = nothing) =
    ProcessTrace(0, 0, 0, nothing, mode, Set{Int}(breakpoints),
                 Channel{Symbol}(1), on_step, false, false)

"""
    process_at!(trace, index, locals = nothing)

Record that execution reached node `index`, then stop there if the UI asked
to. The no-op method for `nothing` is what lets instrumented code run with no
debugger attached.
"""
process_at!(::Nothing, index, locals = nothing) = nothing

function process_at!(trace::ProcessTrace, index::Integer, locals = nothing)
    trace.previous = trace.node
    trace.node = Int(index)
    trace.step_count += 1
    trace.locals = locals
    hook = trace.on_step
    hook === nothing || hook(trace, Int(index))
    trace.mode === :stop && throw(ProcessStoppedException())
    if trace.mode === :step || trace.mode === :pause || Int(index) in trace.breakpoints
        trace.paused = true
        command = take!(trace.resume)          # blocks until the UI says go
        trace.paused = false
        command === :stop && (trace.mode = :stop; throw(ProcessStoppedException()))
        trace.mode = command                   # :run continues, :step stops again
    end
    nothing
end

"""
    resume_process!(trace, mode = :run)

Let a stopped process go: `:run` until the next breakpoint, `:step` to the
next node. Does nothing when the process is not stopped, so a stray resume
cannot bank a "go" that skips the next breakpoint.
"""
function resume_process!(trace::ProcessTrace, mode::Symbol = :run)
    trace.paused || return nothing
    put!(trace.resume, mode)
    nothing
end

"Stop at the next probe."
pause_process!(trace::ProcessTrace) = (trace.mode = :pause; nothing)

"""
    stop_process!(trace)

Unwind the process at its next probe — and let a stopped one reach that probe,
which is why this also releases the channel.
"""
function stop_process!(trace::ProcessTrace)
    trace.mode = :stop
    trace.paused && put!(trace.resume, :stop)
    nothing
end

"Replace the breakpoint set."
set_process_breakpoints!(trace::ProcessTrace, indices) =
    (trace.breakpoints = Set{Int}(Int(i) for i in indices); nothing)

is_process_paused(trace::ProcessTrace) = trace.paused
is_process_finished(trace::ProcessTrace) = trace.finished
