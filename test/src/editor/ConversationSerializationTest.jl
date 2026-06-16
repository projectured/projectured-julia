# Stage 4 — conversation → LLM messages / string.
# Asserts build_messages turns a mixed turn/part conversation into the Anthropic
# array (roles, message count, per-block shape, multi-part → one message) and that
# structured parts serialize as fenced source via their print chain.

using Projectured: ConversationConversation, ConversationTurn, ConversationPart,
                   TextText, TextString, EvaluatorForm, JuliaIdentifier,
                   juliaparse, jsonparse, xmlparse, result_text,
                   build_messages, conversation_to_string

function test_conversation_serialization()
    @testset "Conversation serialization (Stage 4)" begin

        @testset "multi-part user turn → one message, fenced blocks" begin
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
            @test length(blocks) == 4
            @test all(b -> b["type"] == "text", blocks)
            @test blocks[1]["text"] == "hello"
            @test occursin("```julia", blocks[2]["text"]) && occursin("2 + 2", blocks[2]["text"])
            @test occursin("```json", blocks[3]["text"]) && occursin("\"a\": 1", blocks[3]["text"])
            @test occursin("```xml", blocks[4]["text"]) && occursin("<a", blocks[4]["text"])
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
