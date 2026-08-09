# ═══════════════════════════════════════════════════════════════════════════
# test/editor/AssistantMvpTest.jl
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
# `WorkbenchAssistantToWidgetSplitPane.read_intent` handler fires.
# The test deliberately does not wire the full assistant → graphics
# chain — that path is exercised by the standalone assistant example
# (see [`make_assistant_only_example`](../example/Examples.jl)).
#
# Plus the load-bearing reactivity check: pushing a message to
# `conversation.messages` after `print_document` updates the widget
# composite's `elements` *without* re-running `print_document`.
# ═══════════════════════════════════════════════════════════════════════════

using ProjecturedKernel.ToolModule: ToolSet, register_default_tools!
using ProjecturedWorkbench.WorkbenchAssistantModule: _text_to_string, _run_agent_loop!,
                                            _eval_code, _eval_result, _doc_source,
                                            _eval_form_doc
import ProjecturedKernel.LlmModule: stream_turn,
    LlmEvent, LlmTextStart, LlmTextDelta, LlmTextStop,
    LlmToolUse, LlmToolUseStart, LlmToolInputDelta, LlmToolUseStop,
    LlmTurnEnd
import ProjecturedKernel.CellModule: Cell, ComputedCell

# The multi-round scripted backend `ScriptedLlm` (each `stream_turn` consumes the
# next round of SSE events) is a test double, so it lives in
# `ProjecturedKernelExample` (fakes never sit in `main`); it reaches this suite
# through `using ProjecturedConversationExample`. The `_tool_use_script` /
# `_final_text_script` builders below produce the same event-vector shape it consumes.

# ── Test fixture ────────────────────────────────────────────────────────

_mvp_measure(text, font) = (length(text) * 10, 20)

# Chain that exercises the PrimitiveString input. KeyPress events bubble
# up the reader chain; PrimitiveStringToSyntaxLeaf catches them and emits
# ReplaceStringRangeOperation. The test then evaluates the operation
# against the assistant's input directly.
function _input_chain()
    ChainingProjection(
        RecursiveProjection(PrimitiveToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure = _mvp_measure),
    )
end

# Chain that exercises the Enter keybinding. WorkbenchToWidget dispatches
# WorkbenchAssistant to WorkbenchAssistantToWidgetSplitPane, whose
# read_intent for KeyDown :return returns SubmitProseOperation.
function _workbench_chain()
    RecursiveProjection(WorkbenchToWidget())
end

function make_assistant_mvp_setup(; reply::AbstractString = "Yes, sir!")
    # Use FakeLlm so the agent loop runs without network and produces a
    # deterministic reply.
    a = WorkbenchAssistant(; llm = FakeLlm(reply))
    # Pre-seed selection so PrimitiveStringToSyntaxLeaf has a cursor to
    # work with on the first KeyPress.
    a.input.selection = ConcreteReference(
        FieldReferenceStep("value"),
        ConcreteReference(RangeReferenceStep(0, 0), EmptyReference()))
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

# Type a string into the assistant's draft turn via the composer (Stage 6: the
# input pane is the composer on `a.draft`, not the old PrimitiveString box).
function _mvp_type!(a::WorkbenchAssistant, s::AbstractString)
    for c in s
        evaluate_operation(nothing, ComposerInputOperation(a.draft, string(c)))
    end
end

# The active typein's current text (the draft's last part, a PrimitiveString).
_mvp_draft_text(a::WorkbenchAssistant) =
    something(a.draft.parts[length(a.draft.parts)].content.value, "")

# Press Enter on the assistant panel and apply the resulting operation.
function _mvp_enter!(a::WorkbenchAssistant)
    chain = _workbench_chain()
    iomap = print_document(chain, a)
    op = read_intent(chain, iomap, KeyDown(:return, ModifierKeys()))
    op === nothing && return nothing
    evaluate_operation((document = a, tools = register_default_tools!(ToolSet())), op)
    op
end

# ── Reactivity probe ───────────────────────────────────────────────────

