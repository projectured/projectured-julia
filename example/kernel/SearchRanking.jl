# Fragment of `ProjecturedKernelExample` — rankings of a search compared on the
# same questions: by words, by meaning, and by a classifier that reads the
# question, its context and each candidate together.
#
# `plan/done/a-classifier-ranks-the-search.md` says which comparison each
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
    make_candidate_text(entry; call_sites = "", code = "") -> String

What a classifier reads of one entry: its name, its kind, its signature, its
documentation cut at 1,500 characters, the first lines of its definition as
`code`, and the `call_sites` as [`format_call_sites`](@ref) writes them, each
when there is one.
"""
function make_candidate_text(entry; call_sites::AbstractString = "", code::AbstractString = "")
    io = IOBuffer()
    println(io, "name: ", entry.qualname)
    println(io, "kind: ", entry.kind)
    isempty(entry.signature) || println(io, "signature: ", entry.signature)
    documentation = first(entry.full, _CANDIDATE_DOCUMENTATION_LIMIT)
    println(io, "documentation:\n", isempty(documentation) ? "(none)" : documentation)
    isempty(code) || println(io, "code:\n", code)
    isempty(call_sites) || print(io, "calls:\n", call_sites)
    String(rstrip(String(take!(io))))
end

"""
    make_candidate_text(unit::ToolModule._GuideSection; call_sites = "") -> String

What a classifier reads of a part of a guide: the guide, the heading, and the
text cut at 1,500 characters. A guide has no call sites.
"""
make_candidate_text(unit::ToolModule._GuideSection; call_sites::AbstractString = "",
                    code::AbstractString = "") =
    "guide: " * unit.guide * (isempty(unit.heading) ? "" : "\nsection: " * unit.heading) *
    "\ntext:\n" * first(unit.body, _CANDIDATE_DOCUMENTATION_LIMIT)

# The text a meaning vector reads of one entry: the text of the search, with the
# call sites after it, cut to the length a vector reads well. A part of a guide
# reads as the search reads its first chunk.
_make_meaning_candidate_text(unit::ToolModule._GuideSection, call_sites::AbstractString,
                             code::AbstractString = "") =
    first(ToolModule._get_meaning_texts(unit))

function _make_meaning_candidate_text(entry, call_sites::AbstractString, code::AbstractString = "")
    isempty(call_sites) && isempty(code) && return ToolModule._get_meaning_text(entry)
    after = (isempty(code) ? "" : "\n\ncode:\n" * code) *
            (isempty(call_sites) ? "" : "\n\ncalls:\n" * call_sites)
    budget = max(0, ToolModule._MEANING_CHUNK_CHARACTERS - length(after))
    first(entry.qualname * "\n" * entry.full, budget) * after
end

# The text a search reads of a question: the sentence, and the context before it
# when the ranking reads the context.
_make_query_text(question::SearchQuestion, with_context::Bool) =
    with_context && !isempty(question.context) ?
        question.context * "\n\n" * question.sentence : question.sentence

# ═══════════════════════════════════════════════════════════════════════
# The rankers
# ═══════════════════════════════════════════════════════════════════════

# What tells two units apart, and the call sites of a unit as text.
_get_unit_key(entry::ToolModule._ApiEntry) = entry.qualname
_get_unit_key(unit::ToolModule._GuideSection) =
    unit.guide * "#" * unit.heading * "#" * string(hash(unit.body); base = 16)
_get_unit_call_sites(call_sites, entry::ToolModule._ApiEntry) =
    call_sites === nothing ? "" : get(call_sites, entry.qualname, "")
_get_unit_call_sites(call_sites, unit::ToolModule._GuideSection) = ""
# The code of a unit as text: a map by qualified name, or nothing.
_get_unit_code(code, entry) = code === nothing ? "" : get(code, entry.qualname, "")
_get_unit_code(code, unit::ToolModule._GuideSection) = ""

# The units by their words, as each search ranks its own: an API entry by its
# name and its prose, a part of a guide by its heading and its body.
_rank_units_by_words(query, entries::Vector{ToolModule._ApiEntry}) =
    [entry for (_, entry) in ToolModule._rank_api_entries(query, entries)]
_rank_units_by_words(query, units::Vector{ToolModule._GuideSection}) =
    [unit for (_, unit) in ToolModule._rank_guide_sections(query, units)]

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
                     (_rank_units_by_words(query, entries), 0)
                 end)

"""
    make_meaning_ranker(model; call_sites = nothing, code = nothing, context = false,
                        vectors = Dict()) -> SearchRanker

