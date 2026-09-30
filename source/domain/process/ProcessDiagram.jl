# Fragment of `ProcessModule`.
#
# The flowchart's **presentation document** — what a process looks like on
# screen, as opposed to what it is.
#
# `ProcessDiagram` is projection output (`ProcessToProcessDiagram` builds it once
# and keeps its identity across reprints, exactly as `ChartToChartPlot` does with
# `ChartPlot` and `FsmToFsmDiagram` with `FsmDiagram`), so nothing here is
# document content and nothing here serializes.
#
# Two fields:
#
# - `model` — the `ProcessModel` being drawn,
# - `session` — the `ProcessDebugSession` whose cells the live overlay reads, or
#   `nothing` when nothing is attached. A driver takes the diagram's handle at
#   projection setup and keeps writing that one session for the rest of a run,
#   which is why the diagram's identity has to hold.
#
# `ProcessTerminal` is the other presentation-only type: the start and stop
# ovals a flowchart draws. They are **picture, not semantics** — the document
# tree has no node behind them, which is why they live here rather than in
# `ProcessModule`, and why they are opted out of the insertion candidates.
using ..KernelModule
using ..PlatformModule



@document struct ProcessDiagram <: ProcessDocument
    model::Any
    session::Any = nothing
end

"""
A flowchart terminator: `:start` where control enters the process, `:stop`
where it leaves. Synthesized by the diagram stage — no document node stands
behind one, so it is never a completion candidate and never carries a
selection that maps back to content.
"""
@document struct ProcessTerminal <: ProcessDocument
    kind::Symbol = :start
end

"""
An arrow's caption — `yes`/`no` out of a decision, `next`/`done` out of a
`foreach`. Synthesized by the diagram stage for the same reason
`ProcessTerminal` is: the document holds no edges, so it holds no captions.
"""
@document struct ProcessEdgeLabel <: ProcessDocument
    text::String = ""
end

# Single-argument forms the macro does not emit for a fully-defaulted struct
# (it generates the keyword form and the all-fields positional one). Typed, so
# they stay distinct from the generated `::Any, ::Any` arity.
ProcessTerminal(kind::Symbol) = ProcessTerminal(Cell(kind), Cell(nothing))
ProcessEdgeLabel(text::AbstractString) = ProcessEdgeLabel(Cell(String(text)), Cell(nothing))

DomainModule.insertable(::Type{ProcessTerminal}) = false
DomainModule.insertable(::Type{ProcessEdgeLabel}) = false
DomainModule.insertable(::Type{ProcessDiagram}) = false