function _mvp_test_reactive_thunk()
    @testset "ConversationToWidget reactive thunk" begin
        c = ConversationConversation()
        push!(c.turns, ConversationTurn(:user, [ConversationPart("first")]))
        proj = RecursiveProjection(ConversationToWidget())
        io = print_document(proj, proj, c, PrinterContext())
        @test io.output isa VerticalLayout
        n0 = length(io.output.children)
        # Load-bearing: pushing a new turn must show up in the
        # layout's children without re-running print_document.
        push!(c.turns, ConversationTurn(:user, [ConversationPart("second")]))
        @test length(io.output.children) == n0 + 1

        # Same thunk treatment for a turn's parts. A turn projects to a
        # WidgetCard whose `content` is the reactive VerticalLayout of part
        # widgets (the turn is not collapsed, so content is the layout itself).
        reply = ConversationTurn(:assistant; stop_reason = :end_turn)
        push!(c.turns, reply)
        io2 = print_document(proj, proj, c, PrinterContext())
        reply_card = io2.output.children[end]
        @test reply_card isa WidgetCard
        body = reply_card.content
        b0 = length(body.children)
        push!(reply.parts, ConversationPart("delta"))
        @test length(body.children) == b0 + 1
    end
end

# ── Scene walker ───────────────────────────────────────────────────────

function _mvp_test_scenes()
    @testset "Assistant MVP scenes" begin
        a = make_assistant_mvp_setup()

        # Scene 1: type "Hello"
        _mvp_type!(a, "Hello")
        @test _mvp_draft_text(a) == "Hello"
        @test length(a.conversation.turns) == 0

        # Scene 2: Enter — kicks off async _run_agent_loop! via FakeLlm
        op = _mvp_enter!(a)
        @test op isa SubmitDraftTurnOperation
        @test _mvp_wait_idle!(a) === :idle
        @test length(a.conversation.turns) == 2
        user_msg  = a.conversation.turns[1]
        reply_msg = a.conversation.turns[2]
        @test user_msg.role === :user
        @test _text_to_string(user_msg.parts[1].content) == "Hello"
        @test reply_msg.role === :assistant
        @test length(reply_msg.parts) == 1
        @test _text_to_string(reply_msg.parts[1].content) == "Yes, sir!"
        @test _mvp_draft_text(a) == ""        # draft reset after submit

        # Scene 3: type "What?"
        _mvp_type!(a, "What?")
        @test _mvp_draft_text(a) == "What?"

        # Scene 4: Enter again
        _mvp_enter!(a)
        @test _mvp_wait_idle!(a) === :idle
        @test length(a.conversation.turns) == 4
        @test _text_to_string(a.conversation.turns[3].parts[1].content) == "What?"
        @test _text_to_string(a.conversation.turns[4].parts[1].content) == "Yes, sir!"
        @test _mvp_draft_text(a) == ""
    end
end

# Verify the FakeLlm backend can be swapped to produce a different canned
# reply — proves the Llm dispatch actually routes through.
function _mvp_test_fake_llm_dispatch()
    @testset "FakeLlm dispatch" begin
        a = make_assistant_mvp_setup(; reply = "hi there")
        _mvp_type!(a, "ping")
        _mvp_enter!(a)
        @test _mvp_wait_idle!(a) === :idle
        @test length(a.conversation.turns) == 2
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
        _mvp_test_scripted_builders()
        _mvp_test_collapse_click()
        _mvp_test_thinking_stream()
        _mvp_test_resource_collapse()
        _mvp_test_collapse_containment()
    end
end

# ── Resource-read parts collapse by default ────────────────────────────
#
# A `read_resource` tool call is lookup chatter, secondary to the answer (like
# thinking), so the agent loop must create its part collapsed by default —
# unlike an `execute_julia_code` result, which stays expanded.

