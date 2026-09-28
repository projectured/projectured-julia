# Fragment of `ProjecturedKernelExample` — rankings of a search compared on the
# same questions: by words, by meaning, and by a classifier that reads the
# question, its context and each candidate together.
#
# `plan/pending/a-classifier-ranks-the-search.md` says which comparison each
# number serves.

"""
    SearchQuestion

What a question of a ranking asks:

- `sentence`: what the model would search with, in the words of a person;
- `context`: what the question is asked in, such as the request of the person
  and what the window holds; empty for none;
- `expected`: the names, or the guides, that the answer needs, every one of them;
- `kind`: the corpus it is in, `:api` or `:guide`;
- `source`: where the question comes from, such as `:scale`, `:study`, `:pair`
  or `:log`, so a report can count each group apart.
"""
const SearchQuestion = NamedTuple{(:sentence, :context, :expected, :kind, :source),
                                  Tuple{String,String,Vector{String},Symbol,Symbol}}

"""
    make_search_question(question::ScaleQuestion) -> SearchQuestion

The question of a scale corpus as a question of a ranking: no context, and its
one expected name.
"""
make_search_question(question::ScaleQuestion) =
    SearchQuestion((question.sentence, "", String[question.expected], question.kind, :scale))

# ═══════════════════════════════════════════════════════════════════════
# The text of a candidate
# ═══════════════════════════════════════════════════════════════════════

# The longest documentation a candidate shows a classifier, in characters.
const _CANDIDATE_DOCUMENTATION_LIMIT = 1500

"""
    make_candidate_text(entry; call_sites = "") -> String

What a classifier reads of one entry: its name, its kind, its signature, its
documentation cut at 1,500 characters, and the `call_sites` as
[`format_call_sites`](@ref) writes them, when there are any.
"""
function make_candidate_text(entry; call_sites::AbstractString = "")
    io = IOBuffer()
    println(io, "name: ", entry.qualname)
    println(io, "kind: ", entry.kind)
    isempty(entry.signature) || println(io, "signature: ", entry.signature)
    documentation = first(entry.full, _CANDIDATE_DOCUMENTATION_LIMIT)
    println(io, "documentation:\n", isempty(documentation) ? "(none)" : documentation)
    isempty(call_sites) || print(io, "calls:\n", call_sites)
    String(rstrip(String(take!(io))))
end

# The text a meaning vector reads of one entry: the text of the search, with the
# call sites after it, cut to the length a vector reads well.
function _make_meaning_candidate_text(entry, call_sites::AbstractString)
    isempty(call_sites) && return ToolModule._get_meaning_text(entry)
    calls = "\n\ncalls:\n" * call_sites
    budget = max(0, ToolModule._MEANING_CHUNK_CHARACTERS - length(calls))
    first(entry.qualname * "\n" * entry.full, budget) * calls
end

# The text a search reads of a question: the sentence, and the context before it
# when the ranking reads the context.
_make_query_text(question::SearchQuestion, with_context::Bool) =
    with_context && !isempty(question.context) ?
        question.context * "\n\n" * question.sentence : question.sentence

# ═══════════════════════════════════════════════════════════════════════
# The rankers
# ═══════════════════════════════════════════════════════════════════════

"""
    SearchRanker(name, rank)

One ranking to compare. `rank(question, entries)` answers the entries best first
(as many as it ranks, not always all of them) and the input tokens a model read
for the answer, 0 for none.
"""
struct SearchRanker
    name::String
    rank::Function
end

"""
    make_word_ranker(; context = false) -> SearchRanker

The ranking by words that a search by description uses: whole words and rare
words first. With `context`, the words of the context count too.
"""
make_word_ranker(; context::Bool = false) =
    SearchRanker(context ? "words, context" : "words",
                 (question, entries) -> begin
                     query = ToolModule._DescriptionQuery(_make_query_text(question, context))
                     ([entry for (_, entry) in ToolModule._rank_api_entries(query, entries)], 0)
                 end)

"""
    make_meaning_ranker(model; call_sites = nothing, context = false, vectors = Dict())
        -> SearchRanker

The ranking by meaning vectors of `model`, a `MeaningModel`. With `call_sites`, a
map from the qualified name of an entry to its call sites as text, the vector of
an entry reads them after its documentation. With `context`, the vector of the
question reads the context before the sentence. `vectors` keeps every vector by
its text, so two rankers and two runs share them.
"""
function make_meaning_ranker(model; call_sites = nothing, context::Bool = false,
                             vectors::Dict{String,Vector{Float32}} = Dict{String,Vector{Float32}}())
    name = "meaning" * (call_sites === nothing ? "" : ", call sites") * (context ? ", context" : "")
    SearchRanker(name, (question, entries) -> begin
        texts = String[_make_meaning_candidate_text(entry,
                           call_sites === nothing ? "" : get(call_sites, entry.qualname, ""))
                       for entry in entries]
        _compute_missing_vectors!(vectors, model, texts)
        query = only(ToolModule._normalize_meaning_columns(
            model.compute([_make_query_text(question, context)], :query), 1))
        scores = Float32[ToolModule._compute_meaning_dot(query, vectors[text]) for text in texts]
        (entries[sortperm(scores; rev = true, alg = MergeSort)], 0)
    end)
end

function _compute_missing_vectors!(vectors::Dict{String,Vector{Float32}}, model, texts)
    missing_texts = unique(String[text for text in texts if !haskey(vectors, text)])
    for batch in Iterators.partition(missing_texts, ToolModule._MEANING_BATCH_SIZE)
        computed = ToolModule._normalize_meaning_columns(model.compute(collect(batch), :document),
                                                         length(batch))
        for (text, vector) in zip(batch, computed)
            vectors[text] = vector
        end
    end
    vectors
end

