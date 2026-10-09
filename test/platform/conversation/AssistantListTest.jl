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
    end
end

# The editor that a pane operation is evaluated against.
mutable struct _AssistantListMockEditor
    document::Any
end

_is_same_list(found, expected) =
    length(found) == length(expected) && all(map(===, collect(found), expected))
