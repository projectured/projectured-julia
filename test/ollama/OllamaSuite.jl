"""
    test_ollama_layering()

Static layered-architecture guard for `ProjecturedOllama`.
"""
function test_ollama_layering()
    main = package_source_root(ProjecturedOllama)
    check_layering(main, pathof(ProjecturedOllama); name = "ollama")
end

"""
    test_ollama()

Run this package's whole suite: the layering guard, the request render, the stream
reader, the factory registration, and one live turn that skips itself when no
server answers.
"""
function test_ollama()
    @testset "ProjecturedOllama" begin
        test_ollama_layering()
        test_ollama_request()
        test_ollama_stream()
        test_ollama_backend()
        test_ollama_live()
    end
end

export test_ollama, test_ollama_layering, test_ollama_request
export test_ollama_stream, test_ollama_backend, test_ollama_live
