"""
The search by description: the meaning model a backend gives a `ToolSet`, and
how the vectors it computes rank what a description finds.
"""

using Test
using ProjecturedKernel.ToolModule
using ProjecturedKernel.LlmModule: has_meaning_model, get_meaning_model_name,
                                   compute_meaning_vectors, bind_meaning_model!
using ProjecturedKernelExample: FakeLlm

const _MeaningTools = ProjecturedKernel.ToolModule

# A declared API whose names share no word with the descriptions that find them.
module MeaningToy
export measure_utilization, close_window, count_packets
"""
    measure_utilization(server) -> Float64

Give the share of time the server works.
"""
measure_utilization(server) = 0.5
"""
    close_window(window) -> Nothing

Remove the window from the screen.
"""
close_window(window) = nothing
"""
    count_packets(link) -> Int

Give the number of packets a link carried.
"""
count_packets(link) = 0
end

# A meaning model made from a table of synonyms: each word of a group adds to
# the place of its group. "busy" and "utilization" mean the same here, and no
# text of the API says "busy".
const _TOY_MEANING_PLACES = Dict(
    "busy" => 1, "utilization" => 1, "works" => 1, "load" => 1,
    "shut" => 2, "close" => 2, "remove" => 2, "window" => 2,
    "traffic" => 3, "packets" => 3, "carried" => 3)

function _compute_toy_meaning(texts, purpose)
    vectors = zeros(Float32, 3, length(texts))
    for (column, text) in enumerate(texts), word in split(lowercase(text), r"[^a-z]+")
        place = get(_TOY_MEANING_PLACES, word, 0)
        place == 0 || (vectors[place, column] += 1)
    end
    vectors
end

_make_toy_meaning_model(name; compute = _compute_toy_meaning) = MeaningModel(name, compute)

# The name of the first hit in a list answer.
function _get_first_hit(answer::AbstractString)
    found = match(r"^- `([^`(\s{]+)"m, answer)
    found === nothing ? nothing : found.captures[1]
end

# Forget the store of a model, so the next search reads its file again.
function _forget_meaning_store(name)
    lock(_MeaningTools._MEANING_STORES_LOCK) do
        delete!(_MeaningTools._MEANING_STORES, name)
    end
end

# Search until `is_done(answer)`, for at most `seconds`.
function _search_until(is_done, search; seconds = 20)
    deadline = time() + seconds
    answer = search()
    while !is_done(answer) && time() < deadline
        sleep(0.1)
        answer = search()
    end
    answer
end

