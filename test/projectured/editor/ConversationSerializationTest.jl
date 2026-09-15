# Stage 4 — conversation → LLM messages / string.
# Asserts build_messages turns a mixed turn/part conversation into `LlmMessage`s
# (roles, message count, per-block content type, multi-part → one message) and that
# structured parts serialize as fenced source via their print chain.

import ProjecturedKernel.LlmModule: LlmMessage, LlmText, LlmThinking,
                                    LlmRedactedThinking, LlmToolUse, LlmToolResult
# The form a call's text becomes, so a replay test can build one the way the
# agent loop does.
import ProjecturedAssistant.AssistantModule: _eval_form_doc

function test_conversation_serialization()
    @testset "Conversation serialization (Stage 4)" begin

        @testset "multi-part user turn → one message, fenced blocks joined" begin
            turn = ConversationTurn(:user, [
                ConversationPart("hello"),
                ConversationPart(parse_julia("2+2")),
                ConversationPart(parse_json("""{"a": 1}""")),
                ConversationPart(parse_xml("<a/>")),
            ])
            msgs = build_messages(ConversationConversation([turn]))
            @test length(msgs) == 1
            @test msgs[1].role === :user
            blocks = msgs[1].content
            # The parts join into a single text block, blank-line separated so the
            # fenced sources stay apart (adjacent text blocks concatenate raw).
            @test length(blocks) == 1
            @test blocks[1] isa LlmText
            txt = blocks[1].text
            @test startswith(txt, "hello")
            @test occursin("\n\n```julia", txt) && occursin("2 + 2", txt)
            @test occursin("\n\n```json", txt)  && occursin("\"a\": 1", txt)
            @test occursin("\n\n```xml", txt)   && occursin("<a", txt)
        end

        @testset "user inline eval → single user text block" begin
            turn = ConversationTurn(:user, [
                ConversationPart(EvaluatorForm(JuliaIdentifier("2+2"); result = make_evaluator_result_text("4"))),
            ])
            msgs = build_messages(ConversationConversation([turn]))
            @test length(msgs) == 1 && msgs[1].role === :user
            @test occursin("I ran the following Julia code", msgs[1].content[1].text)
            @test occursin("4", msgs[1].content[1].text)
        end

        @testset "assistant tool call → tool_use + tool_result pair" begin
            convo = ConversationConversation([
                ConversationTurn(:user, [ConversationPart("run it")]),
                ConversationTurn(:assistant, [ConversationPart("sure")]),
                ConversationTurn(:assistant, [ConversationPart(
                    EvaluatorForm(JuliaIdentifier("2+2");
                                  result = make_evaluator_result_text("4"), tool_use_id = "tu_1"))]),
            ])
            msgs = build_messages(convo)
            @test [m.role for m in msgs] == [:user, :assistant, :user]
            tool_use = msgs[2].content[end]
            @test tool_use isa LlmToolUse && tool_use.id == "tu_1"
            tool_result = msgs[3].content[1]
            @test tool_result isa LlmToolResult && tool_result.tool_use_id == "tu_1"
        end

        @testset "a call replays as the text it was made with" begin
            # The form is a *projection* of the code, and a projection is not
            # reversible: an unparsable snippet is held as a PrimitiveString whose
            # stringification is its constructor repr, a fenced one parses as a
            # command macro, and a comment-only one parses to nothing. Re-deriving
            # source from the form put all three into the model's history as the
            # code it apparently wrote — and it copied what it was shown, calling
            # `PrimitiveString(…)`, which no scratch module resolves.
            replayed(sent) = begin
                convo = ConversationConversation([
                    ConversationTurn(:user, [ConversationPart("run it")]),
                    ConversationTurn(:assistant, [ConversationPart(
                        EvaluatorForm(_eval_form_doc(sent);
                                      source = sent, result = make_evaluator_result_text("ok"),
                                      tool_use_id = "tu_1"))])])
                only([c for m in build_messages(convo) for c in m.content
                      if c isa LlmToolUse]).input["code"]
            end
            for sent in ["run_simulations(editor",              # does not parse
                         "```julia\nrun_simulations(editor)\n```",  # fenced
                         "# just a comment",                    # comment only
                         "run_simulations(editor)"]             # parses cleanly
                @test replayed(sent) == sent
            end

            # A form kept without a source — an older transcript, or one a person
            # typed — still answers from the document.
            convo = ConversationConversation([
                ConversationTurn(:user, [ConversationPart("run it")]),
                ConversationTurn(:assistant, [ConversationPart(
                    EvaluatorForm(JuliaIdentifier("2+2");
                                  result = make_evaluator_result_text("4"), tool_use_id = "tu_1"))])])
            kept = only([c for m in build_messages(convo) for c in m.content
                         if c isa LlmToolUse])
            @test kept.input["code"] == "2+2"
        end

        @testset "a call that kept its input replays as itself" begin
            convo = ConversationConversation([
                ConversationTurn(:user, [ConversationPart("look it up")]),
                ConversationTurn(:assistant, [ConversationPart(
                    EvaluatorForm(TextBlock(TextString("uri: resource://guide/orientation"));
                                  tool_name = "read_resource",
                                  input = Dict{String,Any}("uri" => "resource://guide/orientation"),
                                  result = make_evaluator_result_text("# Orientation"),
                                  tool_use_id = "tu_1"))])])
            call = only([c for m in build_messages(convo) for c in m.content if c isa LlmToolUse])
            @test call.name == "read_resource"
            @test call.input == Dict{String,Any}("uri" => "resource://guide/orientation")
            @test call.id == "tu_1"
            # The plain rendering names the tool before the arguments.
            text = format_conversation(convo)
            @test occursin("# resource · resource://guide/orientation", text)
        end

        @testset "thinking + tool_use round-trip: ordering + signature" begin
            convo = ConversationConversation([
                ConversationTurn(:user, [ConversationPart("run it")]),
                ConversationTurn(:assistant, [
                    make_conversation_thinking_part("Let me reason about this…"; signature = "sig_1"),
                    ConversationPart("I'll run it."),
                ]),
                ConversationTurn(:assistant, [ConversationPart(
                    EvaluatorForm(JuliaIdentifier("2+2");
                                  result = make_evaluator_result_text("4"), tool_use_id = "tu_1"))]),
            ])
            msgs = build_messages(convo)
            @test [m.role for m in msgs] == [:user, :assistant, :user]
            blocks = msgs[2].content
            # thinking first, then text, then tool_use — all in ONE assistant message.
            @test [typeof(b) for b in blocks] == [LlmThinking, LlmText, LlmToolUse]
            @test blocks[1].text == "Let me reason about this…"
            @test blocks[1].signature == "sig_1"
            @test blocks[3].id == "tu_1"
            @test msgs[3].content[1].tool_use_id == "tu_1"
        end

        @testset "redacted thinking block round-trips as data" begin
            convo = ConversationConversation([
                ConversationTurn(:assistant, [
                    make_conversation_thinking_part(""; redacted = true, data = "enc_abc"),
                    ConversationPart("done"),
                ]),
            ])
            msgs = build_messages(convo)
            blocks = msgs[1].content
            @test blocks[1] isa LlmRedactedThinking
            @test blocks[1].data == "enc_abc"
            # A withheld block has no signature to carry — the type says so.
            @test !hasproperty(blocks[1], :signature)
            @test blocks[2] isa LlmText
        end

        @testset "user turn drops stray thinking parts" begin
            convo = ConversationConversation([
                ConversationTurn(:user, [
                    make_conversation_thinking_part("should not be sent"),
                    ConversationPart("hello"),
                ]),
            ])
            msgs = build_messages(convo)
            @test length(msgs[1].content) == 1
            @test msgs[1].content[1].text == "hello"
        end

        # A pane that greets the person on open writes an assistant turn nobody
        # sent, and a payload cannot open with an assistant message.
        @testset "a leading assistant turn is not sent" begin
            convo = ConversationConversation([
                ConversationTurn(:assistant, [ConversationPart("Hello. I am here.")]),
                ConversationTurn(:user, [ConversationPart("hi")]),
                ConversationTurn(:assistant, [ConversationPart("hello")]),
            ])
            msgs = build_messages(convo)
            @test [m.role for m in msgs] == [:user, :assistant]
            @test msgs[1].content[1].text == "hi"
            @test msgs[2].content[1].text == "hello"

            # With no user turn there is no first message to protect, and the
            # conversation serializes whole.
            alone = ConversationConversation([
                ConversationTurn(:assistant, [ConversationPart("Hello. I am here.")])])
            @test [m.role for m in build_messages(alone)] == [:assistant]
        end

        @testset "format_conversation is readable" begin
            convo = ConversationConversation([
                ConversationTurn(:user, [ConversationPart("hi"), ConversationPart(parse_json("[1,2]"))]),
                ConversationTurn(:assistant, [ConversationPart("hello")]),
            ])
            s = format_conversation(convo)
            @test occursin("User:", s) && occursin("Assistant:", s)
            @test occursin("```json", s) && occursin("hi", s) && occursin("hello", s)
        end
    end
end
