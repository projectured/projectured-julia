# The Claude adapter: which model a backend names, and what a request carries.
#
# Nothing here reaches the network, except the one test that asks the real API
# and skips itself when no key is exported.

# One answer of the Models API, as the documentation shows it: newest first, and
# each model with the capability block that says which thinking it takes. The
# second entry is the newest model that takes adaptive thinking, and the first
# one is a model that takes none.
const _RECORDED_MODELS = """
{
  "data": [
    {"type": "model", "id": "claude-batch-only-9", "created_at": "2026-09-01T00:00:00Z",
     "display_name": "Batch only",
     "capabilities": {"thinking": {"supported": true,
                                   "types": {"enabled": {"supported": true},
                                             "adaptive": {"supported": false}}}}},
    {"type": "model", "id": "claude-opus-5", "created_at": "2026-07-24T00:00:00Z",
     "display_name": "Claude Opus 5",
     "capabilities": {"thinking": {"supported": true,
                                   "types": {"enabled": {"supported": true},
                                             "adaptive": {"supported": true}}}}},
    {"type": "model", "id": "claude-sonnet-5", "created_at": "2026-05-01T00:00:00Z",
     "display_name": "Claude Sonnet 5",
     "capabilities": {"thinking": {"supported": true,
                                   "types": {"adaptive": {"supported": true}}}}}
  ],
  "has_more": false
}
"""

function test_anthropic_model()
    @testset "the model a backend names" begin
        @testset "the newest model that takes adaptive thinking" begin
            # The list is newest first, and the first two entries differ only in
            # that capability, so the answer says the choice reads it.
            @test find_adaptive_model(_RECORDED_MODELS) == "claude-opus-5"
            # An answer with no model, and one that is not JSON at all.
            @test find_adaptive_model("""{"data": [], "has_more": false}""") == ""
            @test find_adaptive_model("not json") == ""
            # A model with no capability block is left out rather than guessed
            # about.
            @test find_adaptive_model("""{"data": [{"id": "claude-old"}]}""") == ""
        end

        @testset "a backend with no key names the alias" begin
            # No key, no request: the alias is a name that keeps working after a
            # new model comes out.
            llm = AnthropicLlm(; api_key = "")
            @test llm.model == "claude-opus-5"
            @test default_llm_model(Val(:anthropic)) == "claude-opus-5"
            # A name a caller wrote wins over the choice.
            @test AnthropicLlm(; api_key = "", model = "claude-sonnet-5").model ==
                  "claude-sonnet-5"
        end

        @testset "the backend registers itself on the seam" begin
            @test :anthropic in get_llm_backend_names()
            @test make_llm(Val(:anthropic); api_key = "", model = "m") isa AnthropicLlm
        end

        @testset "a tool goes into the shape Anthropic reads" begin
            tool = Tool("count_words", "Count the words of a text",
                        NamedTuple[(name = "text", type = "string",
                                    description = "the text", required = true)],
                        (arguments, target) -> "3")
            rendered = only(render_tool_schema(AnthropicLlm(; api_key = ""), [tool]))
            @test rendered["name"] == "count_words"
            @test rendered["description"] == "Count the words of a text"
            @test rendered["input_schema"]["properties"]["text"]["type"] == "string"
            @test rendered["input_schema"]["required"] == ["text"]
        end

        @testset "the live Models API" begin
            key = get(ENV, "ANTHROPIC_API_KEY", "")
            if isempty(key)
                @test_skip "no ANTHROPIC_API_KEY"
            else
                model = get_newest_anthropic_model(key)
                @test startswith(model, "claude-")
            end
        end
    end
end
