# The workflows of the open files of an editor: one row for each open file whose
# document is a workflow, with its file as `within`; a file that closes takes its
# row away; the explorer of each window holds the list from the start; a file of
# the list has the tree of its workflow below it; the facets give the columns.

# A folder with a workflow file and a `.pred` file of another document.
function _make_workflow_list_folder()
    folder = mktempdir()
    workflow = WorkflowStep(title = PrimitiveString("Ship the list"), state = :active,
                            journal = [WorkflowEntry(time = "2026-10-22T09:30:00")],
                            children = [WorkflowStep(title = PrimitiveString("Survey"), state = :done),
                                        WorkflowStep(title = PrimitiveString("Build"), state = :active),
                                        make_workflow_decision("Where the rule goes", ["tree", "file format"])])
    write(joinpath(folder, "plan.pred"), print_pred_text(workflow))
    write(joinpath(folder, "other.pred"), print_pred_text(PrimitiveString("not a workflow")))
    folder
end

"""
    test_workflow_list()

The list of the workflows of the open files: its rows follow the open files, the
first content of an explorer holds it, its tree reaches the steps through the page
of a file, its facets give the columns, and its page counts the workflows.
"""
function test_workflow_list()
    @testset "WorkflowList" begin
        @testset "a row for each open file that holds a workflow, while it is open" begin
            editor = _make_workflow_view_editor(PrimitiveString("start"))
            folder = _make_workflow_list_folder()
            plan = make_file_tab_content(joinpath(folder, "plan.pred"))
            other = make_file_tab_content(joinpath(folder, "other.pred"))
            list = get_session_workflow_list(; editor)
            @test list === get_session_workflow_list(; editor)
            @test list.file_list === get_session_open_file_list(; editor)
            @test isempty(list.files) && isempty(list.table.document.rows)
            add_open_file!(editor, plan)
            add_open_file!(editor, other)
            @test length(list.files) == 1 && list.files[1] === plan
            rows = collect(list.table.document.rows)
            @test length(rows) == 1
            @test rows[1].item === get_edited_document(plan)
            @test rows[1].within === find_page_file(plan)
            @test collect(rows[1].values) ==
                  Any["Ship the list", :active, "Ship the list, Build", "2026-10-22 09:30", 1, "plan.pred"]
            remove_open_file!(editor, plan)
            @test isempty(list.files) && isempty(list.table.document.rows)
            @test :workflows in get_roster_source_names()
        end

        @testset "the first content of an explorer holds the list of its editor" begin
            editor = _make_workflow_view_editor(PrimitiveString("start"))
            content = make_editor_explorer_content(; editor)
            list = only(entry for entry in content.entries if entry isa WorkflowList)
            @test list === get_session_workflow_list(; editor)
            @test list.file_list === get_session_open_file_list(; editor)
            @test is_explorer_entry_type(WorkflowList) && is_session_explorer_entry_type(WorkflowList)
            @test make_pred_document(WorkflowList, (), Pair{Symbol,Any}[]) isa WorkflowList
        end

        @testset "the tree reaches the steps through the page of a file" begin
            editor = _make_workflow_view_editor(PrimitiveString("start"))
            plan = make_file_tab_content(joinpath(_make_workflow_list_folder(), "plan.pred"))
            add_open_file!(editor, plan)
            list = get_session_workflow_list(; editor)
            files = collect_tree_children(list; limit = 10)
            @test length(files) == 1 && last(files[1]) === plan
            steps = [last(pair) for pair in collect_tree_children(plan; limit = 10)]
            @test [get_document_title(step) for step in steps] == ["Survey", "Build", "Where the rule goes"]
            @test [get_document_title(last(pair)) for pair in collect_tree_children(steps[3]; limit = 10)] ==
                  ["tree", "file format"]
            @test get_document_decoration(list).counts[1].text == "1 open"
            @test get_document_decoration(steps[1]).counts[1].role === :success
            @test get_document_decoration(steps[3]).counts[1].text == "open"
        end

        @testset "the facets of a step, and the page of the list" begin
            workflow = WorkflowStep(title = PrimitiveString("Goal"), state = :active)
            @test [first(facet) for facet in get_item_facets(WorkflowStep)] ==
                  ["goal", "active", "last_entry", "open_decisions"]
            @test compute_item_facet(workflow, Val(:goal)) == "Goal"
            @test compute_item_facet(workflow, Val(:last_entry)) == ""
            @test compute_item_facet(workflow, Val(:open_decisions)) == 0
            editor = _make_workflow_view_editor(PrimitiveString("start"))
            list = get_session_workflow_list(; editor)
            line() = print_document(WorkflowListToWidget(), nothing, list, nothing).output.children[1].content
            @test startswith(line(), "No workflow is open.")
            add_open_file!(editor, make_file_tab_content(joinpath(_make_workflow_list_folder(), "plan.pred")))
            @test line() == "1 open workflow · 1 open decision"
            # The renderer draws the list as its page.
            @test _make_workflow_view_editor(list) isa Editor
        end
    end
end
