# The verbs of tasks over a group of plain shell commands: a group is listed,
# found, described with its tasks and its facts, read, stopped, run again and
# closed, and a model may call each verb. The editor is a document in a struct,
# so each verb runs at once on the calling task. The probe tasks are those of
# `TaskGroupTest.jl` and `TaskGroupToWidgetTest.jl`.

mutable struct _TaskVerbsProbeEditor
    document::Any
end

function test_task_group_verbs()
    @testset "task group verbs" begin
        tasks = [_TaskViewProbeTask(name, name == "fail" ? "echo oops >&2; exit 1" : "echo $name")
                 for name in ("alpha", "fail")]
        group = wrap_task_group_document(TaskGroup(tasks; name = "verbs", jobs = 2);
                                         title = "the verbs")
        editor = _TaskVerbsProbeEditor(PaneTree(PaneGroup(PaneTab[PaneTab("verbs", group)])))
        start_task_group_document!(group)
        @test wait_for_task_group!(editor, group) === group
        identifier = getfield(group, :identifier)[]

        @testset "a group is listed and found" begin
            line = only(l for l in split(string(list_task_groups(; editor)), "\n")
                        if startswith(l, identifier * " "))
            @test occursin("the verbs", line) && occursin("2/2", line)
            @test find_task_group(identifier; editor) === group
            @test find_task_group("the verbs"; editor) === group
            @test find_task_group("no such group"; editor) === nothing
        end

        @testset "a group and a task are described with the facts of their kind" begin
            summary = compute_task_group_summary(get_task_group(group)).summary
            text = string(describe_task_group(group; editor))
            @test startswith(text, summary)
            @test occursin("2. fail — ERROR (unexpected)", text) && !occursin("1. alpha", text)
            @test occursin("1. alpha — DONE", string(describe_task_group(group; tasks = :all, editor)))
            detail = string(describe_task(group, 2; editor))
            @test occursin("script: echo oops", detail) && occursin("ended: ERROR", detail)
            @test occursin("stderr:\noops", detail)
            @test occursin("executions: 1", detail) && !occursin("earlier", detail)
            @test string(get_task_output(group, 1; editor)) == "alpha"
            @test string(get_task_output(group, 2; stream = :stderr, editor)) == "oops"
        end

        @testset "a group is stopped, run again and closed" begin
            @test string(stop_task!(group, 1; editor)) == "Stopping task 1."
            @test rerun_tasks!(group; which = :all, wait = true, editor) === group
            @test build_task_group_document_counts(group)[:done] == 1
            detail = string(describe_task(group, 2; editor))
            @test occursin("executions: 2", detail)
            @test occursin(r"earlier 1: started \d\d:\d\d:\d\d — ERROR", detail)
            @test occursin("Closed the group " * identifier, string(close_task_group!(group; editor)))
            @test isempty(get_pane_groups(editor.document)[1].tabs)
            @test !any(g -> g === group, get_session_task_group_list().groups)
        end

        @testset "a model may call every verb" begin
            names = only(names for (owner, names) in make_task_api() if owner === TaskModule)
            @test :describe_task_group in names && :close_task_group! in names
            @test all(name -> isdefined(TaskModule, name), names)
        end
    end
end