function test_meaning_search()
@testset "Meaning search" begin

    folder = mktempdir()
    _MeaningTools._MEANING_FOLDER[] = folder
    try

    @testset "a binary reads its guides and keeps its vectors outside the checkout" begin
        # A Julia session has no bundle, so it uses the checkout.
        @test _MeaningTools._get_bundle_directory() === nothing
        @test endswith(_MeaningTools._get_default_meaning_folder(nothing),
                       joinpath("build", "meaning"))
        @test isfile(joinpath(_MeaningTools._get_documentation_directory(nothing), "README.md"))

        # A binary has `share/projectured/` beside its `bin/`.
        root = mktempdir()
        bin = joinpath(root, "bin")
        mkpath(bin)
        @test _MeaningTools._get_bundle_directory(bin) === nothing
        shared = joinpath(root, "share", "projectured")
        mkpath(shared)
        @test _MeaningTools._get_bundle_directory(bin) == shared
        # A bundle without guides reads the checkout.
        @test _MeaningTools._get_documentation_directory(shared) ==
              _MeaningTools._get_documentation_directory(nothing)
        mkpath(joinpath(shared, "documentation"))
        @test _MeaningTools._get_documentation_directory(shared) ==
              joinpath(shared, "documentation")
        @test withenv(() -> _MeaningTools._get_default_meaning_folder(shared),
                      "XDG_CACHE_HOME" => "/cache") == "/cache/projectured/meaning"
        @test withenv(() -> _MeaningTools._get_default_meaning_folder(shared),
                      "XDG_CACHE_HOME" => nothing) ==
              joinpath(homedir(), ".cache", "projectured", "meaning")
        rm(root; recursive = true)
    end

    @testset "a backend with a meaning model gives it to a tool set" begin
        llm = FakeLlm("ok"; meaning_model = "bag-of-words")
        @test has_meaning_model(llm)
        @test get_meaning_model_name(llm) == "fake/bag-of-words"
        vectors = compute_meaning_vectors(llm, ["plot a vector", "draw the vector", "x"])
        @test size(vectors) == (64, 3)
        @test eltype(vectors) == Float32
        # Two texts that share a word share a place; a text of no word is zero.
        @test sum(vectors[:, 1] .* vectors[:, 2]) > 0
        @test all(iszero, vectors[:, 3])

        set = ToolSet()
        @test set.meaning_model === nothing
        @test bind_meaning_model!(set, llm) === set
        @test set.meaning_model isa MeaningModel
        @test set.meaning_model.name == "fake/bag-of-words"
        @test size(set.meaning_model.compute(["plot"], :query)) == (64, 1)
    end

    @testset "a backend without one leaves the tool set as it is" begin
        plain = FakeLlm("ok")
        @test !has_meaning_model(plain)
        @test_throws ErrorException compute_meaning_vectors(plain, ["plot"])
        @test_throws ErrorException get_meaning_model_name(plain)

        fresh = ToolSet()
        bind_meaning_model!(fresh, plain)
        @test fresh.meaning_model === nothing

        bound = ToolSet()
        bind_meaning_model!(bound, FakeLlm("ok"; meaning_model = "bag-of-words"))
        bind_meaning_model!(bound, plain)
        @test bound.meaning_model.name == "fake/bag-of-words"

        # `set_meaning_model!` is how one is taken away.
        @test set_meaning_model!(bound, nothing).meaning_model === nothing
    end

    api = ApiEntry[ApiEntry(MeaningToy, nothing)]
    toy = _make_toy_meaning_model("test/synonyms")

    @testset "a description finds a name that shares no word with it" begin
        # The words alone find nothing.
        @test occursin("No API matches",
                       search_api("how busy was it"; mode = "description", api = api))
        found = search_api("how busy was it"; mode = "description", api = api,
                           meaning_model = toy)
        @test !occursin("meaning model", first(split(found, '\n')))
        @test _get_first_hit(found) == "measure_utilization"
        @test _get_first_hit(search_api("shut it"; mode = "description", api = api,
                                        meaning_model = toy)) == "close_window"
        # The words and the meaning agree, so the hit stays first.
        @test _get_first_hit(search_api("the traffic in packets"; mode = "description",
                                        api = api, meaning_model = toy)) == "count_packets"
        # The keyword mode ignores the meaning model.
        @test occursin("No API matches",
                       search_api("busy"; api = api, meaning_model = toy))
    end

    @testset "the guides are ranked by meaning too" begin
        found = search_guides("close the window"; mode = "description",
                                     meaning_model = toy)
        @test startswith(found, "# Documentation matches")
        @test occursin("resource://guide/", found)
    end

    @testset "a guide's words count twice when its ranks are merged" begin
        fuse = _MeaningTools._fuse_rankings
        # With equal weights, `y` is first: it is first by meaning and second by
        # words. With the words counting twice, the first by words wins.
        @test fuse(["x", "y"], ["y", "z", "x"]; word_weight = 1.0) == ["y", "x", "z"]
        @test fuse(["x", "y"], ["y", "z", "x"]; word_weight = 2.0) == ["x", "y", "z"]
        # An item only one ranking holds still ranks.
        @test "z" in fuse(["x"], ["z"]; word_weight = 2.0)
    end

    @testset "a guide section longer than a chunk is cut at its paragraphs" begin
        paragraph = repeat("word ", 300)                  # 1500 characters
        section = _MeaningTools._GuideSection("guide", "Heading",
                                              join([paragraph, paragraph, paragraph], "\n\n"))
        chunks = _MeaningTools._get_meaning_texts(section)
        @test length(chunks) == 3
        @test all(chunk -> startswith(chunk, "guide › Heading\n\n"), chunks)
        long = _MeaningTools._GuideSection("guide", "Long", repeat("x", 4500))
        @test length(_MeaningTools._get_meaning_texts(long)) == 3
    end

    @testset "a model that fails falls back to the words, and says why" begin
        broken = _make_toy_meaning_model("test/broken";
                                         compute = (texts, purpose) -> error("no server at port 1"))
        found = search_api("measure the share"; mode = "description", api = api,
                           meaning_model = broken)
        @test startswith(found, "The meaning model test/broken failed")
        @test occursin("no server at port 1", found)
        @test occursin("measure_utilization", found)

        # The description is computed, the documents are not.
        half = _make_toy_meaning_model("test/half"; compute = (texts, purpose) ->
            purpose == :query ? _compute_toy_meaning(texts, purpose) : error("disk full"))
        found = search_api("how busy was it"; mode = "description", api = api,
                           meaning_model = half)
        @test startswith(found, "The meaning model test/half failed")
        @test occursin("disk full", found)
    end

    @testset "only the first search waits for a slow build" begin
        slow = _make_toy_meaning_model("test/slow"; compute = (texts, purpose) ->
            (purpose == :document && sleep(2); _compute_toy_meaning(texts, purpose)))
        search = () -> search_api("how busy was it"; mode = "description", api = api,
                                  meaning_model = slow)
        bound = _MeaningTools._MEANING_WAIT_SECONDS[]
        try
            _MeaningTools._MEANING_WAIT_SECONDS[] = 0.2
            @test startswith(search(), "The meaning vectors of the test/slow model are not ready yet")
            _MeaningTools._MEANING_WAIT_SECONDS[] = 60.0
            @test (@elapsed search()) < 1.5
            answer = _search_until(answer -> _get_first_hit(answer) == "measure_utilization", search)
            @test _get_first_hit(answer) == "measure_utilization"
        finally
            _MeaningTools._MEANING_WAIT_SECONDS[] = bound
        end
    end

    @testset "the vectors are kept in a file, and read back without the model" begin
        count = Ref(0)
        counting = _make_toy_meaning_model("test/counting"; compute = (texts, purpose) ->
            (purpose == :document && (count[] += length(texts)); _compute_toy_meaning(texts, purpose)))
        search = () -> search_api("how busy was it"; mode = "description", api = api,
                                  meaning_model = counting)
        @test _get_first_hit(search()) == "measure_utilization"
        path = joinpath(folder, "test_counting.bin")
        @test isfile(path)
        computed = count[]
        @test computed == length(_MeaningTools._api_index(api))
        size = filesize(path)

        _forget_meaning_store("test/counting")
        @test _get_first_hit(search()) == "measure_utilization"
        @test count[] == computed

        # A record that a crash cut short is cut off the file.
        open(io -> write(io, Int32(40), "cut"), path, "a")
        _forget_meaning_store("test/counting")
        @test _get_first_hit(search()) == "measure_utilization"
        @test count[] == computed
        @test filesize(path) == size

        # A file that is not a vector file is written again.
        write(path, "not a vector file")
        _forget_meaning_store("test/counting")
        @test _get_first_hit(search()) == "measure_utilization"
        @test count[] == 2 * computed
        @test read(path, 8) == Vector{UInt8}("PJMEAN01")
    end

    @testset "a model that changes its vector length under its name starts again" begin
        wider = _make_toy_meaning_model("test/counting"; compute = (texts, purpose) ->
            vcat(_compute_toy_meaning(texts, purpose), ones(Float32, 1, length(texts))))
        found = search_api("how busy was it"; mode = "description", api = api,
                           meaning_model = wider)
        @test _get_first_hit(found) !== nothing
        store = _MeaningTools._get_meaning_store("test/counting")
        @test lock(() -> store.dimension, store.lock) == 4
    end

    @testset "a bound backend ranks the tools and the code a model writes" begin
        set = register_default_tools!(ToolSet(; api = Module[MeaningToy]))
        # The scratch module is built before the model is bound.
        @test occursin("measure_utilization", execute_julia_code(set, nothing, "measure_utilization"))
        set_meaning_model!(set, toy)
        search = only(t for t in list_tools(set) if t.name == "search_api")
        found = search.handler(nothing, Dict("query" => "how busy was it", "mode" => "description"))
        @test _get_first_hit(found) == "measure_utilization"
        code = execute_julia_code(set, nothing,
                                  "search_api(\"how busy was it\"; mode = \"description\")")
        @test occursin("measure_utilization", code)
        @test !occursin("No meaning model", code)
    end

    @testset "binding a backend starts the vectors of the guides and the API" begin
        set = ToolSet(; api = Module[MeaningToy])
        bind_meaning_model!(set, FakeLlm("ok"; meaning_model = "started"))
        store = _MeaningTools._get_meaning_store("fake/started")
        expected = length(_MeaningTools._api_index(set.api))
        deadline = time() + 30
        while time() < deadline &&
              lock(() -> length(store.vectors) < expected || store.task !== nothing, store.lock)
            sleep(0.1)
        end
        @test lock(() -> length(store.vectors), store.lock) > expected
        @test lock(() -> store.failure, store.lock) === nothing
    end

    finally
        _MeaningTools._MEANING_FOLDER[] = ""
    end
end
end # test_meaning_search
