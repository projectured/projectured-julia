"""
    test_assistant_work()

The work page of an assistant, in a real editor, against a scripted connection:
the page shows the job, the plan with its tree of steps and the tree of the work
with a subagent and a background task; a double click on the subagent opens its
page with its transcript, Back and Parent return; a double click on the
background task opens its detail; Cancel of a subagent reaches the agent; the
column `plan` of the list of the assistants follows a plan; the Work button of
the list opens one tab; the verb answers the page in its window; and an Explorer
shows the turns of an assistant, where a press on a turn or a tool call shows it
as the page of the navigator.
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
                         "1 of 3 completed", "Work", "This session",
                         "The agent gives no process.",
                         "warning · Retrying — The model is busy")
                @test _work_page_has_text(backend, text)
            end
            # A row of a tree draws its name, then the detail of its decoration.
            for (label, detail) in (("Writing the code", "in progress"), ("Explore", "running"),
                                    ("watch the build", "running"))
                @test _work_page_has_row(backend, label, detail)
            end
            # The tree of the work keeps its open nodes when the page draws again.
            @test haskey(work.work_tree.expanded, work)
        end

        @testset "the pointer on a link of the page of the work of an agent draws the line under it" begin
            a, _ = _make_worked_assistant()
            editor, backend = _work_page_editor(Navigator(a.agent_work))
            drawing() = last(ProjecturedKernelExample.rendered_output(backend))
            # The links of the subagents stand in the last card of the page.
            texts = _work_page_texts(backend)
            index = findlast(entry -> startswith(entry[1], "Explore"), texts)
            @test index !== nothing
            (text, x, y) = texts[index]
            @test !is_link_text_underlined(drawing(), text)
            _work_page_press!(editor, backend, MouseMove(x + 2, y + 2; time = 0.0))
            @test is_link_text_underlined(drawing(), text)
        end

        @testset "a double click opens a subagent; Back and Parent return" begin
            a, connection = _make_worked_assistant()
            work = AssistantWork(a)
            navigator = Navigator(work)
            editor, backend = _work_page_editor(navigator)
            child = only(collect(a.agent_work.subagents))
            _work_page_double_click!(editor, backend, "Explore"; exact = true)
            @test get_navigator_page(navigator) === child
            @test _work_page_is(navigator.address, FieldReferenceStep("subagents"),
                                ElementReferenceStep(1))
            for text in ("Subagent", "Type: Explore the tests", "State: running",
                         "Transcript", "Find the tests", "The tests are in test/.",
                         "Cancel")
                @test _work_page_has_text(backend, text)
            end
            # Cancel asks the agent of the session that holds the subagent.
            list = get_session_assistant_list(; editor)
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
            _work_page_double_click!(editor, backend, "Explore"; exact = true)
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
            _work_page_double_click!(editor, backend, "watch the build"; exact = true)
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
            # A task that runs says in its node when it started, and reads no clock.
            execution = get_current_task_execution(document)
            started = Libc.strftime("%H:%M:%S", execution.start_time)
            @test format_tree_node_label(document) == "watch the build"
            @test get_document_decoration(document).detail == "running since " * started
            @test get_document_decoration(document).icon === :loader
            # A task that ended says how long it ran.
            ended = AgentBackgroundTaskUpdate("bg1"; status = :completed,
                                              end_time = execution.start_time + 2)
            apply_agent_event!((document = a,), a, ended)
            drain_task_feed!()
            @test format_tree_node_label(document) == "watch the build"
            @test get_document_decoration(document).detail == format_elapsed_time(2.0; precision = 1)
            @test [count.text for count in get_document_decoration(document).counts] == ["DONE"]
            # A task that ended can not be stopped.
            EditorModule.run_frame!(editor)
            @test !_work_page_has_text(backend, "Stop")
        end

        @testset "a summary is a block of lines, and a label is one line" begin
            a, _ = _make_worked_assistant()
            child = only(collect(a.agent_work.subagents))
            child.title = "Explore\nthe tests"
            child.summary = "Read two files:\n1. todo.txt\n2. notes.txt"
            plans = collect(a.agent_work.plans)
            plan = first(plan for plan in plans if !isempty(plan.steps))
            first(collect(plan.steps)).title = "Read\nthe code"
            editor, backend = _work_page_editor(Navigator(AssistantWork(a)))
            texts = [entry[1] for entry in _work_page_texts(backend)]
            @test !any(text -> occursin('\n', text), texts)
            @test _work_page_has_row(backend, "Explore the tests", "running since ")
            @test _work_page_has_row(backend, "Read the code", "completed")
            _work_page_double_click!(editor, backend, "Explore the tests"; exact = true)
            texts = [entry[1] for entry in _work_page_texts(backend)]
            @test !any(text -> occursin('\n', text), texts)
            @test all(in(texts), ("Explore the tests", "Summary:", "Read two files:",
                                  "1. todo.txt", "2. notes.txt"))
            task = AgentBackgroundTask("s", "t", :local_bash, "watch\nthe build", "", "",
                                       "", "one\ntwo", false)
            @test format_task_parameters(task) == "watch the build"
            @test "summary: one two" in format_task_details(task, nothing)
        end

        @testset "the shown page is in a tab of any window, and no walk finds it" begin
            a, _ = _make_worked_assistant()
            b, _ = _make_worked_assistant()
            work = AssistantWork(a)
            make_tree(name, page) =
                PaneTree(PaneGroup(PaneTab[PaneTab(name, PrimitiveString(name)),
                                           PaneTab("Work", Navigator(page))]))
            first_tree = make_tree("x", AssistantWork(b))
            second_tree = make_tree("y", work)
            screen = ScreenDocument([WindowDocument(; id = :one, content = first_tree),
                                     WindowDocument(; id = :two,
                                                    content = UndoBuffer(second_tree))])
            routes = AssistantModule._collect_window_tree_routes(screen)
            @test length(routes) == 2
            @test last(routes[1]) === first_tree && last(routes[2]) === second_tree
            editor = (document = screen,)
            (shown, steps) = AssistantModule._get_shown_assistant_work(editor, a)
            @test shown === work
            tab = try_evaluate_reference(screen, Reference(steps...), nothing)
            @test tab isa PaneTab && tab.content.content === work
            other = Assistant()
            @test AssistantModule._get_shown_assistant_work(editor, other) === nothing
        end

        @testset "the column plan of the list of the assistants follows a plan" begin
            a, _ = _make_worked_assistant()
            list = AssistantList()
            set_assistant_list_source!(list, () -> [a])
            _, iomap = _print_assistant_list(list; width = 1800)
            words = _collect_assistant_list_words(iomap)
            @test all(in(words), ("plan", "subagents", "tasks", "Work"))
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
            (shown, _) = AssistantModule._get_shown_assistant_work(editor, a)
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
            @test first(AssistantModule._get_shown_assistant_work(editor, a)) === shown
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
            turns = (FieldReferenceStep("conversation"), FieldReferenceStep("turns"))
            @test get_tree_children_steps(work) == children
            # A subagent and an assistant also have the turns of their conversation.
            @test get_tree_children_steps(child) == (children..., turns)
            @test get_tree_children_steps(a) ==
                  ((FieldReferenceStep("agent_work"), FieldReferenceStep("subagents")),
                   (FieldReferenceStep("agent_work"), FieldReferenceStep("background_tasks")), turns)
            @test format_tree_node_label(work) == "This session"
            @test get_document_decoration(work).icon === :bot
            @test get_document_decoration(child).icon === :loader
            child.last_tool = "Grep"
            child.token_count = 1200
            # A subagent that runs says when it started, and reads no clock.
            started = Libc.strftime("%H:%M:%S", child.start_time)
            @test format_tree_node_label(child) == "Explore"
            @test get_document_decoration(child).detail == "running since " * started * " · Grep · 1k tokens"
            child.state = :requires_action
            @test get_document_decoration(child).detail == "waits for you · 1k tokens"
            @test get_document_decoration(child).icon === :warning
            # One that ended says how long it worked.
            child.state = :idle
            child.duration = 75.0
            @test get_document_decoration(child).detail == "idle · 1:15 · 1k tokens"
            @test pred_arguments(work) == ((a,), Pair{Symbol,Any}[])
            @test is_walk_opaque(work) && !has_document_duplicate(work)
            @test search_references(work, node -> node === child) |> isempty
        end

        @testset "an Explorer shows the turns of an assistant, and a press shows a turn or a part as its page" begin
            grep = AgentToolCallUpdate("c1"; name = "Grep", status = :completed,
                                       input = Dict{String,Any}("pattern" => "outline"), output = "a.jl")
            connection = ScriptedAgentConnection([Any[
                grep, LlmTextStart(), LlmTextDelta("Found the outline."), LlmTextStop()]])
            a = _make_agent_assistant(connection)
            _submit_to_agent!(a, "Find the outline")
            turns = collect(a.conversation.turns)
            asked = turns[findlast(turn -> turn.role === :user, turns)]
            index = findlast(turn -> turn.role === :assistant, turns)
            answer = turns[index]
            parts = collect(answer.parts)
            k = findfirst(part -> part.content isa EvaluatorForm, parts)
            @test format_tree_node_label(asked) == "You · Find the outline"
            @test format_tree_node_label(answer) == "Assistant · Found the outline."
            @test format_tree_node_label(parts[k]) == "tool · Grep \"outline\""
            explorer = Explorer(ExplorerSection("Explorer", Any[a]))
            navigator = explorer.navigator
            # The rows of the conversation draw a turn and a part, as in the
            # application.
            measure = FixedMeasure(8, 12, 4, 0)
            rows = Pair{Type,Any}[make_conversation_draft_row(; measure), make_conversation_row(; measure)]
            editor, backend = _work_page_editor(explorer; extra = rows)
            # The tree and the page draw the same texts, so a press goes to the
            # text in the tree, the one at the left.
            press!(label) = _work_page_press!(editor, backend, ProjecturedPlatformTest._explorer_click(backend, label))
            for label in (format_tree_node_label(a), format_tree_node_label(answer))
                chevron = ProjecturedPlatformTest._explorer_open_chevron(backend, label)
                @test chevron !== nothing
                _work_page_press!(editor, backend, chevron)
            end
            for label in ("You · Find the outline", "tool · Grep \"outline\"", "Found the outline.")
                @test ProjecturedPlatformTest._explorer_click(backend, label) !== nothing
            end
            answer_steps = (FieldReferenceStep("entries"), ElementReferenceStep(1),
                            FieldReferenceStep("conversation"), FieldReferenceStep("turns"),
                            ElementReferenceStep(index))
            press!(format_tree_node_label(answer))
            @test get_navigator_page(navigator) === answer
            @test _work_page_is(navigator.address, answer_steps...)
            press!("tool · Grep \"outline\"")
            @test get_navigator_page(navigator) === parts[k]
            @test _work_page_is(navigator.address, answer_steps..., FieldReferenceStep("parts"), ElementReferenceStep(k))
            # The page draws the tool call, right of the tree.
            tree_x = ProjecturedPlatformTest._explorer_click(backend, "tool · Grep \"outline\"").x
            @test any(entry -> occursin("Grep", entry[1]) && entry[2] > tree_x + 100, _work_page_texts(backend))
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

# An editor whose document is `document`, drawn by the natural renderer with the
# rows `extra` in front of its own, after its first frame.
function _work_page_editor(document; tabs::Bool = false, extra = Pair{Type,Any}[])
    backend = HeadlessBackend()
    natural = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0), extra)
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

# Whether the last frame draws `label`, and right after it a text that starts with
# `detail`, as a row of a tree draws its name and the detail of its decoration.
function _work_page_has_row(backend, label, detail)
    texts = [entry[1] for entry in _work_page_texts(backend)]
    any(k -> texts[k] == label && startswith(texts[k + 1], detail), 1:(length(texts) - 1))
end

function _work_page_double_click!(editor, backend, text; exact::Bool = false)
    click = _work_page_click(backend, text; exact)
    double = MouseClick(click.button, click.x, click.y, 2, ModifierKeys(); time = 0.0)
    _work_page_press!(editor, backend, click, double)
end

# Whether `reference` names the steps `steps`, whatever its types.
_work_page_is(reference, steps...) =
    get_reference_steps(strip_reference_types(reference)) == collect(steps)