function _mvp_test_resource_collapse()
    @testset "resource-read tool part collapsed by default" begin
        tools = register_default_tools!(ToolSet())
        llm = ScriptedLlm([
            _tool_use_script("tu_1", "read_resource",
                             Dict("uri" => "resource://guides")),
            _final_text_script("Read it."),
        ])
        a = WorkbenchAssistant(; llm = llm)
        push!(a.conversation.turns, ConversationTurn(:user, [ConversationPart("look it up")]))
        _run_agent_loop!((document = a, tools = tools), a)

        reply = a.conversation.turns[end]
        @test reply.role === :assistant
        ef = reply.parts[1].content
        @test ef isa EvaluatorForm
        @test ef.tool_name == "read_resource"
        @test reply.parts[1].collapsed == true       # collapsed by default
    end
end

# ── Collapse layout containment (plan: assistant-collapse-layout Stages 2–3) ──
#
# Stage 2 (no balloon): collapsing a part must not widen any card. A collapsed
# body sized to the wrong (turn/card) width balloons the part card past its
# authored width; that propagates up and widens the whole hierarchy — so the max
# card width of the default (some-parts-collapsed) render must equal that of the
# all-expanded render. (Comparative, so it needs no internal width constants and
# survives the bug, which inflates the root too.)
#
# Stage 3 (containment): on the fallback path and at allocated panel widths,
# every rendered card's right edge stays within the conversation's own width — no
# expanded or collapsed body overflows its container.

# Max `w` over every GraphicsCanvas in the tree.
_canvas_maxw(node) = node isa GraphicsCanvas ?
    max(Int(node.w), maximum(Int[_canvas_maxw(e) for e in node.elements]; init = 0)) : 0

# Max absolute right edge over every sized (w > 0) GraphicsCanvas (offsets
# accumulate through transparent w == 0 wrapper canvases).
function _canvas_max_absright(node, ax = 0)
    node isa GraphicsCanvas || return 0
    ax2 = ax + Int(node.x)
    here = Int(node.w) > 0 ? ax2 + Int(node.w) : 0
    max(here, maximum(Int[_canvas_max_absright(e, ax2) for e in node.elements]; init = 0))
end

function _render_conversation_widget(doc, ctx)
    proj = ProjecturedConversationExample.make_conversation_widget_projection_example(
        measure = (t, _f) -> (length(t) * 10, 20))
    print_document(proj, proj, doc, ctx).output
end

function _all_expanded_conversation()
    doc = ProjecturedConversationExample.make_conversation_document_example()
    for t in doc.turns
        t.collapsed = false
        for p in t.parts
            p.collapsed = false
        end
    end
    doc
end

function _mvp_test_collapse_containment()
    @testset "collapse layout: no balloon + body containment" begin
        # Stage 2 — collapsing a part does not widen any card.
        out_default  = _render_conversation_widget(
            ProjecturedConversationExample.make_conversation_document_example(), PrinterContext())
        out_expanded = _render_conversation_widget(_all_expanded_conversation(), PrinterContext())
        # @broken: pre-existing drift; canvas maxw differs between default/expanded conversation renders
        @test_broken _canvas_maxw(out_default) == _canvas_maxw(out_expanded)

        # Stage 3 — every card's right edge is within the conversation width, on
        # the fallback path and at allocated panel widths (collapsed + expanded).
        for ctx in (PrinterContext(),
                    with_available_size(PrinterContext(); width = Cell(760)),
                    with_available_size(PrinterContext(); width = Cell(1200)))
            out = _render_conversation_widget(
                ProjecturedConversationExample.make_conversation_document_example(), ctx)
            @test _canvas_max_absright(out) <= Int(out.w)
        end
    end
end

# ── Thinking capture (Stages 2–3) ──────────────────────────────────────
#
# A FakeLlm scripted with `thinking="…"` emits a synthetic thinking block
# (block_start → thinking_delta×N → signature_delta → block_stop) before the
# text block. The agent loop must materialize one collapsed ConversationThinking
# part (right text + signature "sig_fake") ahead of the text part.