"""
    make_classifier_ranker(name, score; first_stage = SearchRanker[], depth = 50,
                           call_sites = nothing, context = true) -> SearchRanker

The ranking by a classifier. `score(question, texts)` answers a probability for
each text, that the entry does what the question asks or a step of it, and the
input tokens it read; `texts` are the entries as [`make_candidate_text`](@ref)
writes them, with their `call_sites` when a map of them is given. The question
reaches `score` whole, and the `context` flag says whether the classifier may
read its context.

The candidates are the first `depth` entries of each ranker of `first_stage`, and
every entry when `first_stage` is empty. An entry that no first stage offered is
not in the answer.
"""
function make_classifier_ranker(name::AbstractString, score::Function;
                                first_stage::Vector{SearchRanker} = SearchRanker[],
                                depth::Int = 50, call_sites = nothing, context::Bool = true)
    SearchRanker(String(name), (question, entries) -> begin
        candidates = if isempty(first_stage)
            entries
        else
            pool = Dict{String,Any}()
            order = String[]
            for ranker in first_stage, entry in first(first(ranker.rank(question, entries)), depth)
                haskey(pool, entry.qualname) && continue
                pool[entry.qualname] = entry
                push!(order, entry.qualname)
            end
            [pool[qualname] for qualname in order]
        end
        texts = String[make_candidate_text(entry; call_sites = call_sites === nothing ? "" :
                                                  get(call_sites, entry.qualname, ""))
                       for entry in candidates]
        asked = context ? question : SearchQuestion((question.sentence, "", question.expected,
                                                     question.kind, question.source))
        probabilities, tokens = score(asked, texts)
        (candidates[sortperm(probabilities; rev = true, alg = MergeSort)], tokens)
    end)
end

# ═══════════════════════════════════════════════════════════════════════
# The measurement
# ═══════════════════════════════════════════════════════════════════════

_get_short_name(qualname::AbstractString) = String(last(split(qualname, '.')))

# The place of each expected name among the answer, 0 where it is not there.
function _get_expected_ranks(question::SearchQuestion, ranked)
    names = [_get_short_name(entry.qualname) for entry in ranked]
    Int[something(findfirst(==(expected), names), 0) for expected in question.expected]
end

# The best place of any expected name, 0 when none is there.
_get_best_rank(ranks::Vector{Int}) = (found = filter(>(0), ranks); isempty(found) ? 0 : minimum(found))

"""
    measure_search_rankings(; entries, questions, rankers, io = stdout) -> Vector

Ask every question of `questions` of every ranker of `rankers`, over `entries`,
and answer one row per question and ranker: the place of each expected name, the
best of them, the seconds and the tokens. Then print, for each ranker and each
source of question, how many questions put an expected name first, in five, in
eight (what a summary answer shows) and in ten, the mean reciprocal rank, and how
many had every expected name in the first eight; and for each ranker after the
first, how many questions it ranked better, worse and the same as the first.

A ranker that fails on a question is reported, and the question counts as not
answered for it.
"""
function measure_search_rankings(; entries, questions, rankers, io::IO = stdout)
    rows = NamedTuple[]
    for question in questions, ranker in rankers
        ranks = zeros(Int, length(question.expected))
        tokens = 0
        seconds = @elapsed try
            ranked, tokens = ranker.rank(question, entries)
            ranks = _get_expected_ranks(question, ranked)
        catch err
            println(io, "The ranker ", ranker.name, " failed on ", repr(question.sentence), ": ",
                    first(split(sprint(showerror, err), '\n')))
        end
        push!(rows, (sentence = question.sentence, source = question.source,
                     expected = question.expected, ranker = ranker.name, ranks = ranks,
                     best = _get_best_rank(ranks), seconds = seconds, tokens = tokens))
    end
    _print_ranking_table(io, rows, [ranker.name for ranker in rankers])
    rows
end

function _describe_ranking_quality(rows)
    total = length(rows)
    total == 0 && return "no question"
    inside(n) = count(row -> 1 <= row.best <= n, rows)
    reciprocal = sum(row.best == 0 ? 0.0 : 1 / row.best for row in rows; init = 0.0) / total
    every = count(row -> all(rank -> 1 <= rank <= 8, row.ranks), rows)
    string(inside(1), " / ", inside(5), " / ", inside(8), " / ", inside(10), " of ", total,
           "; reciprocal ", round(reciprocal; digits = 2), "; all in eight ", every)
end

function _print_ranking_table(io::IO, rows, names)
    println(io, "first / five / eight / ten; mean reciprocal rank of the best; questions with every name in eight")
    for source in unique(row.source for row in rows)
        println(io, "\n", source, ":")
        for name in names
            mine = [row for row in rows if row.source === source && row.ranker == name]
            println(io, "  ", rpad(name, 44), _describe_ranking_quality(mine))
        end
    end
    length(names) < 2 && return
    println(io, "\nagainst ", names[1], ", per question (better / worse / same):")
    base = Dict((row.sentence, row.source, join(row.expected, ",")) => row.best
                for row in rows if row.ranker == names[1])
    placed(rank) = rank == 0 ? typemax(Int) : rank
    for name in names[2:end]
        better = worse = same = 0
        for row in rows
            row.ranker == name || continue
            first_best = base[(row.sentence, row.source, join(row.expected, ","))]
            placed(row.best) < placed(first_best) ? (better += 1) :
            placed(row.best) > placed(first_best) ? (worse += 1) : (same += 1)
        end
        seconds = sum(row.seconds for row in rows if row.ranker == name)
        tokens = sum(row.tokens for row in rows if row.ranker == name)
        println(io, "  ", rpad(name, 44), better, " / ", worse, " / ", same,
                "; ", round(seconds; digits = 1), " s, ", tokens, " tokens")
    end
end
