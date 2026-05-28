# ═══════════════════════════════════════════════════════════════════════════
# test/src/editor/AssistantMvpTest.jl
#
# End-to-end test for the WorkbenchAssistant MVP. Drives the printer /
# reader / evaluate_operation pipeline by hand — no SDL, no graphics
# layout — and asserts the four scenes from
# `plan/workbench-assistant-mvp.md`:
#
#   1. type "Hello"  → input.value updates, no submit yet
#   2. press Enter   → user message + canned "Yes, sir!" reply appear,
#                      input clears
#   3. type "What?"  → input updates again
#   4. press Enter   → second user/reply pair appears
#
# Typing goes through the standard `PrimitiveString → Syntax → Text →
# Graphics` chain (PrimitiveStringToSyntaxLeaf catches `KeyPress`).
# Enter goes through `WorkbenchToWidget` so the
# `WorkbenchAssistantToWidgetScrollPane.projection_read` handler fires.
# The test deliberately does not wire the full assistant → graphics
# chain — that path is exercised by the standalone assistant example
# (see [`make_assistant_only_example`](../example/src/Examples.jl)).
#
# Plus the load-bearing reactivity check: pushing a message to
# `conversation.messages` after `projection_print` updates the widget
# composite's `elements` *without* re-running `projection_print`.
# ═══════════════════════════════════════════════════════════════════════════

using Projectured: KeyPress, KeyDown, Modifiers
using Projectured: PrimitiveDocument, PrimitiveToSyntax, SyntaxToText,
                   TextToGraphics, ConversationToWidget, WorkbenchToWidget
using Projectured: ConcreteReferencePath, FieldReference, RangeReference,
                   EmptyReferencePath
using Projectured.WorkbenchAssistantModule: _text_to_string

# ── Test fixture ────────────────────────────────────────────────────────

_mvp_measure(text, font) = (length(text) * 10, 20)

# Chain that exercises the PrimitiveString input. KeyPress events bubble
# up the reader chain; PrimitiveStringToSyntaxLeaf catches them and emits
# StringReplaceRangeOperation. The test then evaluates the operation
# against the assistant's input directly.
function _input_chain()
    SequentialProjection(
        RecursiveProjection(PrimitiveToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure = _mvp_measure),
    )
end

# Chain that exercises the Enter keybinding. WorkbenchToWidget dispatches
# WorkbenchAssistant to WorkbenchAssistantToWidgetScrollPane, whose
# projection_read for KeyDown :return returns SubmitProseOperation.
function _workbench_chain()
    RecursiveProjection(WorkbenchToWidget())
end

function make_assistant_mvp_setup()
    a = WorkbenchAssistant()
    # Pre-seed selection so PrimitiveStringToSyntaxLeaf has a cursor to
    # work with on the first KeyPress.
    a.input.selection = ConcreteReferencePath(
        FieldReference("value"),
        ConcreteReferencePath(RangeReference(0, 0), EmptyReferencePath()))
    a
end

# Type a string into the assistant input by feeding KeyPress events
# through the PrimitiveString chain.
function _mvp_type!(a::WorkbenchAssistant, s::AbstractString)
    chain = _input_chain()
    for c in s
        iomap = projection_print(chain, a.input)
        op = projection_read(chain, iomap, KeyPress(c))
        op === nothing && continue
        evaluate_operation(op, a.input)
    end
end

# Press Enter on the assistant panel and apply the resulting operation.
function _mvp_enter!(a::WorkbenchAssistant)
    chain = _workbench_chain()
    iomap = projection_print(chain, a)
    op = projection_read(chain, iomap, KeyDown(:return, Modifiers()))
    op === nothing && return nothing
    evaluate_operation(op, a)
    op
end

# ── Reactivity probe ───────────────────────────────────────────────────

function _mvp_test_reactive_thunk()
    @testset "ConversationToWidget reactive thunk" begin
        c = ConversationConversation()
        push!(c, ConversationUserMessage("first"))
        proj = RecursiveProjection(ConversationToWidget())
        io = projection_print(proj, c, proj, EmptyReferencePath())
        @test io.output isa WidgetComposite
        n0 = length(io.output.elements)
        # Load-bearing: pushing a new message must show up in the
        # composite's elements without re-running projection_print.
        push!(c, ConversationUserMessage("second"))
        @test length(io.output.elements) == n0 + 1

        # Same thunk treatment for assistant message blocks.
        reply = ConversationAssistantMessage(stop_reason = :end_turn)
        push!(c, reply)
        io2 = projection_print(proj, c, proj, EmptyReferencePath())
        reply_widget = io2.output.elements[end]
        b0 = length(reply_widget.elements)
        push!(reply, ConversationTextBlock("delta"))
        @test length(reply_widget.elements) == b0 + 1
    end
end

# ── Scene walker ───────────────────────────────────────────────────────

function _mvp_test_scenes()
    @testset "Assistant MVP scenes" begin
        a = make_assistant_mvp_setup()

        # Scene 1: type "Hello"
        _mvp_type!(a, "Hello")
        @test a.input.value == "Hello"
        @test length(a.conversation) == 0

        # Scene 2: Enter
        op = _mvp_enter!(a)
        @test op isa SubmitProseOperation
        @test length(a.conversation) == 2
        user_msg  = a.conversation.messages[1]
        reply_msg = a.conversation.messages[2]
        @test user_msg isa ConversationUserMessage
        @test _text_to_string(user_msg.text) == "Hello"
        @test reply_msg isa ConversationAssistantMessage
        @test length(reply_msg.blocks) == 1
        @test _text_to_string(reply_msg.blocks[1].text) == "Yes, sir!"
        @test a.input.value == ""
        @test a.status === :idle

        # Scene 3: type "What?"
        _mvp_type!(a, "What?")
        @test a.input.value == "What?"

        # Scene 4: Enter again
        _mvp_enter!(a)
        @test length(a.conversation) == 4
        @test _text_to_string(a.conversation.messages[3].text) == "What?"
        @test _text_to_string(a.conversation.messages[4].blocks[1].text) == "Yes, sir!"
        @test a.input.value == ""
    end
end

"""
    test_assistant_mvp()

Run the WorkbenchAssistant MVP test suite: the four scripted scenes
plus the reactive-thunk probe. No SDL, no network.
"""
function test_assistant_mvp()
    @testset "Assistant MVP" begin
        _mvp_test_reactive_thunk()
        _mvp_test_scenes()
    end
end
