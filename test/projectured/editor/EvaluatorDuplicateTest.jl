# The duplicate of an evaluator is a second evaluator that a person drives
# alone: its own forms, code and folds. It shares the results, which can be
# live, and it evaluates in the namespace of its window, as every evaluator of
# the window does.
#
# Uses `_EvaluatorToplevelMockEditor` and `_et_flatten` of
# `EvaluatorToplevelTest.jl`.

using Test
using ProjecturedKernel.ToolModule: ToolSet

"""
    test_evaluator_duplicate()

Run the tests of the evaluator duplicate. No SDL, no network.
"""
function test_evaluator_duplicate()
@testset "Evaluator duplicate" begin

    # Type `code` into the bottom form of `toplevel`, and press Enter.
    function evaluate_code!(editor, toplevel, code)
        toplevel.elements[end].form.value = code
        evaluate_operation(editor, EvaluateSelectedFormOperation(toplevel))
    end

    # An evaluator after two evaluations: code that parses into a Julia document,
    # and code that keeps its string because of its comment.
    function make_session(tools)
        toplevel = make_insertion_document(EvaluatorToplevel)
        editor = _EvaluatorToplevelMockEditor(toplevel, tools)
        evaluate_code!(editor, toplevel, "x = 1 + 1")
        evaluate_code!(editor, toplevel, "\"a;\" * \"b\" # a comment keeps the string")
        toplevel, editor
    end

    @testset "the duplicate owns its forms, its code and its folds" begin
        toplevel, _ = make_session(ToolSet())
        @test has_document_duplicate(toplevel)
        @test !(toplevel.elements[1].form isa PrimitiveString)   # the code parsed
        @test toplevel.elements[2].form isa PrimitiveString

        duplicate = make_document_duplicate(toplevel)
        @test length(duplicate.elements) == length(toplevel.elements) == 3
        @test all(i -> duplicate.elements[i] !== toplevel.elements[i], 1:3)
        @test all(i -> duplicate.elements[i].form !== toplevel.elements[i].form, 1:3)
        @test print_natural_text(duplicate.elements[1].form) ==
              print_natural_text(toplevel.elements[1].form)
        @test duplicate.elements[2].form.value == toplevel.elements[2].form.value
        # The caret is where it was: at the start of the bottom form.
        @test repr(duplicate.selection) == repr(toplevel.selection)

        duplicate.elements[1].form_collapsed = true
        duplicate.elements[2].form.value = "changed"
        @test toplevel.elements[1].form_collapsed === false
        @test toplevel.elements[2].form.value != "changed"
    end

    @testset "the duplicate shares each result, also a live one" begin
        tools = ToolSet()
        toplevel, editor = make_session(tools)
        evaluate_code!(editor, toplevel, "CellVector(@computation Any[1, 2])")
        @test toplevel.elements[3].result isa CellVector

        duplicate = make_document_duplicate(toplevel)
        @test all(i -> duplicate.elements[i].result === toplevel.elements[i].result, 1:3)
        # The cell that holds the result is the duplicate's own.
        @test getfield(duplicate.elements[1], :result) !== getfield(toplevel.elements[1], :result)
    end

    @testset "the duplicate evaluates alone, in the namespace of its window" begin
        tools = ToolSet()
        toplevel, _ = make_session(tools)
        duplicate = make_document_duplicate(toplevel)
        form_count = length(toplevel.elements)

        evaluate_code!(_EvaluatorToplevelMockEditor(duplicate, tools), duplicate, "x + 10")
        @test length(duplicate.elements) == form_count + 1
        @test _et_flatten(duplicate.elements[form_count].result) == "12"
        @test length(toplevel.elements) == form_count
        @test toplevel.elements[form_count].form.value == ""
    end

    @testset "text typed into the bottom hole of the duplicate stays there" begin
        tools = ToolSet()
        toplevel = make_insertion_document(EvaluatorToplevel)
        evaluate_operation(_EvaluatorToplevelMockEditor(toplevel, tools),
                           ToggleEvaluatorOptionOperation(toplevel, :type_structured_forms))
        @test !(toplevel.elements[end].form isa PrimitiveString)   # a hole of the Julia domain

        duplicate = make_document_duplicate(toplevel)
        @test duplicate.elements[end].form !== toplevel.elements[end].form
        duplicate.elements[end].form.value = "1 +"
        @test toplevel.elements[end].form.value == ""
    end

    @testset "a tool call in a transcript is the fork's own, and its result is shared" begin
        call = EvaluatorForm(PrimitiveString("1 + 1");
                             result = make_evaluator_result_text("2"), tool_use_id = "tu_1")
        turn = ConversationTurn(:assistant, [ConversationPart(call)])
        conversation = ConversationConversation([turn])
        fork = make_document_duplicate(conversation)
        forked_call = fork.turns[1].parts[1].content
        @test forked_call isa EvaluatorForm
        @test forked_call !== call
        @test forked_call.result === call.result
        forked_call.result_collapsed = true
        @test call.result_collapsed === false
    end

    @testset "the evaluator tab duplicates into the next tab" begin
        tools = ToolSet()
        toplevel, _ = make_session(tools)
        tab = PaneTab("Evaluator", toplevel)
        group = PaneGroup(PaneTab[tab])
        tree = PaneTree(group)
        operation = make_pane_duplicate_tab_operation(tree, group, 1)
        @test operation !== nothing
        evaluate_operation(_EvaluatorToplevelMockEditor(tree, tools), operation)
        @test length(group.tabs) == 2
        @test get_pane_tab_title_string(group.tabs[2]) == "Evaluator (2)"
        @test group.tabs[2].content isa EvaluatorToplevel
        @test length(group.tabs[2].content.elements) == length(toplevel.elements)
        @test get_pane_focus(tree) == (group, 2)
    end

end
end
