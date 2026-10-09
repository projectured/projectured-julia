"""
    test_assistant_overview()

What the table of the assistants reads from one assistant: what the person
writes about the conversation.
"""
function test_assistant_overview()
    @testset "the overview of an assistant" begin
        @testset "what the person writes about a conversation" begin
            a = Assistant()
            @test a.description.value == ""
            @test a.comment.value == ""
            @test a.work_state === :pending
            # A new assistant writes none of the three into its file.
            @test !occursin(r"\b(description|comment|work_state) =", print_pred_text(a))
            @test_throws ArgumentError Assistant(; work_state = :done)

            a = Assistant(; description = "Fix the table", comment = "Ask about the colors.",
                          work_state = :in_progress)
            @test a.description isa PrimitiveString
            @test (a.description.value, a.comment.value, a.work_state) ==
                  ("Fix the table", "Ask about the colors.", :in_progress)
            # A native assistant keeps the three in its file too.
            text = print_pred_text(a)
            loaded = parse_pred_text(text)
            @test (loaded.description.value, loaded.comment.value, loaded.work_state) ==
                  ("Fix the table", "Ask about the colors.", :in_progress)
            @test print_pred_text(loaded) == text
            # A fork copies the three, and an edit of the fork stays in the fork.
            fork = copy_document(DuplicatePolicy(), a)
            @test (fork.description.value, fork.comment.value, fork.work_state) ==
                  ("Fix the table", "Ask about the colors.", :in_progress)
            fork.description.value = "Another table"
            @test a.description.value == "Fix the table"
        end
    end
end
