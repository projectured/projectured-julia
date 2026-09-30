# Fragment of `ChartModule` — `ChartSampleReferenceStep`, the reference step
# that names one sample of a chart series, and its reference-layer seams.

@cell_struct struct ChartSampleReferenceStep <: ReferenceStep
    index::Int
end

ReferenceModule.get_reference_step_kind(::ChartSampleReferenceStep) = :structural

Base.:(==)(a::ChartSampleReferenceStep, b::ChartSampleReferenceStep) = a.index == b.index
Base.hash(s::ChartSampleReferenceStep, h::UInt) =
    hash(s.index, hash(:ChartSampleReferenceStep, h))

Base.show(io::IO, s::ChartSampleReferenceStep) = print(io, "sample(", s.index, ")")

# ── DSL registrations ──────────────────────────────────────────────────────

ReferenceModule.build_reference_step(::Val{:sample}, iex) =
    :($(GlobalRef(ChartModule, :ChartSampleReferenceStep))(Int($iex)))

function ReferenceModule.match_reference_step(::Val{:sample}, hex, argpats, rest_success, bound,
                                              gen_value_match, gen_path_match)
    inner, bound1 = gen_value_match(:($hex.index), argpats[1], rest_success, bound)
    ex = quote
        if $hex isa $(GlobalRef(ChartModule, :ChartSampleReferenceStep))
            $inner
        else
            _NO_MATCH
        end
    end
    return ex, bound1
end
