# Fragment of `ToolModule` — search by meaning: the vectors a meaning model
# computes, where they are kept, how a description is ranked by them, and how a
# guide section's meaning rank joins the rank of its words.

# ═══════════════════════════════════════════════════════════════════════
# The store of vectors
# ═══════════════════════════════════════════════════════════════════════
#
# Process-global, deliberately, as the guide and API indexes are: a vector is
# derived from read-only text and from the model its store is named for, so it
# is identical for every editor that names that model. This is the carve-out
# PAR-PER-EDITOR-STATE grants to such values. Every field of a store is read and
# written under its lock, because its build runs on a task of its own.

# The folder the vector files go in. Empty means `build/meaning/` under the
# repository root. A test points it at a folder of its own.
const _MEANING_FOLDER = Ref("")

# How long the first search that finds vectors missing waits for a build, in
# seconds. A later search during the same build does not wait.
const _MEANING_WAIT_SECONDS = Ref(30.0)

# How many texts go to the model in one call.
const _MEANING_BATCH_SIZE = 64

# The longest text a vector is computed for, in characters. A longer guide
# section is cut into chunks at its paragraphs.
const _MEANING_CHUNK_CHARACTERS = 2000

# The first bytes of a vector file. A file that starts otherwise is not one.
const _MEANING_FILE_HEADER = Vector{UInt8}("PJMEAN01")

mutable struct _MeaningStore
    const name::String
    const path::String
    const lock::ReentrantLock
    # The normalized vector of each text, keyed by the text itself.
    vectors::Dict{String,Vector{Float32}}
    # The texts that wait for a vector, in order, and every text that is waiting
    # or being computed.
    waiting::Vector{String}
    queued::Set{String}
    # The task that computes the waiting texts, while one runs.
    task::Union{Nothing,Task}
    # Why the last build stopped, until a new one starts.
    failure::Union{Nothing,String}
    # The length of every vector in the store, or 0 before the first.
    dimension::Int
    # Whether a search waited on the build that runs, or on the last one.
    has_waited::Bool
    is_writable::Bool
end

const _MEANING_STORES = Dict{String,_MeaningStore}()
const _MEANING_STORES_LOCK = ReentrantLock()

function _get_meaning_file(name::AbstractString)
    folder = isempty(_MEANING_FOLDER[]) ?
        normpath(joinpath(@__DIR__, "..", "..", "..", "build", "meaning")) :
        _MEANING_FOLDER[]
    joinpath(folder, replace(name, r"[/:\\]" => "_") * ".bin")
end

# The store of the model named `name`, made and read from its file on first use.
function _get_meaning_store(name::AbstractString)
    lock(_MEANING_STORES_LOCK) do
        get!(_MEANING_STORES, String(name)) do
            store = _MeaningStore(String(name), _get_meaning_file(name), ReentrantLock(),
                                  Dict{String,Vector{Float32}}(), String[], Set{String}(),
                                  nothing, nothing, 0, false, true)
            _read_meaning_file!(store)
            store
        end
    end
end

# A vector file is a header, then one record per vector: the byte length of the
# text, the text, the length of the vector, and its `Float32` values.
function _read_meaning_file!(store::_MeaningStore)
    isfile(store.path) || return store
    kept = try
        open(store.path, "r") do io
            read(io, length(_MEANING_FILE_HEADER)) == _MEANING_FILE_HEADER || return -1
            whole_records_end = position(io)
            while !eof(io)
                record = _read_meaning_record(io)
                record === nothing && break
                text, vector = record
                # A vector of another length was computed by another model of the
                # same name; the later model is the one that answers now.
                if length(vector) != store.dimension
                    empty!(store.vectors)
                    store.dimension = length(vector)
                end
                store.vectors[text] = vector
                whole_records_end = position(io)
            end
            whole_records_end
        end
    catch err
        @warn "A meaning vector file can not be read, and is written again" store.path reason =
            first(split(sprint(showerror, err), '\n'))
        -1
    end
    # A file that is not one is replaced, and a record that a crash cut short is
    # cut off, so the next batch is appended after the last whole record.
    if kept < 0
        empty!(store.vectors)
        store.dimension = 0
        rm(store.path; force = true)
    elseif kept < filesize(store.path)
        open(io -> truncate(io, kept), store.path, "r+")
    end
    store
end

