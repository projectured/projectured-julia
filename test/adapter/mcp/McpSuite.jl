include("McpTest.jl")

"""
    test_mcp_layering()

Static layered-architecture guard for `ProjecturedMCP`.
"""
function test_mcp_layering()
    main = get_package_source_root(ProjecturedMCP)
    check_layering(main, pathof(ProjecturedMCP);
                   name = "mcp",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedMCP; all = true)
                         if isdefined(ProjecturedMCP, n) &&
                            getfield(ProjecturedMCP, n) isa Module &&
                            getfield(ProjecturedMCP, n) !== ProjecturedMCP &&
                            parentmodule(getfield(ProjecturedMCP, n)) !== ProjecturedMCP))
end

"""
    test_mcp()

Run the whole suite of `ProjecturedMCP`: the layering guard and every test of the package.
"""
function test_mcp()
    @testset "ProjecturedMCP" begin
        test_mcp_layering()
        test_mcp_resources()
        test_mcp_tools()
    end
end

export test_mcp, test_mcp_layering
