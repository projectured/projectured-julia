# Fragment of `ProjecturedKernelExample` — what a search costs and answers on a
# corpus of thousands of names.
#
# The searches were built for the hundred names a window declares. The corpus
# grows: a declaration of every module gives thousands of entries, and the
# ranking, the vectors and their file all grow with it. This measures a corpus
# of any size, so that a change to the engine is decided by numbers.
#
# A repository brings its own corpus and its own questions; this brings the
# measurement. `plan/pending/assistant-recovers-from-a-miss.md` says which
# numbers turn which work on.

# What a question asks: an English `sentence`, the `expected` name or guide it
# means, and the `kind` of corpus it is in, `:api` or `:guide`.
const ScaleQuestion = NamedTuple{(:sentence, :expected, :kind),Tuple{String,String,Symbol}}

# How many hits a rank is looked for in. A rank of 0 means the question's answer
# was not among them.
const _SCALE_HIT_COUNT = 50

# The names an API answer lists, in its order. A hit line opens with the
# signature in backticks, and the name is the word the signature starts with; one
# clear hit is a heading instead.
function _get_scale_api_names(answer::AbstractString)
    alone = match(r"^# `([^`]+)` — the one API match"m, answer)
    alone === nothing || return [String(first(split(alone.captures[1], r"[(\s{]")))]
    [String(found.captures[1]) for found in eachmatch(r"^- `([^`(\s{]+)"m, answer)]
end

# The guides an answer lists, each once, where its first section is.
_get_scale_guide_names(answer::AbstractString) =
    unique([String(first(split(found.captures[1], '#')))
            for found in eachmatch(r"^[-#]+ resource://guide/(\S+)"m, answer)])

_get_scale_names(answer::AbstractString, kind::Symbol) =
    kind === :api ? _get_scale_api_names(answer) : _get_scale_guide_names(answer)

# The place of `expected` among `names`, or 0 when it is not among them.
_get_scale_rank(names, expected::AbstractString) =
    something(findfirst(==(expected), names), 0)

# One search, its answer's ranks and what it cost.
function _ask_scale_question(set::ToolSet, question, mode::AbstractString)
    model = mode == "description" ? set.meaning_model : nothing
    answer = ""
    seconds = @elapsed answer =
        question.kind === :api ?
            search_api(question.sentence; mode = mode, detail = "names",
                       limit = _SCALE_HIT_COUNT, api = set.api, meaning_model = model) :
            search_guides(question.sentence; mode = mode, detail = "names",
                          limit = _SCALE_HIT_COUNT, meaning_model = model)
    (_get_scale_rank(_get_scale_names(answer, question.kind), question.expected), seconds)
end

# Wait until the vectors of the corpus are ready, and answer what the build took.
# A description search says in its first line that they are not ready; an answer
# that starts with a heading is ranked by meaning.
function _await_scale_vectors(set::ToolSet, question, seconds::Real)
    started = time()
    deadline = started + seconds
    while true
        answer = question.kind === :api ?
            search_api(question.sentence; mode = "description", detail = "names", limit = 1,
                       api = set.api, meaning_model = set.meaning_model) :
            search_guides(question.sentence; mode = "description", detail = "names", limit = 1,
                          meaning_model = set.meaning_model)
        line = first(split(answer, '\n'))
        startswith(line, "#") && return time() - started
        occursin("not ready", line) || error("The meaning model answered: " * line)
        time() > deadline &&
            error("The meaning vectors were not ready in " * string(seconds) * " seconds.")
        sleep(1.0)
    end
end

# How well one mode answered the questions of one kind: how many ranked first,
# how many were in the first five and in the first ten, and the mean reciprocal
# rank. A question whose answer is not among the hits counts as zero everywhere.
function _describe_scale_quality(ranks::Vector{Int})
    total = length(ranks)
    total == 0 && return "no question"
    inside(n) = count(rank -> 1 <= rank <= n, ranks)
    reciprocal = sum(rank == 0 ? 0.0 : 1 / rank for rank in ranks; init = 0.0) / total
    string(inside(1), " first, ", inside(5), " in five, ", inside(10), " in ten, of ", total,
           "; mean reciprocal rank ", round(reciprocal; digits = 2))