The ranking by meaning vectors of `model`, a `MeaningModel`. With `call_sites`, a
map from the qualified name of an entry to its call sites as text, the vector of
an entry reads them after its documentation, and with `code`, a map from the
qualified name to the first lines of its definition, the code. With `context`, the vector of the
question reads the context before the sentence. `vectors` keeps every vector by
its text, so two rankers and two runs share them.
"""
function make_meaning_ranker(model; call_sites = nothing, code = nothing, context::Bool = false,
                             vectors::Dict{String,Vector{Float32}} = Dict{String,Vector{Float32}}())
    name = "meaning" * (code === nothing ? "" : ", code") *
           (call_sites === nothing ? "" : ", call sites") * (context ? ", context" : "")
    SearchRanker(name, (question, entries) -> begin
        texts = String[_make_meaning_candidate_text(entry, _get_unit_call_sites(call_sites, entry),
                                                    _get_unit_code(code, entry))
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
                           call_sites = nothing, code = nothing, context = true) -> SearchRanker

The ranking by a classifier. `score(question, texts)` answers a probability for
each text, that the entry does what the question asks or a step of it, and the
input tokens it read; `texts` are the entries as [`make_candidate_text`](@ref)
writes them, with their `call_sites` and their `code` when a map of them is
given. The question
reaches `score` whole, and the `context` flag says whether the classifier may
read its context.

The candidates are the first `depth` entries of each ranker of `first_stage`, and
every entry when `first_stage` is empty. An entry that no first stage offered is
not in the answer.
"""
function make_classifier_ranker(name::AbstractString, score::Function;
                                first_stage::Vector{SearchRanker} = SearchRanker[],
                                depth::Int = 50, call_sites = nothing, code = nothing,
                                context::Bool = true)
    SearchRanker(String(name), (question, entries) -> begin
        candidates = if isempty(first_stage)
            entries
        else
            pool = Dict{String,Any}()
            order = String[]
            for ranker in first_stage, entry in first(first(ranker.rank(question, entries)), depth)
                key = _get_unit_key(entry)
                haskey(pool, key) && continue
                pool[key] = entry
                push!(order, key)
            end
            [pool[key] for key in order]
        end
        _score_candidates(score, question, candidates, call_sites, context; code = code)
    end)
end

# ═══════════════════════════════════════════════════════════════════════
# The measurement
# ═══════════════════════════════════════════════════════════════════════

_get_short_name(qualname::AbstractString) = String(last(split(qualname, '.')))

# The place of each expected name among the answer, 0 where it is not there. A
# guide question names a guide, or a section as `guide#heading`, and its place
# counts guides or sections, each once: the three paragraphs of one section are
# one place. Units of whole guides answer a section question by its guide.
function _get_expected_ranks(question::SearchQuestion, ranked)
    if question.kind === :guide
        sections = any(unit -> !isempty(unit.heading), ranked)
        return Int[_get_guide_rank(expected, ranked, sections) for expected in question.expected]
    end
    names = [_get_short_name(entry.qualname) for entry in ranked]
    Int[something(findfirst(==(expected), names), 0) for expected in question.expected]
end

function _get_guide_rank(expected::AbstractString, ranked, sections::Bool)
    by_section = sections && occursin('#', expected)
    wanted = by_section ? expected : String(first(split(expected, '#')))
    places = unique([by_section ? unit.guide * "#" * unit.heading : unit.guide for unit in ranked])
    something(findfirst(==(wanted), places), 0)
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
_make_choice_line(entry, code::AbstractString = "") =
    !isempty(entry.summary) ? entry.qualname * ": " * first(entry.summary, 100) :
    isempty(code) ? entry.qualname :
    entry.qualname * ": " * first(strip(first(split(code, '\n'))), 100)
_make_choice_line(unit::ToolModule._GuideSection, code::AbstractString = "") =
    unit.guide * (isempty(unit.heading) ? "" : " › " * unit.heading) * ": " *
    first(replace(unit.body, r"\s+" => " "), 100)

# The identifier of an option of a choice: the qualified name of an entry, and
# the place of a part of a guide in its group, since two parts can share a
# heading.
_get_option_id(entry, index::Int) = entry.qualname
_get_option_id(unit::ToolModule._GuideSection, index::Int) = "part " * string(index)

