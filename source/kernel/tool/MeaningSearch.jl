# Fragment of `ToolModule` — search by meaning: how a description is ranked by
# what it means, and how that rank joins the rank of its words.

# The first line of a description search that the words alone ranked.
const _NO_MEANING_MODEL_NOTE =
    "This editor has no meaning model, so the words of the description were " *
    "searched as keywords."

# The entries a description means, best first, and the note that says why there
# is no such ranking. Exactly one of the two is `nothing`.
_rank_api_entries_by_meaning(query::_DescriptionQuery, entries, meaning_model::Nothing) =
    (nothing, _NO_MEANING_MODEL_NOTE)

# The same for guide sections.
_rank_guide_sections_by_meaning(query::_DescriptionQuery, sections, meaning_model::Nothing) =
    (nothing, _NO_MEANING_MODEL_NOTE)

# **Reciprocal rank fusion.** An item's score is the sum, over the rankings it is
# in, of `1 / (_FUSION_RANK_OFFSET + its rank there)`, and each ranking counts its
# first `_FUSED_RANK_COUNT` items. It needs no calibration between a count of
# words and a cosine, and an item that only one ranking finds still ranks.
const _FUSION_RANK_OFFSET = 60
const _FUSED_RANK_COUNT = 50

function _fuse_rankings(first_ranking::Vector{T}, second_ranking::Vector{T}) where {T}
    scores = Dict{T,Float64}()
    order = T[]
    for ranking in (first_ranking, second_ranking)
        for (rank, item) in enumerate(Iterators.take(ranking, _FUSED_RANK_COUNT))
            haskey(scores, item) || push!(order, item)
            scores[item] = get(scores, item, 0.0) + 1 / (_FUSION_RANK_OFFSET + rank)
        end
    end
    # A tie keeps the order the rankings gave, the first ranking before the second.
    sort!(order; by = item -> -scores[item], alg = MergeSort)
end
