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
        _score_candidates(score, question, candidates, call_sites, context)
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
            reason = replace(strip(sprint(showerror, err)), r"\s*\n\s*" => " / ")
            println(io, "The ranker ", ranker.name, " failed on ", repr(question.sentence), ": ",
                    first(reason, 300))
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

# ═══════════════════════════════════════════════════════════════════════
# The shapes that choose before they score
# ═══════════════════════════════════════════════════════════════════════

# The most options one choice holds.
const _CHOICE_OPTION_LIMIT = 255

# The short line of an entry that a choice shows: its qualified name and the
# first sentence of its documentation.
_make_choice_line(entry) =
    isempty(entry.summary) ? entry.qualname : entry.qualname * ": " * first(entry.summary, 100)

# The entries in the order of `probabilities`, best first.
_order_by(entries, probabilities) =
    entries[sortperm(probabilities; rev = true, alg = MergeSort)]

# Score `candidates` with `score`, and answer them best first, and the tokens.
function _score_candidates(score::Function, question::SearchQuestion, candidates, call_sites,
                           context::Bool)
    isempty(candidates) && return (candidates, 0)
    texts = String[make_candidate_text(entry; call_sites = call_sites === nothing ? "" :
                                              get(call_sites, entry.qualname, ""))
                   for entry in candidates]
    asked = context ? question : SearchQuestion((question.sentence, "", question.expected,
                                                 question.kind, question.source))
    probabilities, tokens = score(asked, texts)
    (_order_by(candidates, probabilities), tokens)
end

"""
    make_cascade_ranker(name, choose, score; keep = 3, call_sites = nothing,
                        context = true) -> SearchRanker

The shape of a choice and then a score. `choose(question, options)` answers a
probability for each option of one choice, and the tokens it read; an option is
an identifier and a short line. The entries go to the choice in groups of 255,
and the `keep` best of each group go to `score`, with their full text. The
probabilities of one choice add up to one within its group, so they are not
compared across groups: each group gives its best few.
"""
function make_cascade_ranker(name::AbstractString, choose::Function, score::Function;
                             keep::Int = 3, call_sites = nothing, context::Bool = true)
    SearchRanker(String(name), (question, entries) -> begin
        tokens = 0
        kept = Any[]
        for group in Iterators.partition(entries, _CHOICE_OPTION_LIMIT)
            options = [(entry.qualname, _make_choice_line(entry)) for entry in group]
            probabilities, used = choose(question, options)
            tokens += used
            append!(kept, first(_order_by(collect(group), probabilities), keep))
        end
        ranked, used = _score_candidates(score, question, kept, call_sites, context)
        (ranked, tokens + used)
    end)
end

"""
    make_tree_ranker(name, choose, score; package_of, descriptions, beam = 3, keep = 20,
                     call_sites = nothing, context = true) -> SearchRanker

The owner's divide and conquer: a choice over the packages, then over the modules
of each package kept, then over the names of each module kept, and a score of
the `keep` best names with their full text. `package_of` maps the name of a
module to the name of its package, and `descriptions` maps a package or a module
to the line a choice shows of it. A path scores as the geometric mean of the
probabilities along it, and each level keeps the `beam` best paths, so a
doubtful choice high up can be repaired lower down. A module of more than 255
names is chosen from in groups.
"""
function make_tree_ranker(name::AbstractString, choose::Function, score::Function;
                          package_of::Dict{String,String}, descriptions::Dict{String,String},
                          beam::Int = 3, keep::Int = 20, call_sites = nothing,
                          context::Bool = true)
    SearchRanker(String(name), (question, entries) -> begin
        tokens = 0
        # The entries of each module, and the modules of each package.
        by_module = Dict{String,Vector{Any}}()
        for entry in entries
            entry.kind == "module" && continue
            push!(get!(() -> Any[], by_module, String(first(split(entry.qualname, '.')))), entry)
        end
        by_package = Dict{String,Vector{String}}()
        for module_name in sort(collect(keys(by_module)))
            push!(get!(() -> String[], by_package, get(package_of, module_name, module_name)),
                  module_name)
        end
        describe(key) = get(descriptions, key, key)
        # A path is its probabilities and its last node.
        function choose_among(keys)
            length(keys) == 1 && return [1.0]
            probabilities, used = choose(question, [(key, describe(key)) for key in keys])
            tokens += used
            probabilities
        end
        mean(path) = prod(path) ^ (1 / length(path))
        packages = sort(collect(keys(by_package)))
        paths = [([p], package) for (p, package) in zip(choose_among(packages), packages)]
        paths = first(sort(paths; by = path -> -mean(first(path))), beam)
        module_paths = Tuple{Vector{Float64},String}[]
        for (probabilities, package) in paths
            modules = by_package[package]
            for (p, module_name) in zip(choose_among(modules), modules)
                push!(module_paths, (vcat(probabilities, p), module_name))
            end
        end
        module_paths = first(sort(module_paths; by = path -> -mean(first(path))), beam)
        entry_paths = Tuple{Vector{Float64},Any}[]
        for (probabilities, module_name) in module_paths
            for group in Iterators.partition(by_module[module_name], _CHOICE_OPTION_LIMIT)
                group = collect(group)
                options = [(entry.qualname, _make_choice_line(entry)) for entry in group]
                chosen = length(group) == 1 ? [1.0] : begin
                    found, used = choose(question, options)
                    tokens += used
                    found
                end
                for (p, entry) in zip(chosen, group)
                    push!(entry_paths, (vcat(probabilities, p), entry))
                end
            end
        end
        kept = [last(path) for path in first(sort(entry_paths; by = path -> -mean(first(path))), keep)]
        ranked, used = _score_candidates(score, question, kept, call_sites, context)
        (ranked, tokens + used)
    end)
end
