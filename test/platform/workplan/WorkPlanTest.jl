# The plan of an agent: the progress at every depth, a blocked step that a
# completed blocker frees, the words of the progress, the three contents of a
# plan, its file form and its copy, the tree of its steps in a real editor, a
# link on the page of a step that opens the step that it waits for, and a roster
# of steps with the facet `blocked`. The editor is the one of
# `NavigatorToWidgetTest.jl`, and the double click the one of `TreeTest.jl`.

# A plan of seven steps at two depths: two completed, one in progress, two
# pending of which one is blocked by step 2, one skipped and one deferred.
function _workplan_make()
    WorkPlan("tasks"; title = "Fix the parser", steps = [
        WorkPlanStep("1", "Read the code"; status = :completed),
        WorkPlanStep("2", "Write the tests"; status = :in_progress, active_title = "Writing the tests",
                     priority = :high, children = [
                         WorkPlanStep("2a", "Unit tests"; status = :completed),
                         WorkPlanStep("2b", "Editor tests")]),
        WorkPlanStep("3", "Fix the bug"; blocked_by = ["2"], description = "The parser drops a comma."),
        WorkPlanStep("4", "Write the guide"; status = :skipped, reason = "The guide says it already."),
        WorkPlanStep("5", "Release"; status = :deferred, priority = :low)])
end

_workplan_path(steps...) = extend_reference(EmptyReference(), steps...)
_workplan_step_path(indices...) =
    _workplan_path(FieldReferenceStep("steps"), ElementReferenceStep(indices[1]),
                   (step for k in indices[2:end] for step in (FieldReferenceStep("children"), ElementReferenceStep(k)))...)

