"""
`LlmModule` — the fallbacks of the provider contract, and what the layer does
itself. Verifies the error of `make_llm` and of `get_default_llm_model` for a kind
that no package answers, the registry that `get_llm_backend_names` reads from
the method table, the opacity of a backend to the document walk, and the
conversions of the `LlmMessage` and `LlmRequest` constructors.
"""

using Test
using ProjecturedKernel.DocumentModule: is_walk_opaque
using ProjecturedKernel.LlmModule
using ProjecturedKernel.ToolModule: Tool
using ProjecturedKernelExample: FakeLlm

# A test-local backend kind: the `Val`-keyed methods register `:llm_defaults_probe`
# the same way an opt-in provider package registers its kind.
ProjecturedKernel.LlmModule.make_llm(::Val{:llm_defaults_probe}; kwargs...) =
    FakeLlm("probe")
ProjecturedKernel.LlmModule.get_default_llm_model(::Val{:llm_defaults_probe}) =
    "probe-model"

# The text of the exception that `f` throws, or "" when it throws none.
function _get_llm_error_text(f)
    try
        f()
        ""
    catch exception
        sprint(showerror, exception)
    end
end

function test_llm_defaults()
@testset "Llm defaults" begin

    @testset "a kind that no package answers names the loaded kinds in its error" begin
        missing_kind = :llm_defaults_missing
        text = _get_llm_error_text(() -> make_llm(missing_kind))
        @test occursin("No LLM backend registered for :llm_defaults_missing", text)
        @test occursin(":llm_defaults_probe", text)
        @test occursin("Load the opt-in package that provides :llm_defaults_missing",
                       text)
        @test_throws ErrorException get_default_llm_model(missing_kind)
        @test occursin("it has no default model",
                       _get_llm_error_text(() -> get_default_llm_model(missing_kind)))
    end

    @testset "a kind reaches the method of its package through the symbol" begin
        @test make_llm(:llm_defaults_probe) isa FakeLlm
        @test get_default_llm_model(:llm_defaults_probe) == "probe-model"
    end

    # The two generic methods of the defaults take a `Symbol` and `Val{K} where K`,
    # and neither is a backend.
    @testset "the backends are the kinds in the method table, sorted" begin
        names = get_llm_backend_names()
        @test names isa Vector{Symbol}
        @test :llm_defaults_probe in names
        @test issorted(names) && allunique(names)
        @test !(:K in names)
    end

    @testset "a backend is opaque to the document walk" begin
        @test is_walk_opaque(FakeLlm())
    end

    @testset "a message keeps a text as one text block" begin
        message = LlmMessage(:user, SubString("hello", 1, 2))
        @test message.role === :user
        @test message.content isa Vector{LlmContent}
        @test only(message.content) isa LlmText
        @test only(message.content).text === "he"
        call = LlmToolUse("tu_1", "probe", Dict{String,Any}())
        blocks = LlmMessage(:assistant, call).content
        @test blocks isa Vector{LlmContent}
        @test only(blocks) === call
    end

    @testset "a request converts what it gets, and defaults to an empty turn" begin
        empty_request = LlmRequest()
        @test empty_request.system == ""
        @test isempty(empty_request.messages) && isempty(empty_request.tools)
        @test !empty_request.thinking

        messages = [LlmMessage(:user, "hi")]
        tool = Tool("probe", "a tool of the test", NamedTuple[],
                    (target, arguments) -> "")
        request = LlmRequest(; system = SubString("be brief", 1, 2), messages,
                             tools = [tool], thinking = true)
        @test request.system === "be"
        @test request.messages isa Vector{LlmMessage}
        @test request.messages == messages && request.messages !== messages
        @test request.tools isa Vector{Tool} && only(request.tools) === tool
        @test request.thinking
    end

end
end # test_llm_defaults