# The entries in the order of `probabilities`, best first.
_order_by(entries, probabilities) =
    entries[sortperm(probabilities; rev = true, alg = MergeSort)]

# Score `candidates` with `score`, and answer them best first, and the tokens.
function _score_candidates(score::Function, question::SearchQuestion, candidates, call_sites,
                           context::Bool; code = nothing)
    isempty(candidates) && return (candidates, 0)
    texts = String[make_candidate_text(entry; call_sites = _get_unit_call_sites(call_sites, entry),
                                       code = _get_unit_code(code, entry))
                   for entry in candidates]
    asked = context ? question : SearchQuestion((question.sentence, "", question.expected,
                                                 question.kind, question.source))
    probabilities, tokens = score(asked, texts)
    (_order_by(candidates, probabilities), tokens)
end

"""
    make_cascade_ranker(name, choose, score; keep = 3, call_sites = nothing, code = nothing,
                        context = true, parallel = 1) -> SearchRanker

The shape of a choice and then a score. `choose(question, options)` answers a
probability for each option of one choice, and the tokens it read; an option is
an identifier and a short line. The entries go to the choice in groups of 255,
and the `keep` best of each group go to `score`, with their full text. The
probabilities of one choice add up to one within its group, so they are not
compared across groups: each group gives its best few. `parallel` choices are
asked at once. With `code`, an entry with no first sentence shows the first line
of its code in the choice, and every scored entry carries its code.
"""
function make_cascade_ranker(name::AbstractString, choose::Function, score::Function;
                             keep::Int = 3, call_sites = nothing, code = nothing,
                             context::Bool = true, parallel::Int = 1)
    SearchRanker(String(name), (question, entries) -> begin
        groups = [collect(group) for group in Iterators.partition(entries, _CHOICE_OPTION_LIMIT)]
        chosen = asyncmap(groups; ntasks = parallel) do group
            options = [(_get_option_id(entry, index), _make_choice_line(entry, _get_unit_code(code, entry)))
                       for (index, entry) in enumerate(group)]
            probabilities, used = choose(question, options)
            (first(_order_by(group, probabilities), keep), used)
        end
        kept = reduce(vcat, [first(pair) for pair in chosen]; init = Any[])
        ranked, used = _score_candidates(score, question, kept, call_sites, context; code = code)
        (ranked, sum(last, chosen; init = 0) + used)
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

# ═══════════════════════════════════════════════════════════════════════
# The parts of the guides
# ═══════════════════════════════════════════════════════════════════════

"""
    make_guide_units(size; sections = the sections the search reads) -> Vector

The guides cut into parts of one `size`, for a ranking of `search_guides`:

- `:guide`: one part per guide, with an empty heading: the text of its first
  section, cut at 600 characters, and the headings of the others;
- `:section`: the sections as the search cuts them, at every heading;
- `:paragraph`: each paragraph of each section, with the heading of its section.
"""
function make_guide_units(size::Symbol; sections = ToolModule._guide_index())
    size === :section && return copy(sections)
    if size === :paragraph
        units = ToolModule._GuideSection[]
        for section in sections, paragraph in split(section.body, r"\n\s*\n")
            text = strip(paragraph)
            isempty(text) || push!(units, ToolModule._GuideSection(section.guide, section.heading,
                                                                   String(text)))
        end
        return units
    end
    size === :guide || error("A part of a guide is :guide, :section or :paragraph, not " * repr(size))
    by_guide = Dict{String,Vector{ToolModule._GuideSection}}()
    order = String[]
    for section in sections
        haskey(by_guide, section.guide) || push!(order, section.guide)
        push!(get!(() -> ToolModule._GuideSection[], by_guide, section.guide), section)
    end
    ToolModule._GuideSection[_make_whole_guide_unit(guide, by_guide[guide]) for guide in order]
end

# One part for a whole guide: its first section cut at 600 characters, and the
# headings of the others.
function _make_whole_guide_unit(guide::AbstractString, parts)
    opening = first(parts).heading * "\n" * first(first(parts).body, 600)
    others = join([part.heading for part in parts[2:end] if !isempty(part.heading)], "; ")
    ToolModule._GuideSection(guide, "", isempty(others) ? opening : opening * "\n\nSections: " * others)
end
