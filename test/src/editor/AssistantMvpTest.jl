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
# `WorkbenchAssistantToWidgetSplitPane.projection_read` handler fires.
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
using Projectured: LlmBackend, FakeLlm
using Projectured.McpModule: register_default_tools_and_resources!
using Projectured.WorkbenchAssistantModule: _text_to_string, _run_agent_loop!
import Projectured.LlmModule: stream_turn

# A multi-turn scripted backend: each call to `stream_turn` consumes the
# next vector of SSE events from `scripts`. Useful for testing tool-use
# round-trips where turn N requests a tool and turn N+1 (after the agent
# loop dispatches the tool and appends a result) emits the final reply.
mutable struct ScriptedLlm <: LlmBackend
    scripts::Vector{Vector{NamedTuple}}
    cursor::Int
end
ScriptedLlm(scripts) = ScriptedLlm([Vector{NamedTuple}(s) for s in scripts], 0)

function stream_turn(b::ScriptedLlm,
                     _api_key::AbstractString,
                     _model::AbstractString,
                     _system::AbstractString,
                     _messages::AbstractVector,
                     _tools::AbstractVector;
                     on_event::Function)
    b.cursor += 1
    b.cursor > length(b.scripts) &&
        error("ScriptedLlm: exhausted at turn $(b.cursor) (have $(length(b.scripts)))")
    for ev in b.scripts[b.cursor]
        on_event(ev)
    end
    nothing
end

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
# WorkbenchAssistant to WorkbenchAssistantToWidgetSplitPane, whose
# projection_read for KeyDown :return returns SubmitProseOperation.
function _workbench_chain()
    RecursiveProjection(WorkbenchToWidget())
end

function make_assistant_mvp_setup(; reply::AbstractString = "Yes, sir!")
    # Use FakeLlm so the agent loop runs without network and produces a
    # deterministic reply.
    a = WorkbenchAssistant(; llm = FakeLlm(reply))
    # Pre-seed selection so PrimitiveStringToSyntaxLeaf has a cursor to
    # work with on the first KeyPress.
    a.input.selection = ConcreteReferencePath(
        FieldReference("value"),
        ConcreteReferencePath(RangeReference(0, 0), EmptyReferencePath()))
    a
end

# After SubmitProseOperation launches `_run_agent_loop!` on an @async task,
# spin until status returns to `:idle` (or until the deadline). Tests must
# observe the post-stream state.
function _mvp_wait_idle!(a::WorkbenchAssistant; timeout_seconds::Real = 2.0)
    deadline = time() + timeout_seconds
    while a.status === :streaming && time() < deadline
        yield()
        sleep(0.005)
    end
    a.status
end

# Type a string into the assistant input by feeding KeyPress events
# through the PrimitiveString chain.
function _mvp_type!(a::WorkbenchAssistant, s::AbstractString)
    chain = _input_chain()
    for c in s
        iomap = projection_print(chain, a.input)
        op = projection_read(chain, iomap, KeyPress(c))
        op === nothing && continue
        evaluate_operation((document=a.input,), op)
    end
end

# Press Enter on the assistant panel and apply the resulting operation.
function _mvp_enter!(a::WorkbenchAssistant)
    chain = _workbench_chain()
    iomap = projection_print(chain, a)
    op = projection_read(chain, iomap, KeyDown(:return, Modifiers()))
    op === nothing && return nothing
    evaluate_operation((document=a,), op)
    op
end

# ── Reactivity probe ───────────────────────────────────────────────────

function _mvp_test_reactive_thunk()
    @testset "ConversationToWidget reactive thunk" begin
        c = ConversationConversation()
        push!(c, ConversationUserMessage("first"))
        proj = RecursiveProjection(ConversationToWidget())
        io = projection_print(proj, proj, c, PrinterContext())
        @test io.output isa WidgetComposite
        n0 = length(io.output.elements)
        # Load-bearing: pushing a new message must show up in the
        # composite's elements without re-running projection_print.
        push!(c, ConversationUserMessage("second"))
        @test length(io.output.elements) == n0 + 1

        # Same thunk treatment for assistant message blocks.
        reply = ConversationAssistantMessage(stop_reason = :end_turn)
        push!(c, reply)
        io2 = projection_print(proj, proj, c, PrinterContext())
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

        # Scene 2: Enter — kicks off async _run_agent_loop! via FakeLlm
        op = _mvp_enter!(a)
        @test op isa SubmitProseOperation
        @test _mvp_wait_idle!(a) === :idle
        @test length(a.conversation) == 2
        user_msg  = a.conversation.messages[1]
        reply_msg = a.conversation.messages[2]
        @test user_msg isa ConversationUserMessage
        @test _text_to_string(user_msg.text) == "Hello"
        @test reply_msg isa ConversationAssistantMessage
        @test length(reply_msg.blocks) == 1
        @test _text_to_string(reply_msg.blocks[1].text) == "Yes, sir!"
        @test a.input.value == ""

        # Scene 3: type "What?"
        _mvp_type!(a, "What?")
        @test a.input.value == "What?"

        # Scene 4: Enter again
        _mvp_enter!(a)
        @test _mvp_wait_idle!(a) === :idle
        @test length(a.conversation) == 4
        @test _text_to_string(a.conversation.messages[3].text) == "What?"
        @test _text_to_string(a.conversation.messages[4].blocks[1].text) == "Yes, sir!"
        @test a.input.value == ""
    end