function _read_meaning_record(io::IO)
    try
        text_length = read(io, Int32)
        text_length >= 0 || return nothing
        text = read(io, text_length)
        length(text) == text_length || return nothing
        dimension = read(io, Int32)
        dimension > 0 || return nothing
        values = read(io, 4 * dimension)
        length(values) == 4 * dimension || return nothing
        (String(text), collect(reinterpret(Float32, values)))
    catch err
        err isa EOFError ? nothing : rethrow()
    end
end

# Append one batch to the file, in one write. A folder that can not be written
# keeps the vectors in memory, and says so once.
function _append_meaning_records!(store::_MeaningStore, texts, vectors)
    store.is_writable || return
    buffer = IOBuffer()
    isfile(store.path) || write(buffer, _MEANING_FILE_HEADER)
    for (text, vector) in zip(texts, vectors)
        write(buffer, Int32(ncodeunits(text)), text, Int32(length(vector)), vector)
    end
    try
        mkpath(dirname(store.path))
        open(io -> write(io, take!(buffer)), store.path, "a")
    catch err
        store.is_writable = false
        @warn "The meaning vectors of $(store.name) are kept in memory only" store.path reason =
            first(split(sprint(showerror, err), '\n'))
    end
    nothing
end

# A vector of length one, so that a dot product is the cosine. A vector of zeros
# stays zeros.
function _normalize_meaning_vector(vector::AbstractVector{<:Real})
    result = Vector{Float32}(vector)
    magnitude = sqrt(sum(abs2, result; init = 0.0f0))
    magnitude > 0 ? result ./ magnitude : result
end

function _normalize_meaning_columns(matrix, count::Integer)
    matrix isa AbstractMatrix{<:Real} ||
        error("The meaning model answered a $(typeof(matrix)), not a matrix of numbers.")
    size(matrix, 2) == count ||
        error("The meaning model answered $(size(matrix, 2)) vectors for $count texts.")
    [_normalize_meaning_vector(view(matrix, :, column)) for column in 1:count]
end

function _compute_meaning_dot(a::Vector{Float32}, b::Vector{Float32})
    total = 0.0f0
    @inbounds @simd for i in eachindex(a, b)
        total += a[i] * b[i]
    end
    total
end

# ═══════════════════════════════════════════════════════════════════════
# The build
# ═══════════════════════════════════════════════════════════════════════

# Put each of `texts` that has no vector in the queue of `store`, and start the
# task that computes them when none runs. Answer whether every one of `texts`
# has a vector already.
function _queue_meaning_texts!(store::_MeaningStore, model::MeaningModel, texts)
    lock(store.lock) do
        complete = true
        for text in texts
            haskey(store.vectors, text) && continue
            complete = false
            text in store.queued && continue
            push!(store.queued, text)
            push!(store.waiting, text)
        end
        if !isempty(store.waiting) && store.task === nothing
            store.failure = nothing
            store.has_waited = false
            store.task = Threads.@spawn _compute_waiting_vectors!(store, model)
        end
        complete
    end
end

function _compute_waiting_vectors!(store::_MeaningStore, model::MeaningModel)
    try
        while true
            batch = lock(store.lock) do
                count = min(_MEANING_BATCH_SIZE, length(store.waiting))
                taken = store.waiting[1:count]
                deleteat!(store.waiting, 1:count)
                count == 0 && (store.task = nothing)
                taken
            end
            isempty(batch) && return
            vectors = _normalize_meaning_columns(model.compute(batch, :document), length(batch))
            lock(store.lock) do
                for (text, vector) in zip(batch, vectors)
                    if length(vector) != store.dimension
                        empty!(store.vectors)
                        store.dimension = length(vector)
                    end
                    store.vectors[text] = vector
                    delete!(store.queued, text)
                end
                _append_meaning_records!(store, batch, vectors)
            end
        end
    catch err
        lock(store.lock) do
            store.failure = first(split(sprint(showerror, err), '\n'))
            empty!(store.waiting)
            empty!(store.queued)
            store.task = nothing
        end
    end
    nothing
end

# Wait while the build of `store` runs. Only the first search that finds texts
# missing during a build waits, and for at most `_MEANING_WAIT_SECONDS`; a later
# one reads what is there, so a long build does not hold every search.
function _await_meaning_build(store::_MeaningStore)
    bound = lock(store.lock) do
        waited = store.has_waited
        store.has_waited = true
        waited ? 0.0 : _MEANING_WAIT_SECONDS[]
    end
    deadline = time() + bound
    while time() < deadline
        lock(() -> store.task === nothing, store.lock) && return
        sleep(0.05)
    end
    nothing
