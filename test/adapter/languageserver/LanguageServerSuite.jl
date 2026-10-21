"""
    test_languageserver_layering()

Static layered-architecture guard for `ProjecturedLanguageServer`.
"""
function test_languageserver_layering()
    main = get_package_source_root(ProjecturedLanguageServer)
    check_layering(main, pathof(ProjecturedLanguageServer);
                   name = "languageserver",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedLanguageServer; all = true)
                         if isdefined(ProjecturedLanguageServer, n) &&
                            getfield(ProjecturedLanguageServer, n) isa Module &&
                            getfield(ProjecturedLanguageServer, n) !== ProjecturedLanguageServer &&
                            parentmodule(getfield(ProjecturedLanguageServer, n)) !== ProjecturedLanguageServer))
end

"""
    test_languageserver()

Run this package's whole suite: the layering guard and the connection, against
a language server in this process.
"""
function test_languageserver()
    @testset "ProjecturedLanguageServer" begin
        test_languageserver_layering()
        test_language_server_connection()
    end
end

export test_languageserver, test_languageserver_layering, test_language_server_connection
