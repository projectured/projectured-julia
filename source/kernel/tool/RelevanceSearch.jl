# Fragment of `ToolModule` — search by relevance: a classifier reads the
# description, what it is asked in, and each thing the search could find, all
# together, and ranks them by how likely each does what was asked.

# ═══════════════════════════════════════════════════════════════════════
# The shapes of a ranking by relevance
# ═══════════════════════════════════════════════════════════════════════
#
# **Every entry is scored when there are few, and chosen from when there are
# many.** A score reads the whole text of an entry, and one request scores a
# window's hundred names in about a second. At thousands of names, a choice among
# 255 short lines at a time keeps the best few of each group, and only those are
# scored. Measured on the 5,187 entries of an IDE, 2026-09-28: this cascade put
# 54 of 60 questions' names in the first ten, where the meaning vectors put 30
# and a score of the first fifty of words and meaning put 43.
# `plan/done/a-classifier-ranks-the-search.md` holds the numbers.

# The most options one choice holds.
const _RELEVANCE_CHOICE_LIMIT = 255

# How many of each group of a choice go on to be scored.
const _RELEVANCE_CHOICE_KEEP = 3

# How many choices are asked at once.
const _RELEVANCE_PARALLEL_CHOICES = 8

# How many of each first ranking a search of the guides gives the relevance
# model. The guides are cut into sections the meaning vectors already rank well,
# so the model orders their first hits rather than choosing among all.
const _RELEVANCE_POOL_DEPTH = 50

# The longest text of one thing the relevance model reads, in characters.
const _RELEVANCE_TEXT_LIMIT = 1500

# What the relevance model reads of an entry: its name, its kind, its signature
# and its documentation.
function _make_relevance_text(entry::_ApiEntry)
    io = IOBuffer()
    println(io, "name: ", entry.qualname)
    println(io, "kind: ", entry.kind)
    isempty(entry.signature) || println(io, "signature: ", entry.signature)
    print(io, "documentation:\n", isempty(entry.full) ? "(none)" :
                                  first(entry.full, _RELEVANCE_TEXT_LIMIT))
    String(take!(io))
end

# What the relevance model reads of a section of a guide.
_make_relevance_text(section::_GuideSection) =
    "guide: " * section.guide * "\nsection: " * section.heading * "\ntext:\n" *
    first(section.body, _RELEVANCE_TEXT_LIMIT)

# The line of an entry that a choice shows.
_make_relevance_line(entry::_ApiEntry) =
    isempty(entry.summary) ? entry.qualname : entry.qualname * ": " * first(entry.summary, 100)

# The first line of a search by description that the relevance model did not
# rank, and why. The line after it says what ranked the hits instead.
_describe_relevance_failure(model::RelevanceModel, reason::AbstractString) =
    "The relevance model $(model.name) failed, so it did not rank these hits. " *
    "The reason: " * reason

_join_notes(first_note, second_note) =
    first_note === nothing ? second_note :
    second_note === nothing ? first_note : first_note * "\n" * second_note

# `things` best first by the probabilities the model scores them with.
function _order_by_relevance(query::_DescriptionQuery, context::String, things,
                             model::RelevanceModel)
    probabilities = model.score(query.text, context, String[_make_relevance_text(thing)
                                                             for thing in things])
    length(probabilities) == length(things) ||
        error("the relevance model answered $(length(probabilities)) scores for $(length(things)) texts")
    things[sortperm(probabilities; rev = true, alg = MergeSort)]
end

# The best few of each group of a choice among `entries`.
function _choose_relevance_candidates(query::_DescriptionQuery, context::String,
                                      entries::Vector{_ApiEntry}, model::RelevanceModel)
    groups = [collect(group) for group in Iterators.partition(entries, _RELEVANCE_CHOICE_LIMIT)]
    kept = asyncmap(groups; ntasks = _RELEVANCE_PARALLEL_CHOICES) do group
        options = [(entry.qualname, _make_relevance_line(entry)) for entry in group]
        probabilities = model.choose(query.text, context, options)
        first(group[sortperm(probabilities; rev = true, alg = MergeSort)], _RELEVANCE_CHOICE_KEEP)
    end
    reduce(vcat, kept; init = _ApiEntry[])
end

# The entries a description asks for, best first, and the note that says why
# there is no such ranking. Exactly one of the two is `nothing`.
function _rank_api_entries_by_relevance(query::_DescriptionQuery, context::String,
                                        entries::Vector{_ApiEntry}, model::RelevanceModel)
    isempty(entries) && return (_ApiEntry[], nothing)
    try
        candidates = length(entries) <= _RELEVANCE_CHOICE_LIMIT ? entries :
                     _choose_relevance_candidates(query, context, entries, model)
        (_order_by_relevance(query, context, candidates, model), nothing)
    catch err
        (nothing, _describe_relevance_failure(model, first(split(sprint(showerror, err), '\n'))))
    end
end

# The first `_RELEVANCE_POOL_DEPTH` sections of each ranking, each once, in the
# order they come.
function _make_relevance_pool(rankings::Vector{_GuideSection}...)
    pool = _GuideSection[]
    seen = Set{Tuple{String,String,String}}()
    for ranking in rankings, section in first(ranking, _RELEVANCE_POOL_DEPTH)
        key = (section.guide, section.heading, section.body)
        key in seen && continue
        push!(seen, key)
        push!(pool, section)
    end
    pool
end

# The sections of `pool` best first by relevance, and the note that says why
# there is no such ranking.
function _rank_guide_sections_by_relevance(query::_DescriptionQuery, context::String,
                                           pool::Vector{_GuideSection}, model::RelevanceModel)
    isempty(pool) && return (_GuideSection[], nothing)
    try
        (_order_by_relevance(query, context, pool, model), nothing)
    catch err
        (nothing, _describe_relevance_failure(model, first(split(sprint(showerror, err), '\n'))))
    end
end

# The context of a search as the text a ranking reads: empty for none.
_get_context_text(context) = context === nothing ? "" : String(strip(string(context)))

# A description with its context before it, as a meaning vector reads it.
_add_query_context(query::_DescriptionQuery, context::AbstractString) =
    isempty(context) ? query : _DescriptionQuery(context * "\n\n" * query.text)
