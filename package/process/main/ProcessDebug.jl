"""
    ProcessDebugModule

Running a realized process **under the debugger**: realize it with probes,
load it, start it on its own task, and hand back the trace the bridge reads.

This is the one place the three halves of the debug design meet — the
realization (`ProcessToJuliaCode`), the plain-Julia runtime
(`ProcessRuntime`), and the session document (`ProcessDebugSession`) — and it
is deliberately thin, because each of them is useful without it: an embedder
that realizes into its own host and drives its own trace uses none of this.

The process runs on a `Task`. That is what makes a breakpoint bearable: the
probe blocks its own task while the editor keeps refreshing, and the refresh
hook's `sync_process_debug!` is what eventually lets it go.

Realized code calls `process_at!` by name, so the module it is loaded into
must have the runtime in scope. `start_process` arranges that for the module
it creates; a caller supplying its own `context` module gets the same `using`
injected, and everything else the process calls — the functions its steps
name — has to be there already.
"""
module ProcessDebugModule

import ..ProcessModule: ProcessModel, process_nodes
import ..ProcessDebugSessionModule: ProcessDebugSession, sync_process_debug!
import ..ProcessRuntimeModule: ProcessTrace, ProcessStopped
import ..ProcessToJuliaCodeModule: realize_process_text

export start_process, realize_into, ProcessRun

"""
A started process: the `task` running it, the `trace` the bridge reads, the
`context` module it was loaded into, and the `model` it came from (which is
what the staleness check compares against).
"""
struct ProcessRun
    model::Any
    trace::ProcessTrace
    task::Task
    context::Module
end

"""
    realize_into(model, context; instrumentation = :position) -> Function

Realize `model` and load it into `context`, returning the function. The
runtime is brought into scope first, so the probes resolve.
"""
function realize_into(model::ProcessModel, context::Module;
                      instrumentation::Symbol = :position)
    Base.include_string(context,
        "using ProjecturedProcess.ProcessRuntimeModule: process_at!, ProcessTrace\n")
    Base.include_string(context, realize_process_text(model; instrumentation = instrumentation))
    Base.invokelatest(getfield, context, Symbol(model.name))
end

"""
    start_process(model, arguments...; kwargs...) -> ProcessRun

Realize `model`, start it on its own task, and return the handle. The process
begins running immediately unless `mode = :step` or a breakpoint stops it.

- `context` — the module the code is loaded into, and where the functions the
  process calls must live. A fresh anonymous module by default, which is only
  enough for a process that calls nothing.
- `instrumentation` — `:position` (the default) or `:locals`; `:none` starts a
  process that reports nothing, which the debugger cannot follow.
- `mode` — `:run` or `:step` (stop at the very first node).
- `breakpoints` — node indices to stop at.
- `session` — stamped with `node_count` so staleness can be detected later.

The task never throws `ProcessStopped` outward: a stopped process is a normal
outcome of debugging, not a failure.
"""
function start_process(model::ProcessModel, arguments...;
                       context::Module = Module(:ProcessRunContext),
                       instrumentation::Symbol = :position,
                       mode::Symbol = :run,
                       breakpoints = Int[],
                       session::Union{ProcessDebugSession,Nothing} = nothing)
    f = realize_into(model, context; instrumentation = instrumentation)
    trace = ProcessTrace(; mode = mode, breakpoints = breakpoints)
    if session !== nothing
        session.node_count = length(process_nodes(model))
        session.status = :running
        session.node = 0
        session.previous = 0
        session.step_count = 0
    end
    task = @async begin
        try
            Base.invokelatest(f, arguments..., trace)
        catch exception
            exception isa ProcessStopped ? nothing : rethrow()
        finally
            trace.finished = true
        end
    end
    ProcessRun(model, trace, task, context)
end

end # module
