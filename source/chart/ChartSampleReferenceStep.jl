"""
    ChartSampleReferenceStepModule

The `ChartSampleReferenceStep` step type — a reference step naming one sample
inside a chart series.

A series holds its data as whole column vectors precisely so that a million
samples do not become a million reactive cells, which leaves nothing for a
reference to descend *into*: there is no per-sample document to carry a
selection. So a sample is addressed the way a pixel offset inside a rendered
element already is, with a `:structural` step that names a position within an
otherwise opaque leaf — exactly what `PointReferenceStep` does for graphics
coordinates. The selection still terminates at a real `Document`, the series.

Registers its own `.sample(i)` entry with the kernel `@reference` /
`@reference_case` DSLs through the reference layer's `build_reference_step` /
`match_reference_step` seams. What a sample *evaluates* to depends on the kind
of series holding it, so the chart domain supplies `evaluate_reference_step`
rather than this file guessing.
"""
module ChartSampleReferenceStepModule

using ..CellModule
using ..CellStructModule
using ..ReferenceModule

export ChartSampleReferenceStep

"""
    ChartSampleReferenceStep(index)

References the `index`-th sample of a chart series — a point of a line or
scatter series, a bin of a histogram, a bar of a bar series. 1-based, like every
other index in the reference vocabulary.
"""
@cell_struct struct ChartSampleReferenceStep <: ReferenceStep
    index::Int
end

ReferenceModule.get_reference_step_kind(::ChartSampleReferenceStep) = :structural

Base.:(==)(a::ChartSampleReferenceStep, b::ChartSampleReferenceStep) = a.index == b.index

Base.show(io::IO, s::ChartSampleReferenceStep) = print(io, "sample(", s.index, ")")

# ── DSL registrations ──────────────────────────────────────────────────────

ReferenceModule.build_reference_step(::Val{:sample}, iex) =
    :($(GlobalRef(ChartSampleReferenceStepModule, :ChartSampleReferenceStep))(Int($iex)))

function ReferenceModule.match_reference_step(::Val{:sample}, hex, argpats, rest_success, bound,
                                              gen_value_match, gen_path_match)
    inner, bound1 = gen_value_match(:($hex.index), argpats[1], rest_success, bound)
    ex = quote
        if $hex isa $(GlobalRef(ChartSampleReferenceStepModule, :ChartSampleReferenceStep))
            $inner
        else
            _nomatch
        end
    end
    return ex, bound1
end

end # module