end

"""
    measure_search_scale!(; modules, questions, backend = nothing, io = stdout,
                          seconds = 900) -> Vector

Declare `modules` on a tool set, then ask every question of `questions` twice:
by its words, and by its description. Print what the corpus holds, what a search
costs, and how well the questions are answered, and answer one row per question.

`questions` are `ScaleQuestion`s, each an English sentence with the name or the
guide it means. `backend` is a language model with a meaning model; without one
the description mode ranks by the words of the sentence, and the table says so.
`seconds` bounds the wait for the vectors of the corpus, which are computed once
per model and kept.

The measurement reads a clock, so it wants a machine that is not busy.
"""
function measure_search_scale!(; modules, questions, backend = nothing, io::IO = stdout,
                               seconds::Real = 900)
    set = ToolSet()
    declare_api!(set, modules)
    build_seconds = @elapsed entries = ToolModule._api_index(set.api)
    sections = ToolModule._guide_index()
    kinds = Dict{String,Int}()
    for entry in entries
        kinds[entry.kind] = get(kinds, entry.kind, 0) + 1
    end
    println(io, "A search on ", length(entries), " declared entries (",
            join([string(count, " ", kind) for (kind, count) in sort(collect(kinds))], ", "),
            ") and ", length(sections), " guide sections.")
    println(io, "The index took ", round(build_seconds; digits = 2), " s to build.")
    vector_seconds = 0.0
    if backend !== nothing && has_meaning_model(backend)
        bind_meaning_model!(set, backend)
        vector_seconds = _await_scale_vectors(set, first(questions), seconds)
        store = ToolModule._get_meaning_store(set.meaning_model.name)
        println(io, "The meaning model ", set.meaning_model.name, " was ready after ",
                round(vector_seconds; digits = 1), " s; its vectors take ",
                round(Base.summarysize(store.vectors) / 1_000_000; digits = 1), " MB.")
    else
        println(io, "No meaning model, so a description ranks by its words.")
    end
    rows = NamedTuple[]
    for question in questions
        word_rank, word_seconds = _ask_scale_question(set, question, "keywords")
        meaning_rank, meaning_seconds = _ask_scale_question(set, question, "description")
        push!(rows, (sentence = question.sentence, expected = question.expected,
                     kind = question.kind, word_rank = word_rank, meaning_rank = meaning_rank,
                     word_seconds = word_seconds, meaning_seconds = meaning_seconds))
    end
    _print_scale_table(io, rows)
    rows
end

# The questions, then what each mode answered on each kind, then what a search
# cost. A rank of 0 is written as a dash, because it is not a place.
function _print_scale_table(io::IO, rows)
    place(rank) = rank == 0 ? "—" : string(rank)
    println(io, rpad("sentence", 58), rpad("expected", 34), rpad("words", 7), "description")
    for row in rows
        println(io, rpad(first(row.sentence, 56), 58), rpad(first(row.expected, 32), 34),
                rpad(place(row.word_rank), 7), place(row.meaning_rank))
    end
    for kind in (:api, :guide)
        mine = [row for row in rows if row.kind === kind]
        isempty(mine) && continue
        println(io, String(kind), " by words: ",
                _describe_scale_quality([row.word_rank for row in mine]))
        println(io, String(kind), " by description: ",
                _describe_scale_quality([row.meaning_rank for row in mine]))
    end
    seconds(field) = [getfield(row, field) for row in rows]
    report(label, values) = println(io, label, ": mean ",
                                    round(1000 * sum(values) / length(values); digits = 1),
                                    " ms, worst ", round(1000 * maximum(values); digits = 1), " ms")
    report("A search by words", seconds(:word_seconds))
    report("A search by description", seconds(:meaning_seconds))
    nothing
end
