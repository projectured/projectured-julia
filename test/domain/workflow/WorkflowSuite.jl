"""
    test_workflow_layering()

Static layered-architecture guard for `ProjecturedWorkflow`.
"""
function test_workflow_layering()
    main = get_package_source_root(ProjecturedWorkflow)
    check_layering(main, pathof(ProjecturedWorkflow);
                   name = "workflow",
                   extra_aliases = Set{Symbol}(
                       n for n in names(ProjecturedWorkflow; all = true)
                         if isdefined(ProjecturedWorkflow, n) &&
                            getfield(ProjecturedWorkflow, n) isa Module &&
                            getfield(ProjecturedWorkflow, n) !== ProjecturedWorkflow &&
                            parentmodule(getfield(ProjecturedWorkflow, n)) !== ProjecturedWorkflow))
end

"""
    test_workflow()

Run this package's whole suite: the layering guard and every workflow test.
"""
function test_workflow()
    @testset "ProjecturedWorkflow" begin
        test_workflow_layering()
        test_workflow_document()
        test_workflow_edits()
        test_workflow_to_widget()
        test_workflow_journal_to_widget, test_workflow_assistant_api()
        test_workflow_assistant_api()
    end
end

export test_workflow, test_workflow_layering, test_workflow_document, test_workflow_edits, test_workflow_to_widget,
       test_workflow_journal_to_widget, test_workflow_assistant_api
