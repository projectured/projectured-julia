"""
    test_assistant_work()

The work page of an assistant, in a real editor, against a scripted connection:
the page shows the job, the plan with its tree of steps and the tree of the work
with a subagent and a background task; a double click on the subagent opens its
page with its transcript, Back and Parent return; a double click on the
background task opens its detail; Cancel of a subagent reaches the agent; the
column `plan` of the list of the assistants follows a plan; the Work button of
the list opens one tab; and the verb answers the page in its window.
"""
function test_assistant_work()
    @testset "the work page of an assistant" begin
        @testset "the page shows the job, the plan and the tree of the work" begin
            a, _ = _make_worked_assistant()
            work = AssistantWork(a)
            @test get_document_title(work) == "Work · Fix the tests"
            @test work.subagents === a.agent_work.subagents
            @test work.plans === a.agent_work.plans
            @test work.process_tree === nothing
            editor, backend = _work_page_editor(Navigator(work))
            for text in ("The job", "Fix the tests", "First prompt: Fix the tests",
                         "Plan of the plan mode", "First read, then write.", "Now",
                         "Step: Writing the code", "Context: not known yet", "tasks",
                         "1 of 3 completed", "Writing the code · in progress", "Work",
                         "This session", "Explore · running", "watch the build · running",
                         "The agent gives no process.",
                         "warning · Retrying — The model is busy")
                @test _work_page_has_text(backend, text)
            end
            # The tree of the work keeps its open nodes when the page draws again.
            @test haskey(work.work_tree.expanded, work)
        end

        @testset "a double click opens a subagent; Back and Parent return" begin
            a, connection = _make_worked_assistant()
            work = AssistantWork(a)
            navigator = Navigator(work)
            editor, backend = _work_page_editor(navigator)
            child = only(collect(a.agent_work.subagents))
            _work_page_double_click!(editor, backend, "Explore · running")
            @test get_navigator_page(navigator) === child
            @test _work_page_is(navigator.address, FieldReferenceStep("subagents"),
                                ElementReferenceStep(1))
            for text in ("Subagent", "Type: Explore the tests", "State: running",
                         "Transcript", "Find the tests", "The tests are in test/.",
                         "Cancel")
                @test _work_page_has_text(backend, text)
            end
            # Cancel asks the agent of the session that holds the subagent.
            list = get_session_assistant_list()
            previous = list.source
            set_assistant_list_source!(list, () -> [a])
            try
                _work_page_press!(editor, backend, _work_page_click(backend, "Cancel"))
                is_cancelled() = !isempty(connection.subagent_cancels)
                @test timedwait(is_cancelled, 10.0; pollint = 0.01) === :ok
                @test connection.subagent_cancels == ["scripted-session-1" => "sub1"]
            finally
                set_assistant_list_source!(list, previous)
            end
            _work_page_press!(editor, backend, _work_page_click(backend, _WORK_PAGE_BACK))
            @test get_navigator_page(navigator) === work
            @test _work_page_has_text(backend, "The job")
            # Parent from the page of a subagent comes back to the work page.
            _work_page_double_click!(editor, backend, "Explore · running")
            @test get_navigator_page(navigator) === child
            parent = _work_page_click(backend, _WORK_PAGE_PARENT)
            _work_page_press!(editor, backend, parent)
            @test get_navigator_page(navigator) === work
            @test navigator.address isa EmptyReference
        end

        @testset "a double click on a background task opens its detail" begin
            a, _ = _make_worked_assistant()
            work = AssistantWork(a)
            navigator = Navigator(work)
            editor, backend = _work_page_editor(navigator)
            _work_page_double_click!(editor, backend, "watch the build · running")
            document = only(collect(a.agent_work.background_tasks))
            @test get_navigator_page(navigator) === document
            @test _work_page_is(navigator.address, FieldReferenceStep("background_tasks"),
                                ElementReferenceStep(1))
            # The page of the task: its name, its state, the facts of its kind and
            # its streams. The editor does not start a task of an agent, so the page
            # has no Run again.
            for text in ("watch the build", "running", "kind: local_bash", "stdout", "stderr")
                @test _work_page_has_text(backend, text)
            end
            @test !_work_page_has_text(backend, "Run again")
            # Stop while the agent can stop the task, and the link to its output.
            update = AgentBackgroundTaskUpdate("bg1"; can_stop = true,
                                               output_uri = "file:///var/tmp/bg1.output")
            apply_agent_event!((document = a,), a, update)
            EditorModule.run_frame!(editor)
            @test _work_page_has_text(backend, "Stop")
            @test _work_page_has_text(backend, "Open the output")
            @test startswith(format_tree_node_label(document), "watch the build · running · ")
            @test get_tree_node_icon(document) === :loader
        end

        @testset "the column plan of the list of the assistants follows a plan" begin
            a, _ = _make_worked_assistant()
            list = AssistantList()
            set_assistant_list_source!(list, () -> [a])
            _, iomap = _print_assistant_list(list; width = 1800)
            words = _collect_assistant_list_words(iomap)
            @test all(in(words), ("plan", "subagents", "background tasks", "Work"))
            @test "1/3" in words
            entries = [AgentPlanEntry("Read the code", :high, :completed; id = "1"),
                       AgentPlanEntry("Write the code", :medium, :completed; id = "2"),
                       AgentPlanEntry("Run the tests", :low, :in_progress; id = "3")]
            apply_agent_event!((document = a,), a, AgentPlanUpdate(entries; id = "tasks"))
            words = _collect_assistant_list_words(iomap)
            @test "2/3" in words && !("1/3" in words)
        end

        @testset "the Work button of the list opens one tab; the verb answers it" begin
            a, _ = _make_worked_assistant()
            list = AssistantList()
            set_assistant_list_source!(list, () -> [a])
            editor, backend = _work_page_editor(list; tabs = true)
            count_tabs() =
                length(search_references(editor.document, node -> node isa PaneTab))
            press_work() = _work_page_click(backend, "Work"; exact = true)
            @test count_tabs() == 1
            _work_page_press!(editor, backend, press_work())
            EditorModule.run_frame!(editor)
            @test count_tabs() == 2
            shown = AssistantModule._get_shown_assistant_work(editor, a)
            @test shown isa AssistantWork && shown.assistant === a
            @test _work_page_has_text(backend, "The job")
            # The list again, and a second press shows the same tab.
            is_list_tab(node) = node isa PaneTab && node.content === list
            found = search_references(editor.document, is_list_tab)
            focus_pane!(only(found); editor)
            EditorModule.run_frame!(editor)
            @test !_work_page_has_text(backend, "The job")
            _work_page_press!(editor, backend, press_work())
            EditorModule.run_frame!(editor)
            @test count_tabs() == 2
            @test _work_page_has_text(backend, "The job")
            @test AssistantModule._get_shown_assistant_work(editor, a) === shown
            # The verb shows the same page and answers it in its window.
            answer = show_assistant_work!(a; editor)
            @test answer isa ReferencedDocument
            @test get_document(answer) === shown
            path = get_reference(answer)
            @test try_evaluate_reference(editor.document, path, nothing) === shown
            @test count_tabs() == 2
        end

        @testset "the nodes of the tree of the work, and a file of the page" begin
            a, _ = _make_worked_assistant()
            work = AssistantWork(a)
            child = only(collect(a.agent_work.subagents))
            children = ((FieldReferenceStep("subagents"),),
                        (FieldReferenceStep("background_tasks"),))
            @test get_tree_children_steps(work) == children
            @test get_tree_children_steps(child) == get_tree_children_steps(work)
            @test format_tree_node_label(work) == "This session"
            @test get_tree_node_icon(work) === :bot
            @test get_tree_node_icon(child) === :loader
            child.last_tool = "Grep"
            child.token_count = 1200
            @test format_tree_node_label(child) ==
                  "Explore · running · Grep · 1k tokens"
            child.state = :requires_action
            @test format_tree_node_label(child) == "Explore · waits for you · 1k tokens"
            @test get_tree_node_icon(child) === :warning
            @test pred_arguments(work) == ((a,), Pair{Symbol,Any}[])
            @test is_walk_opaque(work) && !has_document_duplicate(work)
            @test search_references(work, node -> node === child) |> isempty
        end
    end
