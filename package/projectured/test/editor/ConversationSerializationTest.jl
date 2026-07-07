# Stage 4 — conversation → LLM messages / string.
# Asserts build_messages turns a mixed turn/part conversation into the Anthropic
# array (roles, message count, per-block shape, multi-part → one message) and that
# structured parts serialize as fenced source via their print chain.

using Projectured: ConversationConversation, ConversationTurn, ConversationPart,
                   ConversationThinking, thinking_part,
                   TextText, TextString, EvaluatorForm, JuliaIdentifier,
                   juliaparse, jsonparse, xmlparse, result_text,
                   build_messages, conversation_to_string

function test_conversation_serialization()
    @testset "Conversation serialization (Stage 4)" begin

        @testset "multi-part user turn → one message, fenced blocks joined" begin
            turn = ConversationTurn(:user, [
                ConversationPart("hello"),
                ConversationPart(juliaparse("2+2")),
                ConversationPart(jsonparse("""{"a": 1}""")),
                ConversationPart(xmlparse("<a/>")),
            ])
            msgs = build_messages(ConversationConversation([turn]))
            @test length(msgs) == 1
            @test msgs[1]["role"] == "user"
            blocks = msgs[1]["content"]
            # The parts join into a single text block, blank-line separated so the
            # fenced sources stay apart (adjacent API text blocks concatenate raw).
            @test length(blocks) == 1
            @test blocks[1]["type"] == "text"
            txt = blocks[1]["text"]
            @test startswith(txt, "hello")
            @test occursin("\n\n```julia", txt) && occursin("2 + 2", txt)
            @test occursin("\n\n```json", txt)  && occursin("\"a\": 1", txt)
            @test occursin("\n\n```xml", txt)   && occursin("<a", txt)
        end

        @testset "user inline eval → single user text block" begin
            turn = ConversationTurn(:user, [
                ConversationPart(EvaluatorForm(JuliaIdentifier("2+2"); result = result_text("4"))),
            ])
            msgs = build_messages(ConversationConversation([turn]))
            @test length(msgs) == 1 && msgs[1]["role"] == "user"
            @test occursin("I ran the following Julia code", msgs[1]["content"][1]["text"])
            @test occursin("4", msgs[1]["content"][1]["text"])
        end

        @testset "assistant tool call → tool_use + tool_result pair" begin
            convo = ConversationConversation([
                ConversationTurn(:user, [ConversationPart("run it")]),
                ConversationTurn(:assistant, [ConversationPart("sure")]),
                ConversationTurn(:assistant, [ConversationPart(
                    EvaluatorForm(JuliaIdentifier("2+2");
                                  result = result_text("4"), tool_use_id = "tu_1"))]),
            ])
            msgs = build_messages(convo)
            @test [m["role"] for m in msgs] == ["user", "assistant", "user"]
            tool_use = msgs[2]["content"][end]
            @test tool_use["type"] == "tool_use" && tool_use["id"] == "tu_1"
            tool_result = msgs[3]["content"][1]
            @test tool_result["type"] == "tool_result" && tool_result["tool_use_id"] == "tu_1"
        end

        @testset "thinking + tool_use round-trip: ordering + signature" begin
            convo = ConversationConversation([
                ConversationTurn(:user, [ConversationPart("run it")]),
                ConversationTurn(:assistant, [
                    thinking_part("Let me reason about this…"; signature = "sig_1"),
                    ConversationPart("I'll run it."),
                ]),
                ConversationTurn(:assistant, [ConversationPart(
                    EvaluatorForm(JuliaIdentifier("2+2");
                                  result = result_text("4"), tool_use_id = "tu_1"))]),
            ])
            msgs = build_messages(convo)
            @test [m["role"] for m in msgs] == ["user", "assistant", "user"]
            blocks = msgs[2]["content"]
            # thinking first, then text, then tool_use — all in ONE assistant message.
            @test [b["type"] for b in blocks] == ["thinking", "text", "tool_use"]
            @test blocks[1]["thinking"] == "Let me reason about this…"
            @test blocks[1]["signature"] == "sig_1"
            @test blocks[3]["id"] == "tu_1"
            @test msgs[3]["content"][1]["tool_use_id"] == "tu_1"
        end

        @testset "redacted thinking block round-trips as data" begin
            convo = ConversationConversation([
                ConversationTurn(:assistant, [
                    thinking_part(""; redacted = true, data = "enc_abc"),
                    ConversationPart("done"),
                ]),
            ])
            msgs = build_messages(convo)
            blocks = msgs[1]["content"]
            @test blocks[1]["type"] == "redacted_thinking"
            @test blocks[1]["data"] == "enc_abc"
            @test !haskey(blocks[1], "signature")
            @test blocks[2]["type"] == "text"
        end

        @testset "user turn drops stray thinking parts" begin
            convo = ConversationConversation([
                ConversationTurn(:user, [
                    thinking_part("should not be sent"),
                    ConversationPart("hello"),
                ]),
            ])
            msgs = build_messages(convo)
            @test length(msgs[1]["content"]) == 1
            @test msgs[1]["content"][1]["text"] == "hello"
        end

        @testset "conversation_to_string is readable" begin
            convo = ConversationConversation([
                ConversationTurn(:user, [ConversationPart("hi"), ConversationPart(jsonparse("[1,2]"))]),
                ConversationTurn(:assistant, [ConversationPart("hello")]),
            ])
            s = conversation_to_string(convo)
            @test occursin("User:", s) && occursin("Assistant:", s)
            @test occursin("```json", s) && occursin("hi", s) && occursin("hello", s)
        end
    end
end