end

# A vector of another length than the query's was computed by another model of
# the same name. The store forgets every vector, and the build starts again.
function _check_meaning_dimension!(store::_MeaningStore, dimension::Int)
    lock(store.lock) do
        (store.dimension == 0 || store.dimension == dimension) && return
        empty!(store.vectors)
        store.dimension = 0
        rm(store.path; force = true)
    end
    nothing
end

"""
    _start_meaning_vectors!(set)

Start computing the vectors of everything the searches of `set` look in: the
entries of its API and the sections of the guides. The texts are gathered on a
task of their own, because the first gathering reads every docstring and every
guide.
"""
function _start_meaning_vectors!(set::ToolSet)
    model = set.meaning_model
    model === nothing && return nothing
    api = set.api
    Threads.@spawn try
        texts = String[_get_meaning_text(entry) for entry in _api_index(api)]
        for section in _guide_index()
            append!(texts, _get_meaning_texts(section))
        end
        _queue_meaning_texts!(_get_meaning_store(model.name), model, texts)
    catch err
        @warn "The meaning vectors of $(model.name) did not start" reason =
            first(split(sprint(showerror, err), '\n'))
    end
    nothing
end

# ═══════════════════════════════════════════════════════════════════════
# The texts that get a vector
# ═══════════════════════════════════════════════════════════════════════

# An entry is its qualified name and its whole documentation. The scored text
# holds only the signature and one sentence, and a description finds its verb
# less often by that: measured on the omnet IDE's 88 verbs, 2026-09-16, the
# mean rank of eight test sentences fell from 8.1 to 5.8 with the whole
# documentation, and five of the eight ranked their verb first instead of four.
_get_meaning_text(entry::_ApiEntry) =
    first(entry.qualname * "\n" * entry.full, _MEANING_CHUNK_CHARACTERS)

# A section is its guide, its heading and its body, cut into chunks at its
# paragraphs when the body is long. Each chunk carries the guide and the heading.
function _get_meaning_texts(section::_GuideSection)
    prefix = section.guide * " › " * section.heading * "\n\n"
    length(section.body) <= _MEANING_CHUNK_CHARACTERS && return [prefix * section.body]
    chunks = String[]
    current = IOBuffer()
    current_length = 0
    for paragraph in split(section.body, r"\n\s*\n"), piece in _split_long_paragraph(paragraph)
        if current_length > 0 && current_length + 2 + length(piece) > _MEANING_CHUNK_CHARACTERS
            push!(chunks, prefix * String(take!(current)))
            current_length = 0
        end
        current_length > 0 && (write(current, "\n\n"); current_length += 2)
        write(current, piece)
        current_length += length(piece)
    end
    current_length > 0 && push!(chunks, prefix * String(take!(current)))
    chunks
end

function _split_long_paragraph(paragraph::AbstractString)
    length(paragraph) <= _MEANING_CHUNK_CHARACTERS && return [String(paragraph)]
    characters = collect(paragraph)
    [String(characters[start:min(start + _MEANING_CHUNK_CHARACTERS - 1, end)])
     for start in 1:_MEANING_CHUNK_CHARACTERS:length(characters)]
end

# ═══════════════════════════════════════════════════════════════════════
# The rank by meaning
# ═══════════════════════════════════════════════════════════════════════

# The first line of a description search that the words alone ranked.
const _NO_MEANING_MODEL_NOTE =
    "No meaning model was given, so the words of the description ranked these " *
    "hits. When you know a word of the name, mode \"keywords\" with that word " *
    "does better."

_describe_unready_vectors(model::MeaningModel) =
    "The meaning vectors of the $(model.name) model are not ready yet, so the " *
    "words of the description ranked these hits. Search again in a minute."

_describe_meaning_failure(model::MeaningModel, reason::AbstractString) =
    "The meaning model $(model.name) failed, so the words of the description " *
    "ranked these hits. The reason: " * reason

# The vector of the description, or the note that says why there is none.
function _compute_query_vector(model::MeaningModel, text::String)
    try
        (only(_normalize_meaning_columns(model.compute([text], :query), 1)), nothing)
    catch err
        (nothing, _describe_meaning_failure(model, first(split(sprint(showerror, err), '\n'))))
    end
end