end

# An assistant whose agent answered one prompt: a plan of steps, a plan of the plan
# mode, a subagent with a prompt and a text, a background task and a notice.
function _make_worked_assistant()
    steps = [AgentPlanEntry("Read the code", :high, :completed; id = "1"),
             AgentPlanEntry("Write the code", :medium, :in_progress; id = "2",
                            active_title = "Writing the code"),
             AgentPlanEntry("Run the tests", :low, :pending; id = "3",
                            blocked_by = ["2"])]
    prompt = LlmMessage(:user, [LlmText("Find the tests")])
    connection = ScriptedAgentConnection([Any[
        AgentPlanUpdate(steps; id = "tasks"),
        AgentPlanUpdate(AgentPlanEntry[]; id = "plan-mode",
                        markdown = "First read, then write."),
        AgentSubagentUpdate("sub1"; title = "Explore", description = "Explore the tests",
                            state = :running, can_cancel = true, event = prompt),
        AgentSubagentUpdate("sub1"; event = LlmTextDelta("The tests are in test/.")),
        AgentBackgroundTaskUpdate("bg1"; kind = :local_bash, title = "watch the build",
                                  status = :running),
        AgentNoticeUpdate(:warning, "Retrying", "The model is busy"),
        LlmTextStart(), LlmTextDelta("Working on it."), LlmTextStop()]])
    a = _make_agent_assistant(connection)
    _submit_to_agent!(a, "Fix the tests")
    a, connection
