# The duplicate of an assistant is a fork: the conversation so far and the text
# in the composer, a draft of its own that links back to the fork, and the
# backend shared. The fork starts idle, and a turn that streams keeps writing to
# the assistant that started it.
#
# Uses the fixture helpers of `AssistantMvpTest.jl`: `make_assistant_mvp_setup`,
# `_mvp_type!`, `_mvp_enter!`, `_mvp_wait_idle!` and `_mvp_draft_text`.

"""
    test_assistant_duplicate()

Run the tests of the assistant fork. No SDL, no network.
"""
function test_assistant_duplicate()
    @testset "Assistant duplicate" begin

    @testset "the fork has the conversation so far, and a composer of its own" begin
        a = make_assistant_mvp_setup(reply = "Yes")
        _mvp_type!(a, "Hello")
        _mvp_enter!(a)
        @test _mvp_wait_idle!(a) === :idle
        turns = length(a.conversation.turns)
        @test turns == 2
        @test has_document_duplicate(a)

        fork = make_document_duplicate(a)
        @test fork isa Assistant
        @test length(fork.conversation.turns) == turns
        @test fork.conversation !== a.conversation
        @test fork.conversation.turns[1] !== a.conversation.turns[1]
        @test _text_to_string(fork.conversation.turns[end].parts[end].content) == "Yes"
        # The draft links back to its own assistant, in both.
        @test fork.draft !== a.draft
        @test fork.draft.assistant === fork
        @test a.draft.assistant === a
        # The backend is shared, and the fork is idle.
        @test fork.llm === a.llm
        @test fork.status === :idle

        _mvp_type!(fork, "Only here")
        @test _mvp_draft_text(fork) == "Only here"
        @test _mvp_draft_text(a) == ""
    end

    @testset "a turn submitted in the fork goes to the fork" begin
        a = make_assistant_mvp_setup(reply = "Yes")
        fork = make_document_duplicate(a)
        _mvp_type!(fork, "Question")
        @test _mvp_enter!(fork) !== nothing
        @test _mvp_wait_idle!(fork) === :idle
        @test length(fork.conversation.turns) == 2
        @test isempty(a.conversation.turns)
    end

    @testset "a fork made while a turn streams is idle, and the stream stays with the original" begin
        a = make_assistant_mvp_setup(reply = "Late")
        _mvp_type!(a, "Go")
        _mvp_enter!(a)
        # The turn runs on a task that has not started yet: nothing yields here.
        @test a.status === :streaming
        fork = make_document_duplicate(a)
        forked = length(fork.conversation.turns)
        @test fork.status === :idle
        @test _mvp_wait_idle!(a) === :idle
        @test length(a.conversation.turns) == forked + 1
        @test length(fork.conversation.turns) == forked
        @test fork.status === :idle
    end

    @testset "a fork leaves out the reply that streams" begin
        a = make_assistant_mvp_setup(reply = "Unused")
        push!(a.conversation.turns, ConversationTurn(:user, [ConversationPart("Go")]))
        push!(a.conversation.turns, ConversationTurn(:assistant, [ConversationPart("Half")]))
        a.status = :streaming
        fork = make_document_duplicate(a)
        @test length(fork.conversation.turns) == 1
        @test fork.conversation.turns[1].role === :user
        @test length(a.conversation.turns) == 2
        # An idle assistant's last reply is finished, and the fork keeps it.
        a.status = :idle
        @test length(make_document_duplicate(a).conversation.turns) == 2
    end

    end
end