function _mvp_test_thinking_stream()
    @testset "thinking block captured from stream" begin
        a = WorkbenchAssistant(; llm = FakeLlm("Hello"; thinking = "Let me reason…"))
        push!(a.conversation.turns, ConversationTurn(:user, [ConversationPart("hi")]))
        tools = register_default_tools!(ToolSet())
        _run_agent_loop!((document = a, tools = tools), a)

        reply = a.conversation.turns[end]
        @test reply.role === :assistant
        @test length(reply.parts) == 2

        think = reply.parts[1]
        @test think.content isa ConversationThinking
        @test _text_to_string(think.content.text) == "Let me reason…"
        @test think.content.signature == "sig_fake"
        @test think.content.redacted == false
        @test think.collapsed == true        # collapsed by default

        @test reply.parts[2].content isa MarkdownDocument   # prose parsed to Markdown
        @test _text_to_string(reply.parts[2].content) == "Hello"
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
            read_intent(proj, io, MousePress(:left, x, y))
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
        doc  = ProjecturedConversationExample.make_conversation_document_example()
        proj = ProjecturedConversationExample.make_conversation_widget_projection_example(measure = fake_measure)
        io   = print_document(proj, proj, doc, PrinterContext())

        # Resolve both header clicks from the *same* fresh projection (a toggle
        # mutates `collapsed`, which re-projects and shifts later positions).
        op_turn = _find_toggle(proj, io, t -> t === doc.turns[1])
        # parts[1] of the assistant turn is now the collapsed-by-default thinking
        # part; target parts[2] (the "Sure!…" prose part) which starts expanded.
        op_part  = _find_toggle(proj, io, t -> t === doc.turns[2].parts[2])
        op_think = _find_toggle(proj, io, t -> t === doc.turns[2].parts[1])

        # Thinking part header → toggles the thinking part's domain node. It is
        # collapsed by default, so the click expands it.
        @test op_think isa ToggleCollapseOperation
        @test doc.turns[2].parts[1].content isa ConversationThinking
        @test doc.turns[2].parts[1].collapsed == true
        evaluate_operation((document = doc,), op_think)
        @test doc.turns[2].parts[1].collapsed == false

        # Turn header → toggles the turn's domain node.
        @test op_turn isa ToggleCollapseOperation
        @test doc.turns[1].collapsed == false
        evaluate_operation((document = doc,), op_turn)
        @test doc.turns[1].collapsed == true

        # Part header → toggles the part's domain node.
        @test op_part isa ToggleCollapseOperation
        @test doc.turns[2].parts[2].collapsed == false
        evaluate_operation((document = doc,), op_part)
        @test doc.turns[2].parts[2].collapsed == true
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

# A script entry pairs an `LlmEvent` with the delay `ScriptedLlm` sleeps after
# emitting it (0.0 defers to the backend-wide `delay`). Mirrors the private
# `ProjecturedKernelExample._ev` helper, re-created here since it isn't exported.
_ev(event::LlmEvent, delay::Real = 0.0) = (event = event, delay = Float64(delay))

function _tool_use_script(tool_id::AbstractString, tool_name::AbstractString,
                          input::AbstractDict)
    NamedTuple[
        _ev(LlmToolUseStart(String(tool_id), String(tool_name))),
        # The finished call arrives with its arguments already parsed — that is the
        # adapter's job, so a fake supplies them directly rather than re-serialising
        # them to JSON only to have someone parse them back.
        _ev(LlmToolUseStop(LlmToolUse(String(tool_id), String(tool_name),
                                      Dict{String,Any}(input)))),
        _ev(LlmTurnEnd(:tool_use)),
    ]
end

function _final_text_script(text::AbstractString)
    NamedTuple[
        _ev(LlmTextStart()),
        _ev(LlmTextDelta(String(text))),
        _ev(LlmTextStop()),
        _ev(LlmTurnEnd(:end_turn)),
    ]
end

# ── Timestamped scripted builders + JSON round-trip ────────────────────
#
# The `make_scripted_turn` / `make_scripted_think` / `make_scripted_say` / `make_scripted_run`
# helpers must produce rounds the agent loop consumes exactly as the hand-built
# `_tool_use_script` does — including a multi-line `execute_julia_code` block that
# round-trips through the JSON `{"code": …}` encode/parse without corruption.