end

# Verify the FakeLlm backend can be swapped to produce a different canned
# reply — proves the LlmBackend dispatch actually routes through.
function _mvp_test_fake_llm_dispatch()
    @testset "FakeLlm dispatch" begin
        a = make_assistant_mvp_setup(; reply = "hi there")
        _mvp_type!(a, "ping")
        _mvp_enter!(a)
        @test _mvp_wait_idle!(a) === :idle
        @test length(a.conversation) == 2
        @test _text_to_string(a.conversation.messages[end].blocks[end].text) == "hi there"
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
        _mvp_test_fake_llm_dispatch()
        _mvp_test_tool_use_roundtrip()
    end
end

# ── Tool-use round-trip ────────────────────────────────────────────────
#
# Exercises the full agent loop:
#   turn 1: LLM requests `execute_julia_code({"code":"1+1"})`
#       → agent loop dispatches via ToolRegistry → tool returns "2\n"
#       → ConversationCodeExecution(:assistant, …) appended (which
#         carries both the call and the result, plus the tool_use_id
#         needed to round-trip back through Anthropic on the next turn)
#   turn 2: LLM emits a final text reply
#       → ConversationAssistantMessage with a text block appended

function _tool_use_script(tool_id::AbstractString, tool_name::AbstractString,
                          input_json::AbstractString)
    NamedTuple[
        (type = :message_start, data = Dict{Symbol,Any}()),
        (type = :content_block_start,
         data = Dict{Symbol,Any}(:content_block =>
                                  Dict{Symbol,Any}(:type => "tool_use",
                                                    :id   => String(tool_id),
                                                    :name => String(tool_name)))),
        (type = :content_block_delta,
         data = Dict{Symbol,Any}(:delta =>
                                  Dict{Symbol,Any}(:type         => "input_json_delta",
                                                    :partial_json => String(input_json)))),
        (type = :content_block_stop, data = Dict{Symbol,Any}()),
        (type = :message_delta,
         data = Dict{Symbol,Any}(:delta =>
                                  Dict{Symbol,Any}(:stop_reason => "tool_use"))),
        (type = :message_stop, data = Dict{Symbol,Any}()),
    ]
end

function _final_text_script(text::AbstractString)
    NamedTuple[
        (type = :message_start, data = Dict{Symbol,Any}()),
        (type = :content_block_start,
         data = Dict{Symbol,Any}(:content_block =>
                                  Dict{Symbol,Any}(:type => "text"))),
        (type = :content_block_delta,
         data = Dict{Symbol,Any}(:delta =>
                                  Dict{Symbol,Any}(:type => "text_delta",
                                                    :text => String(text)))),
        (type = :content_block_stop, data = Dict{Symbol,Any}()),
        (type = :message_delta,
         data = Dict{Symbol,Any}(:delta =>
                                  Dict{Symbol,Any}(:stop_reason => "end_turn"))),
        (type = :message_stop, data = Dict{Symbol,Any}()),
    ]
end

function _mvp_test_tool_use_roundtrip()
    @testset "Tool-use round-trip via ScriptedLlm" begin
        # Make sure execute_julia_code is registered.
        register_default_tools_and_resources!()

        llm = ScriptedLlm([
            _tool_use_script("tu_1", "execute_julia_code",
                             """{"code":"1+1"}"""),
            _final_text_script("Done."),
        ])
        a = WorkbenchAssistant(; llm = llm)
        push!(a.conversation, ConversationUserMessage("compute 1+1"))

        # Drive the agent loop synchronously (no @async) so we can assert
        # the post-state immediately. Stand-in editor mirrors the production
        # `evaluate_operation(editor, op)` plumbing — the tool dispatch in
        # the loop receives this as `editor` (the FakeLlm script's `1+1`
        # doesn't read it, but the wiring is what's under test).
        _run_agent_loop!((document=a,), a)

        msgs = a.conversation.messages
        # Expected sequence after the unified ConversationCodeExecution refactor:
        #   1. user message ("compute 1+1")
        #   2. ConversationCodeExecution(:assistant, code="1+1", result≈"2")
        #      — the assistant turn 1 had only a tool_use (no prose), so the
        #        empty placeholder ConversationAssistantMessage was dropped.
        #   3. assistant message with one ConversationTextBlock("Done.") from turn 2.
        @test length(msgs) == 3

        @test msgs[1] isa ConversationUserMessage
        @test _text_to_string(msgs[1].text) == "compute 1+1"

        @test msgs[2] isa ConversationCodeExecution
        @test msgs[2].initiator   === :assistant
        @test msgs[2].code        == "1+1"
        @test msgs[2].tool_use_id == "tu_1"
        # The real `execute_julia_code` tool ran — `1+1` repr is "2".
        @test occursin("2", msgs[2].result)
        @test msgs[2].is_error == false

        @test msgs[3] isa ConversationAssistantMessage
        @test length(msgs[3].blocks) == 1
        @test msgs[3].blocks[1] isa ConversationTextBlock
        @test _text_to_string(msgs[3].blocks[1].text) == "Done."
    end
end
