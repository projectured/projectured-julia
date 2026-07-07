# Tests for the Stage 3b user-message composer (ConversationEditorModule):
# the gesture→operation reader and the part-growing operations that turn a draft
# `ConversationTurn` into a finished sequence of parts.


# Flatten a TextText to its rendered string.
function _ce_flatten(t::TextText)
    io = IOBuffer()
    for span in t.elements
        hasproperty(span, :content) && print(io, span.content)
    end
    String(take!(io))
end

# Apply an operation to the draft (no real editor needed for the logic).
_ce_apply!(op) = evaluate_operation(nothing, op)
_ce_type!(draft, s) = for ch in s
    _ce_apply!(ComposerInputOperation(draft, string(ch)))
end

# A fresh single-typein draft.
_ce_draft() = ConversationDraft([ConversationPart(PrimitiveString(""))])

function test_conversation_editor()
    @testset "Conversation composer (Stage 3b)" begin

        @testset "worked case: prose · evaluated 2+2 · prose" begin
            turn = _ce_draft()

            _ce_type!(turn, "hey assistant, look what I've got")
            _ce_apply!(ComposerInsertPartOperation(turn))   # INSERT → kind chooser
            @test turn.parts[length(turn.parts)].content isa DocumentInsertion

            _ce_type!(turn, "julia")
            _ce_apply!(ComposerCommitChooserOperation(turn)) # ENTER → JuliaInsertion
            @test turn.parts[length(turn.parts)].content isa JuliaInsertion

            _ce_type!(turn, "2+2")
            _ce_apply!(ComposerEvaluateOperation(turn))      # ALT+ENTER → EvaluatorForm
            @test turn.parts[length(turn.parts)].content isa PrimitiveString  # fresh typein

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
            turn = _ce_draft()
            _ce_type!(turn, "hi")
            _ce_apply!(ComposerInsertPartOperation(turn))    # → DocumentInsertion
            _ce_type!(turn, "jul")
            _ce_apply!(ComposerRevertOperation(turn))        # ESC
            @test turn.parts[length(turn.parts)].content isa PrimitiveString
            @test length(turn.parts) == 2                    # committed "hi" + fresh typein
        end

        @testset "unknown chooser keyword is a no-op" begin
            turn = _ce_draft()
            _ce_apply!(ComposerInsertPartOperation(turn))    # drop blank → chooser
            _ce_type!(turn, "zzz")
            _ce_apply!(ComposerCommitChooserOperation(turn)) # not a known kind
            @test turn.parts[length(turn.parts)].content isa DocumentInsertion
        end

        @testset "INSERT drops a blank typein" begin
            turn = _ce_draft()
            _ce_apply!(ComposerInsertPartOperation(turn))
            @test length(turn.parts) == 1
            @test turn.parts[1].content isa DocumentInsertion
        end

        @testset "reader: gesture → operation per active state" begin
            proj = ConversationComposerToWidget()
            turn = _ce_draft()
            iom = print_document(proj, turn)

            # text typein
            @test read_intent(proj, iom, KeyPress('a')) isa ComposerInputOperation
            @test read_intent(proj, iom, KeyDown(:return, Modifiers())) isa ComposerSubmitOperation
            @test read_intent(proj, iom, KeyDown(:return, Modifiers(shift=true))) isa ComposerNewlineOperation
            @test read_intent(proj, iom, KeyDown(:insert, Modifiers())) isa ComposerInsertPartOperation
            @test read_intent(proj, iom, KeyDown(:tab, Modifiers())) isa ComposerInsertPartOperation
            @test read_intent(proj, iom, KeyDown(:backspace, Modifiers())) isa ComposerBackspaceOperation

            # kind chooser
            _ce_apply!(ComposerInsertPartOperation(turn))
            @test read_intent(proj, iom, KeyDown(:return, Modifiers())) isa ComposerCommitChooserOperation
            @test read_intent(proj, iom, KeyDown(:escape, Modifiers())) isa ComposerRevertOperation

            # julia source
            _ce_type!(turn, "julia")
            _ce_apply!(ComposerCommitChooserOperation(turn))
            @test turn.parts[length(turn.parts)].content isa JuliaInsertion
            @test read_intent(proj, iom, KeyDown(:return, Modifiers())) isa ComposerCommitSourceOperation
            @test read_intent(proj, iom, KeyDown(:return, Modifiers(alt=true))) isa ComposerEvaluateOperation
            @test read_intent(proj, iom, KeyDown(:return, Modifiers(shift=true))) isa ComposerNewlineOperation
        end

        @testset "show: get_projection_gesture_bindings mirrors what the reader fires (fire == show)" begin
            proj = ConversationComposerToWidget()
            turn = _ce_draft()
            iom = print_document(proj, turn)
            descs() = Set(b.description for b in get_projection_gesture_bindings(proj, iom))

            # text typein mode — Submit / New line / Add a structured part / Insert
            @test "Submit" in descs()
            @test "New line" in descs()
            @test "Add a structured part" in descs()
            @test "Insert character" in descs()
            @test !("Choose insertion kind" in descs())   # chooser-only, not here

            # kind chooser mode — Submit is gone, Choose appears
            _ce_apply!(ComposerInsertPartOperation(turn))
            @test "Choose insertion kind" in descs()
            @test !("Submit" in descs())

            # julia source mode — Evaluate + Commit source
            _ce_type!(turn, "julia")
            _ce_apply!(ComposerCommitChooserOperation(turn))
            @test "Evaluate" in descs()
            @test "Commit source" in descs()
        end
    end
end
