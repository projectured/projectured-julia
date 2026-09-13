# ──────────────────────────────────────────────────────────────────────────
# Folded in from SequenceChartRowReferenceStep.jl.
#
# The `SequenceChartRowReferenceStep` step type — a reference step naming one row
# of a sequence chart's columnar table.
#
# The event and arrow tables hold their data as whole column vectors precisely so
# that a hundred thousand occurrences do not become a hundred thousand reactive
# cells, which leaves nothing for a reference to descend *into*: there is no
# per-row document to carry a selection. So a row is addressed the way a chart
# sample and a pixel offset already are, with a `:structural` step naming a
# position within an otherwise opaque leaf. The selection still terminates at a
# real `Document` — the table.
#
# Registers its own `.row(k)` entry with the kernel `@reference` /
# `@reference_case` DSLs through the reference layer's `build_reference_step` /
# `match_reference_step` seams. What a row *evaluates* to depends on which table
# holds it, so the sequence chart domain supplies `evaluate_reference_step` rather
# than this file guessing.
using ..CellModule
using ..CellStructModule
using ..ReferenceModule


"""
    SequenceChartRowReferenceStep(index)

References the `index`-th row of a sequence chart table — an occurrence of the
event table, an arrow of the arrow table, a sample of a state band. 1-based, like
every other index in the reference vocabulary.
"""
@cell_struct struct SequenceChartRowReferenceStep <: ReferenceStep
    index::Int
end

ReferenceModule.get_reference_step_kind(::SequenceChartRowReferenceStep) = :structural

Base.:(==)(a::SequenceChartRowReferenceStep, b::SequenceChartRowReferenceStep) =
    a.index == b.index

Base.show(io::IO, s::SequenceChartRowReferenceStep) = print(io, "row(", s.index, ")")

# ── DSL registrations ──────────────────────────────────────────────────────

ReferenceModule.build_reference_step(::Val{:row}, iex) =
    :($(GlobalRef(SequenceChartModule, :SequenceChartRowReferenceStep))(Int($iex)))

function ReferenceModule.match_reference_step(::Val{:row}, hex, argpats, rest_success, bound,
                                              gen_value_match, gen_path_match)
    inner, bound1 = gen_value_match(:($hex.index), argpats[1], rest_success, bound)
    ex = quote
        if $hex isa $(GlobalRef(SequenceChartModule, :SequenceChartRowReferenceStep))
            $inner
        else
            _nomatch
        end
    end
    return ex, bound1
end
