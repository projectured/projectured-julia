# Tests for the Stage 3b user-message composer (ConversationEditorModule):
# the gesture→operation reader and the part-growing operations that turn a draft
# `ConversationTurn` into a finished sequence of parts.

using Projectured: ConversationTurn, ConversationPart, PrimitiveString, TextText,
                   DocumentInsertion, JuliaInsertion, JuliaDocument, EvaluatorForm,
                   ConversationComposerToWidget,
                   ComposerInputOperation, ComposerBackspaceOperation,
                   ComposerNewlineOperation, ComposerInsertPartOperation,
                   ComposerCommitChooserOperation, ComposerCommitSourceOperation,
                   ComposerEvaluateOperation, ComposerRevertOperation,
                   ComposerSubmitOperation,
                   projection_print, projection_read, evaluate_operation,
                   KeyPress, KeyDown
using Projectured: Modifiers

# Flatten a TextText to its rendered string.
function _ce_flatten(t::TextText)
    io = IOBuffer()
    for span in t.elements
        hasproperty(span, :content) && print(io, span.content)
    end
    String(take!(io))
end

# Apply an operation to the draft turn (no real editor needed for the logic).
_ce_apply!(op) = evaluate_operation(nothing, op)
_ce_type!(turn, s) = for ch in s
    _ce_apply!(ComposerInputOperation(turn, string(ch)))
end

function test_conversation_editor()
    @testset "Conversation composer (Stage 3b)" begin

        @testset "worked case: prose · evaluated 2+2 · prose" begin
            turn = ConversationTurn(:user, [ConversationPart(PrimitiveString(""))])

            _ce_type!(turn, "hey assistant, look what I've got")
            _ce_apply!(ComposerInsertPartOperation(turn))   # INSERT → kind chooser
            @test turn.parts[length(turn)].content isa DocumentInsertion

            _ce_type!(turn, "julia")
            _ce_apply!(ComposerCommitChooserOperation(turn)) # ENTER → JuliaInsertion
            @test turn.parts[length(turn)].content isa JuliaInsertion

            _ce_type!(turn, "2+2")
            _ce_apply!(ComposerEvaluateOperation(turn))      # ALT+ENTER → EvaluatorForm
            @test turn.parts[length(turn)].content isa PrimitiveString  # fresh typein

            _ce_type!(turn, "see, it's not that complicated")
            _ce_apply!(ComposerSubmitOperation(turn))        # ENTER → finalize

            @test length(turn.parts) == 3
            p1, p2, p3 = turn.parts[1].content, turn.parts[2].content, turn.parts[3].content
            @test p1 isa TextText
            @test _ce_flatten(p1) == "hey assistant, look what I've got"
            @test p2 isa EvaluatorForm
            @test p2.form isa JuliaDocument
            @test !p2.is_error
            @test occursin("4", _ce_flatten(p2.result))
            @test p3 isa TextText
            @test _ce_flatten(p3) == "see, it's not that complicated"
        end

        @testset "ESC reverts a structured insertion to a text typein" begin
            turn = ConversationTurn(:user, [ConversationPart(PrimitiveString(""))])
            _ce_type!(turn, "hi")
            _ce_apply!(ComposerInsertPartOperation(turn))    # → DocumentInsertion
            _ce_type!(turn, "jul")
            _ce_apply!(ComposerRevertOperation(turn))        # ESC
            @test turn.parts[length(turn)].content isa PrimitiveString
            @test length(turn.parts) == 2                    # committed "hi" + fresh typein
        end

        @testset "unknown chooser keyword is a no-op" begin
            turn = ConversationTurn(:user, [ConversationPart(PrimitiveString(""))])
            _ce_apply!(ComposerInsertPartOperation(turn))    # drop blank → chooser
            _ce_type!(turn, "zzz")
            _ce_apply!(ComposerCommitChooserOperation(turn)) # not a known kind
            @test turn.parts[length(turn)].content isa DocumentInsertion
        end

        @testset "INSERT drops a blank typein" begin
            turn = ConversationTurn(:user, [ConversationPart(PrimitiveString(""))])
            _ce_apply!(ComposerInsertPartOperation(turn))
            @test length(turn.parts) == 1
            @test turn.parts[1].content isa DocumentInsertion
        end

        @testset "reader: gesture → operation per active state" begin
            proj = ConversationComposerToWidget()
            turn = ConversationTurn(:user, [ConversationPart(PrimitiveString(""))])
            iom = projection_print(proj, turn)

            # text typein
            @test projection_read(proj, iom, KeyPress('a')) isa ComposerInputOperation
            @test projection_read(proj, iom, KeyDown(:return, Modifiers())) isa ComposerSubmitOperation
            @test projection_read(proj, iom, KeyDown(:return, Modifiers(shift=true))) isa ComposerNewlineOperation
            @test projection_read(proj, iom, KeyDown(:insert, Modifiers())) isa ComposerInsertPartOperation
            @test projection_read(proj, iom, KeyDown(:backspace, Modifiers())) isa ComposerBackspaceOperation

            # kind chooser
            _ce_apply!(ComposerInsertPartOperation(turn))
            @test projection_read(proj, iom, KeyDown(:return, Modifiers())) isa ComposerCommitChooserOperation
            @test projection_read(proj, iom, KeyDown(:escape, Modifiers())) isa ComposerRevertOperation

            # julia source
            _ce_type!(turn, "julia")
            _ce_apply!(ComposerCommitChooserOperation(turn))
            @test turn.parts[length(turn)].content isa JuliaInsertion
            @test projection_read(proj, iom, KeyDown(:return, Modifiers())) isa ComposerCommitSourceOperation
            @test projection_read(proj, iom, KeyDown(:return, Modifiers(alt=true))) isa ComposerEvaluateOperation
            @test projection_read(proj, iom, KeyDown(:return, Modifiers(shift=true))) isa ComposerNewlineOperation
        end
    end
end
