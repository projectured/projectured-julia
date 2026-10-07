"""
    test_acp_layering()

Static layered-architecture guard for `ProjecturedACP`.
"""
function test_acp_layering()
    main = get_package_source_root(ProjecturedACP)
    check_layering(main, pathof(ProjecturedACP);
                   name = "acp",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedACP; all = true)
                         if isdefined(ProjecturedACP, n) &&
                            getfield(ProjecturedACP, n) isa Module &&
                            getfield(ProjecturedACP, n) !== ProjecturedACP &&
                            parentmodule(getfield(ProjecturedACP, n)) !== ProjecturedACP))
end

"""
    test_acp()

Run this package's whole suite: the layering guard, the translation of the
updates of an agent, the connection against a fake agent in this process, and
the transport with a real child process.
"""
function test_acp()
    @testset "ProjecturedACP" begin
        test_acp_layering()
        test_acp_update()
        test_acp_connection()
        test_acp_transport()
    end
end

export test_acp, test_acp_layering, test_acp_update, test_acp_connection, test_acp_transport
