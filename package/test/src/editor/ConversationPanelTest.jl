# Stage 6 — the composer wired into the live WorkbenchAssistant panel.
# Submitting the draft turn (ENTER on a text typein → SubmitDraftTurnOperation)
# pushes it into the conversation, resets the draft in place, and streams a reply.

using Projectured: WorkbenchAssistant, FakeLlm, PrimitiveString, TextText,
                   ComposerInputOperation, SubmitDraftTurnOperation, evaluate_operation,
                   projection_print, projection_read, KeyPress, KeyDown, Modifiers

function _panel_wait_idle!(a; timeout_seconds = 3.0)
    deadline = time() + timeout_seconds
    while a.status === :streaming && time() < deadline
        yield(); sleep(0.005)
    end
    a.status
end

function test_assistant_composer_panel()
    @testset "Assistant composer panel (Stage 6)" begin
        @testset "panel renders + routes keys to the draft" begin
            a = WorkbenchAssistant(; llm = FakeLlm("ok"))
            proj = make_assistant_projection_example()
            iom = projection_print(proj, a)
            @test iom.output isa Projectured.GraphicsCanvas
            @test projection_read(proj, iom, KeyPress('h')) isa ComposerInputOperation
            @test projection_read(proj, iom, KeyDown(:return, Modifiers())) isa SubmitDraftTurnOperation
        end

        @testset "submit pushes the draft, resets it, and streams a reply" begin
            a = WorkbenchAssistant(; llm = FakeLlm("hello there"))
            for ch in "hi assistant"
                evaluate_operation(nothing, ComposerInputOperation(a.draft, string(ch)))
            end
            @test length(a.conversation.turns) == 0

            evaluate_operation(nothing, SubmitDraftTurnOperation(a))
            _panel_wait_idle!(a)

            # User turn submitted, plus a streamed assistant reply.
            @test length(a.conversation.turns) >= 1
            @test a.conversation.turns[1].role == :user
            @test any(t -> t.role == :assistant, a.conversation.turns)

            # Draft reset in place to a single empty text typein.
            @test length(a.draft.parts) == 1
            @test a.draft.parts[1].content isa PrimitiveString
            @test isempty(something(a.draft.parts[1].content.value, ""))
        end

        @testset "empty draft does not submit" begin
            a = WorkbenchAssistant(; llm = FakeLlm("x"))
            evaluate_operation(nothing, SubmitDraftTurnOperation(a))
            @test length(a.conversation.turns) == 0
            @test a.status === :idle
        end

        @testset "ENTER submits through the nested full workbench" begin
            # Regression: in the full workbench the panel reader isn't reached, so
            # the composer must convert ENTER's submit via the draft's assistant.
            ex   = workbench_example
            doc  = ex.make_document()
            proj = ex.make_projection()
            iom  = projection_print(proj, doc)
            a = nothing
            for p in (:navigation_page, :editing_page, :information_page, :control_page)
                for e in getfield(doc, p)[].elements
                    e isa WorkbenchAssistant && (a = e)
                end
            end
            @test a !== nothing
            @test projection_read(proj, iom, KeyPress('h')) isa ComposerInputOperation
            @test projection_read(proj, iom, KeyDown(:return, Modifiers())) isa SubmitDraftTurnOperation
        end
    end
end
