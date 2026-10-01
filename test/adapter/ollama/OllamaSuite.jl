"""
    test_ollama_layering()

Static layered-architecture guard for `ProjecturedOllama`.
"""
function test_ollama_layering()
    main = get_package_source_root(ProjecturedOllama)
    check_layering(main, pathof(ProjecturedOllama);
                   name = "ollama",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedOllama; all = true)
                         if isdefined(ProjecturedOllama, n) &&
                            getfield(ProjecturedOllama, n) isa Module &&
                            getfield(ProjecturedOllama, n) !== ProjecturedOllama &&
                            parentmodule(getfield(ProjecturedOllama, n)) !== ProjecturedOllama))
end

"""
    test_ollama()

Run this package's whole suite: the layering guard, the request render, the stream
reader, the factory registration, one live turn that skips itself when no server
answers, the meaning vectors against a stand-in server, and one live meaning test
that skips itself when the server or its meaning model is missing.
"""
function test_ollama()
    @testset "ProjecturedOllama" begin
        test_ollama_layering()
        test_ollama_request()
        test_ollama_stream()
        test_ollama_backend()
        test_ollama_live()
        test_ollama_meaning()
        test_ollama_meaning_live()
    end
end

export test_ollama, test_ollama_layering, test_ollama_request
export test_ollama_stream, test_ollama_backend, test_ollama_live
export test_ollama_meaning, test_ollama_meaning_live
