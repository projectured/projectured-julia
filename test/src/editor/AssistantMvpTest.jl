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
                   TextToGraphics, ConversationToWidget, WorkbenchToWidget,
                   VerticalLayout
using Projectured: ConcreteReferencePath, FieldReference, RangeReference,
                   EmptyReferencePath
using Projectured: LlmBackend, FakeLlm
using Projectured.McpModule: register_default_tools_and_resources!
using Projectured.WorkbenchAssistantModule: _text_to_string, _run_agent_loop!,
                                            _eval_code, _eval_result
using Projectured: ConversationConversation, ConversationTurn, ConversationPart,
                   EvaluatorForm, TextText, TextString, JuliaIdentifier, WidgetCard,
                   MousePress, ToggleCollapseOperation
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
        push!(c, ConversationTurn(:user, [ConversationPart("first")]))
        proj = RecursiveProjection(ConversationToWidget())
        io = projection_print(proj, proj, c, PrinterContext())
        @test io.output isa VerticalLayout
        n0 = length(io.output.children)
        # Load-bearing: pushing a new turn must show up in the
        # layout's children without re-running projection_print.
        push!(c, ConversationTurn(:user, [ConversationPart("second")]))
        @test length(io.output.children) == n0 + 1

        # Same thunk treatment for a turn's parts. A turn projects to a
        # WidgetCard whose `content` is the reactive VerticalLayout of part
        # widgets (the turn is not collapsed, so content is the layout itself).
        reply = ConversationTurn(:assistant; stop_reason = :end_turn)
        push!(c, reply)
        io2 = projection_print(proj, proj, c, PrinterContext())
        reply_card = io2.output.children[end]
        @test reply_card isa WidgetCard
        body = reply_card.content
        b0 = length(body.children)
        push!(reply, ConversationPart("delta"))
        @test length(body.children) == b0 + 1
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
        user_msg  = a.conversation.turns[1]
        reply_msg = a.conversation.turns[2]
        @test user_msg.role === :user
        @test _text_to_string(user_msg.parts[1].content) == "Hello"
        @test reply_msg.role === :assistant
        @test length(reply_msg.parts) == 1
        @test _text_to_string(reply_msg.parts[1].content) == "Yes, sir!"
        @test a.input.value == ""

        # Scene 3: type "What?"
        _mvp_type!(a, "What?")
        @test a.input.value == "What?"

        # Scene 4: Enter again
        _mvp_enter!(a)
        @test _mvp_wait_idle!(a) === :idle
        @test length(a.conversation) == 4
        @test _text_to_string(a.conversation.turns[3].parts[1].content) == "What?"
        @test _text_to_string(a.conversation.turns[4].parts[1].content) == "Yes, sir!"
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
        @test _text_to_string(a.conversation.turns[end].parts[end].content) == "hi there"
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
        _mvp_test_collapse_click()
    end
end

# ── Collapse-on-header-click (widget presentation) ─────────────────────
#
# Projects the conversation through the widget chain and drives a MousePress
# on a turn / part header card. The WidgetCard reader emits a
# ToggleCollapseOperation targeting the card; ConversationToWidget translates
# it back to the domain turn/part; evaluating it flips `collapsed`.
# Uses a font-free measure so the headless run never loads a TTF.

# Scan the left edge for the first header click that yields a ToggleCollapse
# whose target satisfies `pred`.
function _find_toggle(proj, io, pred)
    for y in 2:3:820, x in 16:4:200
        op = try
            projection_read(proj, io, MousePress(:left, x, y))
        catch
            nothing
        end
        if op isa ToggleCollapseOperation && op.target !== nothing && pred(op.target)
            return op
        end
    end
    nothing
end

function _mvp_test_collapse_click()
    @testset "collapse on header click" begin
        fake_measure(_text, _font) = (length(_text) * 10, 20)
        doc  = ProjecturedExample.make_conversation_document_example()
        proj = ProjecturedExample.make_conversation_widget_projection_example(measure = fake_measure)
        io   = projection_print(proj, proj, doc, PrinterContext())

        # Resolve both header clicks from the *same* fresh projection (a toggle
        # mutates `collapsed`, which re-projects and shifts later positions).
        op_turn = _find_toggle(proj, io, t -> t === doc.turns[1])
        op_part = _find_toggle(proj, io, t -> t === doc.turns[2].parts[1])

        # Turn header → toggles the turn's domain node.
        @test op_turn isa ToggleCollapseOperation
        @test doc.turns[1].collapsed == false
        evaluate_operation((document = doc,), op_turn)
        @test doc.turns[1].collapsed == true

        # Part header → toggles the part's domain node.
        @test op_part isa ToggleCollapseOperation
        @test doc.turns[2].parts[1].collapsed == false
        evaluate_operation((document = doc,), op_part)
        @test doc.turns[2].parts[1].collapsed == true
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
        push!(a.conversation, ConversationTurn(:user, [ConversationPart("compute 1+1")]))

        # Drive the agent loop synchronously (no @async) so we can assert
        # the post-state immediately. Stand-in editor mirrors the production
        # `evaluate_operation(editor, op)` plumbing — the tool dispatch in
        # the loop receives this as `editor` (the FakeLlm script's `1+1`
        # doesn't read it, but the wiring is what's under test).
        _run_agent_loop!((document=a,), a)

        msgs = a.conversation.turns
        # Expected sequence in the turn/part model:
        #   1. user turn ("compute 1+1")
        #   2. :assistant eval turn — one part whose content is an EvaluatorForm
        #      (code="1+1", result≈"2"). Turn 1 had only a tool_use (no prose),
        #      so the empty placeholder assistant turn was dropped.
        #   3. :assistant turn with one TextText part ("Done.") from turn 2.
        @test length(msgs) == 3

        @test msgs[1].role === :user
        @test _text_to_string(msgs[1].parts[1].content) == "compute 1+1"

        @test msgs[2].role === :assistant
        ef = msgs[2].parts[1].content
        @test ef isa EvaluatorForm
        @test _eval_code(ef)   == "1+1"
        @test ef.tool_use_id   == "tu_1"
        # The real `execute_julia_code` tool ran — `1+1` repr is "2".
        @test occursin("2", _eval_result(ef))
        @test ef.is_error == false

        @test msgs[3].role === :assistant
        @test length(msgs[3].parts) == 1
        @test msgs[3].parts[1].content isa TextText
        @test _text_to_string(msgs[3].parts[1].content) == "Done."
    end
end
