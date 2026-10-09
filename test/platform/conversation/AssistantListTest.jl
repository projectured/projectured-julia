"""
    test_assistant_list()

The list of the open assistants: the read of the tabs of a pane tree, the rows
that follow the tabs and not the edits inside them, each way a tab comes and
goes, and the one list of the session.
"""
function test_assistant_list()
    @testset "the list of the open assistants" begin
        @testset "the read of the tabs" begin
            one, two = Assistant(), Assistant()
            notes = PrimitiveString("notes")
            left = PaneGroup([PaneTab("One", one), PaneTab("Notes", notes)])
            right = PaneGroup([PaneTab("Two", UndoBuffer(two))])
            tree = PaneTree(PaneSplit(:vertical, [left, right]))
            # An assistant inside a history counts; a text inside an assistant does not.
            @test _is_same_list(collect_pane_tab_contents(tree, Assistant), [one, two])
            @test _is_same_list(collect_pane_tab_contents(tree, PrimitiveString), [notes])
            @test isempty(collect_pane_tab_contents(PaneTree(PaneGroup(PaneTab[])), Assistant))
        end

        @testset "the rows follow the tabs, not the edits inside them" begin
            one = Assistant()
            group = PaneGroup([PaneTab("One", one)])
            tree = PaneTree(group)
            list = AssistantList()
            @test isempty(list.assistants)
            reads = Ref(0)
            set_assistant_list_source!(list, () -> (reads[] += 1; collect_pane_tab_contents(tree, Assistant)))
            @test _is_same_list(list.assistants, [one])
            @test reads[] == 1
            one.description.value = "Fix the table"
            push!(one.conversation.turns, ConversationTurn(:user, [ConversationPart("Hello")]))
            @test _is_same_list(list.assistants, [one])
            @test reads[] == 1
            set_assistant_list_source!(list, nothing)
            @test isempty(list.assistants)
        end

        @testset "each way a tab comes and goes" begin
            one, two = Assistant(), Assistant()
            group = PaneGroup([PaneTab("One", one), PaneTab("Two", two)])
            tree = PaneTree(group)
            editor = _AssistantListMockEditor(tree)
            list = AssistantList()
            set_assistant_list_source!(list, () -> collect_pane_tab_contents(tree, Assistant))
            @test _is_same_list(list.assistants, [one, two])
            # A close takes the row out, and the undo of the close brings it back.
            inverse = evaluate_invertible_operation!(editor, make_pane_close_tab_operation(tree, group, 1))
            @test _is_same_list(list.assistants, [two])
            evaluate_operation(editor, inverse)
            @test _is_same_list(list.assistants, [one, two])
            # An empty assistant opens in a tab.
            three = Assistant()
            evaluate_operation(editor, make_pane_open_tab_operation(tree, group, PaneTab("Three", three)))
            @test _is_same_list(list.assistants, [one, two, three])
            # The duplicate of a tab is a fork, which is an assistant of its own.
            evaluate_operation(editor, make_pane_duplicate_tab_operation(tree, group, 2))
            @test length(list.assistants) == 4
            @test all(a -> list.assistants[3] !== a, (one, two, three))
            # An assistant that an empty tab takes counts at once.
            evaluate_operation(editor, make_pane_open_tab_operation(tree, group, default_new_pane_tab()))
            @test length(list.assistants) == 4
            four = Assistant()
            group.tabs[length(group.tabs)].content = four
            @test list.assistants[end] === four
        end

        @testset "the list of the session" begin
            session = get_session_assistant_list()
            @test session isa AssistantList
            @test get_session_assistant_list() === session
            @test make_insertion_document(AssistantList) === session
            @test get_document_title(session) == "Assistants"
            # A file keeps that a tab shows the list, and a load gives the list of the session.
            tree = PaneTree(PaneGroup([PaneTab("Assistants", session), PaneTab("One", Assistant())]))
            loaded = parse_pred_text(print_pred_text(tree))
            @test loaded.root.tabs[1].content === session
            @test length(collect_pane_tab_contents(loaded, Assistant)) == 1
            # The walk of the documents reaches an assistant through its tab, not through the list.
            one = Assistant()
            list = AssistantList()
            tree = PaneTree(PaneGroup([PaneTab("Assistants", list), PaneTab("One", one)]))
            set_assistant_list_source!(list, () -> collect_pane_tab_contents(tree, Assistant))
            @test _is_same_list(list.assistants, [one])
            found = search_references(tree, node -> node isa Assistant)
            @test length(found) == 1
            @test evaluate_reference(tree, only(found)) === one
        end

        @testset "the Assistants pane" begin
            list = AssistantList()
            projection, iomap = _print_assistant_list(list)
            @test "No assistant is open in this window." in _collect_assistant_list_words(iomap)
            first_assistant = Assistant(; llm = FakeLlm("ok"), work_state = :in_progress)
            second_assistant = Assistant()
            tree = PaneTree(PaneGroup([PaneTab("A", first_assistant), PaneTab("B", second_assistant)]))
            shown = Any[]
            set_assistant_list_source!(list, () -> collect_pane_tab_contents(tree, Assistant))
            set_assistant_list_opener!(list, (editor, assistant) -> push!(shown, assistant))
            first_assistant.input.value = "Fix the table"
            evaluate_operation((document = first_assistant, tools = register_default_tools!(ToolSet())),
                               SubmitProseOperation(first_assistant))
            @test timedwait(() -> first_assistant.status !== :streaming, 10.0; pollint = 0.01) === :ok
            # The drawn pane follows the list and each assistant.
            words = _collect_assistant_list_words(iomap)
            @test "2 conversations · 0 running" in words
            @test all(in(words), ("title", "work", "turn", "activity", "prompts", "context", "started", "elapsed"))
            @test "Fix the table" in words && "Assistant" in words
            @test "in progress" in words && "pending" in words
            @test count(==("you"), words) == 2
            @test count(==("Show"), words) == 2
            # A turn that runs: the row says whose turn it is and what the turn does.
            second_assistant.status = :streaming
            push!(second_assistant.conversation.turns, ConversationTurn(:assistant; start_time = time()))
            words = _collect_assistant_list_words(iomap)
            @test "2 conversations · 1 running" in words
            @test "assistant" in words && "starts" in words
            second_assistant.status = :idle
            words = _collect_assistant_list_words(iomap)
            @test count(==("you"), words) == 2 && !("starts" in words)
            # Show gives the opener the assistant of its row.
            texts = _collect_assistant_list_texts(iomap.output)
            show = first(sort([t for t in texts if t[3] == "Show"]; by = t -> t[2]))
            operation = read_intent(projection, iomap,
                MouseClick(:left, show[1] + 2, show[2] + 2, ModifierKeys(); time = 0.0))
            @test operation isa InvokeActionOperation
            operation.action.callback(nothing)
            @test length(shown) == 1 && only(shown) === first_assistant
        end
    end