# The vectors of `texts`, in their order, or the note that says why they are not
# ready.
function _find_text_vectors(model::MeaningModel, texts::Vector{String}, dimension::Int)
    store = _get_meaning_store(model.name)
    _check_meaning_dimension!(store, dimension)
    _queue_meaning_texts!(store, model, texts) || _await_meaning_build(store)
    lock(store.lock) do
        all(text -> haskey(store.vectors, text), texts) &&
            return ([store.vectors[text] for text in texts], nothing)
        failure = store.failure
        (nothing, failure === nothing ? _describe_unready_vectors(model) :
                                        _describe_meaning_failure(model, failure))
    end
end

# How many items a rank by meaning answers. Every item has a score, so the rank
# is cut, as the answer is.
const _MEANING_RANK_COUNT = 50

# The items with the highest scores, best first. A tie keeps the order the items
# came in.
_get_best_items(items::Vector, scores::Vector{Float32}) =
    items[first(sortperm(scores; rev = true, alg = MergeSort), _MEANING_RANK_COUNT)]

# The entries a description means, best first, and the note that says why there
# is no such ranking. Exactly one of the two is `nothing`.
_rank_api_entries_by_meaning(query::_DescriptionQuery, entries, meaning_model::Nothing) =
    (nothing, _NO_MEANING_MODEL_NOTE)

function _rank_api_entries_by_meaning(query::_DescriptionQuery, entries::Vector{_ApiEntry},
                                      model::MeaningModel)
    query_vector, note = _compute_query_vector(model, query.text)
    query_vector === nothing && return (nothing, note)
    vectors, note = _find_text_vectors(model, String[_get_meaning_text(entry) for entry in entries],
                                       length(query_vector))
    vectors === nothing && return (nothing, note)
    scores = Float32[_compute_meaning_dot(query_vector, vector) for vector in vectors]
    (_get_best_items(entries, scores), nothing)
end

# The same for guide sections. A section scores as its best chunk.
_rank_guide_sections_by_meaning(query::_DescriptionQuery, sections, meaning_model::Nothing) =
    (nothing, _NO_MEANING_MODEL_NOTE)

function _rank_guide_sections_by_meaning(query::_DescriptionQuery,
                                         sections::Vector{_GuideSection}, model::MeaningModel)
    query_vector, note = _compute_query_vector(model, query.text)
    query_vector === nothing && return (nothing, note)
    chunks = [_get_meaning_texts(section) for section in sections]
    vectors, note = _find_text_vectors(model, reduce(vcat, chunks; init = String[]),
                                       length(query_vector))
    vectors === nothing && return (nothing, note)
    scores = Vector{Float32}(undef, length(sections))
    next = 1
    for (index, section_chunks) in enumerate(chunks)
        best = -Inf32
        for _ in section_chunks
            best = max(best, _compute_meaning_dot(query_vector, vectors[next]))
            next += 1
        end
        scores[index] = best
    end
    (_get_best_items(sections, scores), nothing)
end

# **Reciprocal rank fusion, for guide sections.** An item's score is the sum, over
# the two rankings, of `weight / (_FUSION_RANK_OFFSET + its rank there)`, over the
# first `_MEANING_RANK_COUNT` items of each; the meaning rank weighs 1. It needs no
# calibration between a count of words and a cosine, and an item that only one
# ranking finds still ranks.
#
# **A guide's words count twice.** A heading says what its section is about in
# the words a person uses, and the keyword scorer counts a heading five times, so
# for a guide the words are a strong ranking, where for a verb's name they are
# noise. Measured on eight sentences, 2026-09-16: the expected section came first
# five times by the words, six times by the meaning, seven times by both merged
# this way, and the eighth second. With equal weights the eighth came fourth.
const _FUSION_RANK_OFFSET = 60
const _GUIDE_WORD_WEIGHT = 2.0

function _fuse_rankings(word_ranking::Vector{T}, meaning_ranking::Vector{T};
                        word_weight::Real) where {T}
    scores = Dict{T,Float64}()
    order = T[]
    for (weight, ranking) in ((word_weight, word_ranking), (1.0, meaning_ranking))
        for (rank, item) in enumerate(Iterators.take(ranking, _MEANING_RANK_COUNT))
            haskey(scores, item) || push!(order, item)
            scores[item] = get(scores, item, 0.0) + weight / (_FUSION_RANK_OFFSET + rank)
        end
    end
    # A tie keeps the order the rankings gave, the words before the meaning.
    sort!(order; by = item -> -scores[item], alg = MergeSort)
end

