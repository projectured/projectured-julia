# The search and documentation tools over the whole surface that the code tool
# binds. That surface is the one of the application, with every package of the
# umbrella loaded, so these tests live in the umbrella suite.

# After register_default_tools! the search tools are registered, and no resource
# for each function is.
function test_search_tools_registered()
    @testset "search tools registered, function resources dropped" begin
        tools = register_default_tools!(ToolSet())
        tool_names = [t.name for t in list_tools(tools)]
        @test "search_api" in tool_names
        @test "search_guides" in tool_names

        resource_uris = [r.uri for r in list_resources(tools)]
        @test !any(u -> startswith(u, "resource://function/"), resource_uris)
        @test any(u -> startswith(u, "resource://module/"), resource_uris)

        # The search tools are callable through the registry like any tool.
        out = call_tool(tools, "search_api"; args = Dict("query" => "replace_selection"),
                        target = nothing)
        @test occursin("replace_selection", out)

        # mode "regex" makes the tool treat the query as a regular expression
        rout = call_tool(tools, "search_api";
                         args = Dict("query" => "^OperationModule\\.Replace", "mode" => "regex"),
                         target = nothing)
        @test occursin("ReplaceSelectionOperation", rout)

        # an invalid regex is reported, not thrown
        bad = call_tool(tools, "search_guides";
                        args = Dict("query" => "(unclosed", "mode" => "regex"),
                        target = nothing)
        @test occursin("Invalid regex", bad)

        # in the default mode the same string is read as harmless keywords
        kout = call_tool(tools, "search_guides"; args = Dict("query" => "(unclosed"),
                         target = nothing)
        @test isa(kout, String) && !occursin("Invalid regex", kout)
    end
end

# With no declared API, the documentation tools read the whole surface that the
# code tool binds: the modules of the packages outside the kernel, and only the
# names that the code can write.
function test_whole_surface_documentation()
    @testset "the documentation tools read the whole surface" begin
        tools = register_default_tools!(ToolSet())
        call = (name, args) -> call_tool(tools, name; args = args, target = nothing)
        # A type of a package outside the kernel is the one clear match.
        found = call("search_api", Dict("query" => "CellVector"))
        @test startswith(found, "# `CellVector` — the one API match")
        # A module outside the kernel is found, and its function reads in full.
        read = call("read_function_documentation",
                    Dict("module_name" => "PaneModule",
                         "function_name" => "get_pane_rectangles"))
        @test occursin("Every group with its rectangle in the unit square", read)
        # A name that nobody defined is answered with a name outside the kernel.
        answer = call("execute_julia_code", Dict("code" => "CellVectr(1)"))
        @test occursin("UndefVarError", answer)
        @test occursin("Did you mean: `CellVector`", answer)
        # Each name of the index is the binding that the code of the model reaches.
        # The scratch module binds its names after this function starts, so the
        # check reads them in the newest world.
        execute_julia_code!(tools, nothing, "@__MODULE__")
        scratch = get_last_evaluated_value(tools)
        surface = Dict(ToolModule._collect_surface_modules())
        is_writable = entry -> begin
            module_name, name = split(entry.qualname, '.')
            symbol = Symbol(name)
            isdefined(scratch, symbol) && getfield(scratch, symbol) ===
                getfield(surface[Symbol(module_name)], symbol)
        end
        entries = ToolModule._api_index()
        @test length(entries) > 2000
        @test isempty([entry.qualname for entry in entries if entry.kind != "module" &&
                       !Base.invokelatest(is_writable, entry)])
    end
end