end

# The editor that a pane operation is evaluated against.
mutable struct _AssistantListMockEditor
    document::Any
end

_is_same_list(found, expected) =
    length(found) == length(expected) && all(map(===, collect(found), expected))

# The pane with the theme that the slice registers it with, and its widgets drawn
# on a canvas at the size of a window.
function _print_assistant_list(list; width = 1400, height = 600)
    appearance = Appearance()
    measure = FixedMeasure(10, 18, 6, 0)
    pane = AssistantListToWidgetPane(get_scaled_theme!(appearance, ConversationTheme))
    widgets = RecursiveProjection(TypeDispatchingProjection(
        WidgetToGraphics(; measure, theme = get_scaled_theme!(appearance, WidgetTheme),
                         graphics_theme = get_scaled_theme!(appearance, GraphicsTheme)).dispatch))
    projection = ChainingProjection(pane, widgets)
    context = with_exact_size(PrinterContext(); width = Cell(Int32(width)), height = Cell(Int32(height)))
    (projection, print_document(projection, nothing, list, context))
end

# Each text of a drawn pane with its place on the canvas.
function _collect_assistant_list_texts(node, x = 0, y = 0, found = Tuple{Int,Int,String}[])
    if node isa GraphicsCanvas
        elements = node.elements
        if elements isa ListNode
            link = elements
            while link !== nothing
                _collect_assistant_list_texts(link.value, x + Int(node.x), y + Int(node.y), found)
                link = link.next
            end
        else
            for element in elements
                _collect_assistant_list_texts(element, x + Int(node.x), y + Int(node.y), found)
            end
        end
    elseif node isa GraphicsViewport
        _collect_assistant_list_texts(node.content, x + Int(node.x), y + Int(node.y), found)
    elseif node isa GraphicsText
        push!(found, (x + Int(node.x), y + Int(node.y), String(node.text)))
    end
    found
end

_collect_assistant_list_words(iomap) = [text for (_, _, text) in _collect_assistant_list_texts(iomap.output)]
