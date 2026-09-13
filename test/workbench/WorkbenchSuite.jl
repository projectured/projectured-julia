"""
    test_workbench_layering()

Static layered-architecture guard for `ProjecturedWorkbench`.
"""
function test_workbench_layering()
    main = get_package_source_root(ProjecturedWorkbench)
    check_layering(main, pathof(ProjecturedWorkbench);
                   name = "workbench",
                   # PAR-QUALIFIED-EXTENSION: the header imports what it extends
                   qualified_files = Set(["Workspace.jl"]),
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedWorkbench; all = true)
                         if isdefined(ProjecturedWorkbench, n) &&
                            getfield(ProjecturedWorkbench, n) isa Module &&
                            getfield(ProjecturedWorkbench, n) !== ProjecturedWorkbench &&
                            parentmodule(getfield(ProjecturedWorkbench, n)) !== ProjecturedWorkbench))
end

"""
    test_workbench()

Run this package's whole suite: the layering guard and every workbench test.
"""
function test_workbench()
    @testset "ProjecturedWorkbench" begin
        test_workbench_layering()
        test_assistant_mvp()
        test_workbench_content_pane()
        test_workbench_tab_click()
    end
end

export test_workbench, test_workbench_layering, test_assistant_mvp
export test_workbench_content_pane, test_workbench_tab_click