end

# An editor whose document is `document`, drawn by the natural renderer, after its
# first frame.
function _work_page_editor(document; tabs::Bool = false)
    backend = HeadlessBackend()
    natural = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))
    editor = EditorModule.build_editor(document, natural; backend,
                                       devices = Device[Keyboard(), Mouse(), Display()],
                                       window = false, tabs, appearance = false,
                                       settings = false)
    EditorModule.run_frame!(editor)
    (editor, backend)
end

# The glyphs of Back and Parent in the bar of a navigator.
const _WORK_PAGE_BACK = string(Char(0xe048))
const _WORK_PAGE_PARENT = string(Char(0xe04a))

# Each text of the last frame, at its place, also inside a viewport.
function _work_page_drawn(node, x = 0, y = 0, found = Tuple{String,Int,Int}[])
    node = node isa Cell ? node[] : node
    if node isa GraphicsText
        push!(found, (String(node.text), x + Int(node.x), y + Int(node.y)))
    elseif node isa GraphicsCanvas
        elements = node.elements
        here = (x + Int(node.x), y + Int(node.y))
        if elements isa ListNode
            link = elements
            while link !== nothing
                _work_page_drawn(link.value, here..., found)
                link = link.next
            end
        else
            foreach(element -> _work_page_drawn(element, here..., found), elements)
        end
    elseif node isa GraphicsViewport
        _work_page_drawn(node.content, x + Int(node.x) + round(Int, node.transform.e),
                         y + Int(node.y) + round(Int, node.transform.f), found)
    end
    found
end

_work_page_texts(backend) =
    _work_page_drawn(last(ProjecturedKernelExample.rendered_output(backend)))
_work_page_has_text(backend, text) =
    any(entry -> occursin(text, entry[1]), _work_page_texts(backend))

# A click on the first text of the last frame that holds `text`, or that is
# `text` when `exact`.
function _work_page_click(backend, text; exact::Bool = false)
    texts = _work_page_texts(backend)
    index = findfirst(entry -> exact ? entry[1] == text : occursin(text, entry[1]), texts)
    index === nothing && error("the frame draws no text \"", text, "\"")
    (_, x, y) = texts[index]
    MouseClick(:left, x + 2, y + 2, 1, ModifierKeys(); time = 0.0)
end

function _work_page_press!(editor, backend, events...)
    foreach(event -> ProjecturedKernelExample.push_event!(backend, event), events)
    EditorModule.run_frame!(editor)
end

function _work_page_double_click!(editor, backend, text)
    click = _work_page_click(backend, text)
    double = MouseClick(click.button, click.x, click.y, 2, ModifierKeys(); time = 0.0)
    _work_page_press!(editor, backend, click, double)
end

# Whether `reference` names the steps `steps`, whatever its types.
_work_page_is(reference, steps...) =
    get_reference_steps(strip_reference_types(reference)) == collect(steps)