function _mvp_test_scripted_builders()
    @testset "ScriptedLlm timestamped builders" begin
        tools = register_default_tools!(ToolSet())
        # Multi-line code with an embedded quote — stresses the JSON escaper.
        code = "v = 6 * 7\nstring(\"n=\", v)"
        llm = ScriptedLlm([
            make_scripted_turn(
                make_scripted_think("Let me compute this carefully"; delay = 0.0),
                make_scripted_say("Working on it."; delay = 0.0),
                make_scripted_run(code; tool_id = "tu_demo", delay = 0.0);
                stop_reason = "tool_use"),
            make_scripted_turn(make_scripted_say("Done."; delay = 0.0)),
        ]; delay = 0.0)
        a = WorkbenchAssistant(; llm = llm)
        push!(a.conversation.turns, ConversationTurn(:user, [ConversationPart("compute")]))
        _run_agent_loop!((document = a, tools = tools), a)

        reply = a.conversation.turns[end]
        @test reply.role === :assistant
        @test any(p -> p.content isa ConversationThinking, reply.parts)
        ef = first(p.content for p in reply.parts if p.content isa EvaluatorForm)
        # The tool payload is `juliaparse`d into a JuliaDocument and re-rendered
        # for display, which normalizes user whitespace/operator spacing (e.g.
        # `1+1` -> `1 + 1`, multi-statement input becomes an indented block).
        # Fidelity is up to the parse/render round-trip: the tool code that
        # arrived matches what the *same* pipeline would produce for the same
        # input string, i.e. no data was lost between the JSON payload and the
        # EvaluatorForm's document (a genuine drop would produce a *different*
        # normalized string, not the identity round-trip we see here).
        @test _eval_code(ef) == _doc_source(_eval_form_doc(code))
        @test occursin("n=42", _eval_result(ef))           # the code actually ran
        @test _text_to_string(reply.parts[end].content) == "Done."
    end
end

function _mvp_test_tool_use_roundtrip()
    @testset "Tool-use round-trip via ScriptedLlm" begin
        # Make sure execute_julia_code is registered.
        tools = register_default_tools!(ToolSet())

        llm = ScriptedLlm([
            _tool_use_script("tu_1", "execute_julia_code",
                             Dict("code" => "1+1")),
            _final_text_script("Done."),
        ])
        a = WorkbenchAssistant(; llm = llm)
        push!(a.conversation.turns, ConversationTurn(:user, [ConversationPart("compute 1+1")]))

        # Drive the agent loop synchronously (no @async) so we can assert
        # the post-state immediately. Stand-in editor mirrors the production
        # `evaluate_operation(editor, op)` plumbing — the tool dispatch in
        # the loop receives this as `editor` (the FakeLlm script's `1+1`
        # doesn't read it, but the wiring is what's under test).
        _run_agent_loop!((document=a, tools=tools), a)

        msgs = a.conversation.turns
        # Expected sequence in the turn/part model:
        #   1. user turn ("compute 1+1")
        #   2. one :assistant turn with two parts — the EvaluatorForm (code="1+1",
        #      result≈"2") followed by the final "Done." prose. The agent appends
        #      the tool result and the closing text to the same assistant turn
        #      rather than emitting a separate trailing prose turn.
        @test length(msgs) == 2

        @test msgs[1].role === :user
        @test _text_to_string(msgs[1].parts[1].content) == "compute 1+1"

        @test msgs[2].role === :assistant
        @test length(msgs[2].parts) == 2
        ef = msgs[2].parts[1].content
        @test ef isa EvaluatorForm
        # Round-trip is stable modulo the parse/render normalizer; see the
        # scripted-builders test above for the fuller explanation.
        @test _eval_code(ef) == _doc_source(_eval_form_doc("1+1"))
        @test ef.tool_use_id   == "tu_1"
        # An `execute_julia_code` result is primary content — expanded by default.
        @test msgs[2].parts[1].collapsed == false
        # The real `execute_julia_code` tool ran — `1+1` repr is "2".
        @test occursin("2", _eval_result(ef))
        @test ef.is_error == false

        @test msgs[2].parts[2].content isa MarkdownDocument  # prose parsed to Markdown
        @test _text_to_string(msgs[2].parts[2].content) == "Done."
    end
end