function test_work_plan()
@testset "the plan of an agent" begin
    @testset "the progress counts the steps at every depth" begin
        plan = _workplan_make()
        progress = compute_work_plan_progress(plan)
        @test progress == WorkPlanProgress(7, 2, 1, 2, 1, 1, 1)
        @test (progress.total, progress.completed, progress.blocked) == (7, 2, 1)
        # A step under a step counts, and the count follows its status.
        plan.steps[2].children[2].status = :completed
        @test compute_work_plan_progress(plan) == WorkPlanProgress(7, 1, 1, 3, 1, 1, 1)
        @test compute_work_plan_progress(WorkPlan("empty")) == WorkPlanProgress(0, 0, 0, 0, 0, 0, 0)
        @test WORK_PLAN_STEP_STATUSES == (:pending, :in_progress, :completed, :skipped, :deferred)
        @test_throws ArgumentError WorkPlanStep("x", "No such status"; status = :blocked)
        @test_throws ArgumentError WorkPlanStep("x", "No such priority"; priority = :urgent)
    end

    @testset "a blocked step is free when its blocker completes" begin
        plan = _workplan_make()
        (writing, fixing) = (plan.steps[2], plan.steps[3])
        @test is_work_plan_step_blocked(plan, fixing)
        @test !is_work_plan_step_blocked(plan, writing)
        @test format_tree_node_label(fixing) == "Fix the bug · blocked by step 2"
        @test get_tree_node_icon(fixing) === :stop
        @test compute_item_facet(fixing, Val(:blocked)) === true
        writing.status = :completed
        @test !is_work_plan_step_blocked(plan, fixing)
        @test format_tree_node_label(fixing) == "Fix the bug · pending"
        @test get_tree_node_icon(fixing) === :circle
        @test compute_item_facet(fixing, Val(:blocked)) === false
        # A blocker under a step blocks too; an id that names no step blocks nothing,
        # and a step that does not wait is not blocked.
        set_work_plan_steps!(plan, [WorkPlanStep("a", "A"; children = [WorkPlanStep("a1", "A one")]),
                                    WorkPlanStep("b", "B"; blocked_by = ["a1"]),
                                    WorkPlanStep("c", "C"; blocked_by = ["missing"]),
                                    WorkPlanStep("d", "D"; status = :in_progress, blocked_by = ["a"])])
        @test [is_work_plan_step_blocked(plan, step) for step in plan.steps] == [false, true, false, false]
        plan.steps[1].children[1].status = :completed
        @test !is_work_plan_step_blocked(plan, plan.steps[2])
        # A step that no plan holds is never blocked, and shows no blocker.
        alone = WorkPlanStep("e", "Alone"; blocked_by = ["a"])
        @test alone.plan === nothing && compute_item_facet(alone, Val(:blocked)) === false
        @test format_tree_node_label(alone) == "Alone · pending"
    end

    @testset "the words of the progress" begin
        plan = _workplan_make()
        @test describe_work_plan_progress(plan) ==
              "2 of 7 completed, 1 in progress, 1 pending, 1 blocked, 1 skipped, 1 deferred"
        @test format_tree_node_label(plan) == "Fix the parser · " * describe_work_plan_progress(plan)
        @test describe_work_plan_progress(WorkPlan("empty")) == "no steps"
        @test describe_work_plan_progress(WorkPlan("one"; steps = [WorkPlanStep("1", "Only")])) ==
              "0 of 1 completed, 1 pending"
        # The label of a step that runs is what it shows while it runs.
        @test format_tree_node_label(plan.steps[2]) == "Writing the tests · in progress"
        @test get_tree_node_icon(plan.steps[2]) === :loader && get_tree_node_icon(plan.steps[1]) === :circle_check
        @test get_tree_node_icon(plan.steps[4]) === :skip_forward && get_tree_node_icon(plan.steps[5]) === :circle_pause
        @test get_tree_node_icon(plan) === :list && get_document_title(plan) == "Fix the parser"
        @test get_document_title(WorkPlan("tasks")) == "Plan" && get_document_title(plan.steps[3]) == "Fix the bug"
    end

    @testset "the three contents of a plan" begin
        projection = WorkPlanToWidget()
        plan = _workplan_make()
        iomap = print_document(projection, nothing, plan, nothing)
        root = iomap.output
        parts = [child for child in root.children]
        @test length(parts) == 3
        @test parts[1].content == describe_work_plan_progress(plan)
        @test parts[2].child.value ≈ 2 / 7
        tree = parts[3].child
        @test tree isa DocumentTree && tree.root === plan && tree === plan.link.step_tree
        @test get_tree_children_steps(plan) == ((FieldReferenceStep("steps"),),)
        @test get_tree_children_steps(plan.steps[2]) == ((FieldReferenceStep("children"),),)
        # A path of a step maps into the tree, and back.
        inside = _workplan_path(FieldReferenceStep("children"), ElementReferenceStep(3), FieldReferenceStep("child"),
                                FieldReferenceStep("root"), FieldReferenceStep("steps"), ElementReferenceStep(3))
        @test _nav_is(map_reference_forward(projection, iomap, _workplan_step_path(3)), inside)
        @test _nav_is(map_reference_backward(projection, iomap, inside), _workplan_step_path(3))
        @test has_introduced_step(map_reference_backward(projection, iomap,
                                                         _workplan_path(FieldReferenceStep("children"), ElementReferenceStep(1))))
        # The tree keeps its open nodes when the plan is drawn again, and the view
        # follows the plan.
        tree.expanded = IdDict{Any,Nothing}(plan => nothing, plan.steps[2] => nothing)
        again = print_document(projection, nothing, plan, nothing).output
        @test again.children[3].child === tree && haskey(tree.expanded, plan.steps[2])
        plan.steps[3].status = :completed
        @test parts[1].content == "3 of 7 completed, 1 in progress, 1 pending, 1 skipped, 1 deferred"
        @test parts[2].child.value ≈ 3 / 7

        # A text shows as prose: with no Markdown parser, as a text block.
        @test make_prose_document("# Plan\n\nRead the code.") isa TextBlock
        text = WorkPlan("plan-mode"; text = "# Plan\n\nRead the code.")
        shown = only(collect(print_document(projection, nothing, text, nothing).output.children))
        @test shown isa TextBlock && occursin("Read the code.", get_flat_string(shown))

        # A file shows as a link that opens it.
        file = WorkPlan("file"; uri = "file:///tmp/plan.md")
        link = only(collect(print_document(projection, nothing, file, nothing).output.children))
        @test link isa WidgetButton && link.action.label == "/tmp/plan.md"
        open = read_bound_gesture(link, MouseClick(:left, 0, 0, 1, ModifierKeys(); time = 0.0), nothing)
        @test open isa OpenFileOperation && open.path == "/tmp/plan.md"
        # A plan with no content shows its steps, which say that there are none.
        empty = print_document(projection, nothing, WorkPlan("empty"), nothing).output
        @test collect(empty.children)[1].content == "no steps"
    end

    @testset "a file keeps the plan, and a copy links its steps to the copy" begin
        plan = _workplan_make()
        (positional, keywords) = pred_arguments(plan)
        @test positional == ("tasks",) && first.(keywords) == [:title, :steps, :text, :uri]
        read = parse_pred_text(print_pred_text(plan))
        @test read isa WorkPlan && read.title == "Fix the parser" && length(read.steps) == 5
        @test read.steps[2].children[1].id == "2a" && read.steps[2].active_title == "Writing the tests"
        @test collect(read.steps[3].blocked_by) == ["2"] && read.steps[4].reason == "The guide says it already."
        @test read.steps[5].priority === :low && read.steps[5].status === :deferred
        @test read.steps[3].plan.plan === read && is_work_plan_step_blocked(read, read.steps[3])
        copied = copy_document(plan)
        @test copied !== plan && copied.steps[3] !== plan.steps[3]
        @test copied.steps[3].plan.plan === copied && copied.steps[2].children[1].plan.plan === copied
        @test plan.steps[3].plan.plan === plan
        copied.steps[2].status = :completed
        @test !is_work_plan_step_blocked(copied, copied.steps[3]) && is_work_plan_step_blocked(plan, plan.steps[3])
        @test copy_document(plan.steps[2]).plan === nothing
        # A walk of the documents finds each step once, at its place in the plan.
        @test length(search_documents(plan, node -> node isa WorkPlanStep)) == 7
    end

    @testset "in an editor, the tree of the steps follows a status, and a double click opens a step" begin
        plan = _workplan_make()
        navigator = Navigator(plan)
        editor, backend = _nav_editor(navigator)
        @test _nav_has_text(backend, "2 of 7 completed, 1 in progress")
        @test _nav_has_text(backend, "Writing the tests · in progress")
        @test _nav_has_text(backend, "Fix the bug · blocked by step 2")
        plan.steps[2].status = :completed
        run_frame!(editor)
        @test _nav_has_text(backend, "Write the tests · completed")
        @test _nav_has_text(backend, "Fix the bug · pending")
        @test !_nav_has_text(backend, "blocked by step 2")
        click = _nav_click(backend, "Fix the bug · pending")
        @test click !== nothing
        _nav_press!(editor, backend, click, _doctree_double(click))
        @test get_navigator_page(navigator) === plan.steps[3]
        @test _nav_is(navigator.address, _workplan_step_path(3))
        @test _nav_has_text(backend, "status pending · priority medium")
        @test _nav_has_text(backend, "The parser drops a comma.")
    end

    @testset "a link on the page of a step opens the step that it waits for" begin
        plan = _workplan_make()
        navigator = Navigator(plan, _workplan_step_path(3))
        editor, backend = _nav_editor(navigator)
        @test get_navigator_page(navigator) === plan.steps[3]
        @test _nav_has_text(backend, "status blocked by step 2 · priority medium")
        @test _nav_has_text(backend, "blocked by")
        link = _nav_click(backend, "step 2")
        @test link !== nothing
        _nav_press!(editor, backend, link)
        @test get_navigator_page(navigator) === plan.steps[2]
        @test _nav_is(navigator.address, _workplan_step_path(2))
        @test _nav_has_text(backend, "while it runs: Writing the tests")
        back = _nav_click(backend, _NAV_BACK)
        _nav_press!(editor, backend, back)
        @test get_navigator_page(navigator) === plan.steps[3]
        # A step that no plan holds shows the ids that it waits for, with no link.
        lone = Navigator(WorkPlanStep("x", "Alone"; blocked_by = ["7"]))
        _, lone_backend = _nav_editor(lone)
        @test _nav_has_text(lone_backend, "blocked by") && _nav_has_text(lone_backend, "7")
        @test !_nav_has_text(lone_backend, "step 7")
    end

    @testset "a roster of the steps has the facet blocked" begin
        plan = _workplan_make()
        @test first.(collect_item_facets(WorkPlanStep)) == ["blocked", "type"]
        roster = link_roster!(Roster(CollectionItems(plan.steps); columns = ["id", "status", "blocked"]), plan.steps)
        @test [row.values for row in roster.rows] ==
              [["1", :completed, false], ["2", :in_progress, false], ["3", :pending, true],
               ["4", :skipped, false], ["5", :deferred, false]]
        plan.steps[2].status = :completed
        @test roster.rows[3].values[3] == false
    end
end
end
