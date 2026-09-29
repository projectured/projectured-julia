"""
    ProjecturedAnthropicTest

The Anthropic tier of the test-package DAG: the suite for the Claude adapter.

What is worth testing here is translation and choice, and neither needs the
network: the suite renders a request into Anthropic's JSON, it reads a stream
body into events, and it picks a model from a recorded answer of the Models API.
A stand-in server on this machine answers the stream of a turn. One test asks
the real API, and it skips itself when no key is exported.

Everything is aggregated by `test_anthropic()`.
"""
module ProjecturedAnthropicTest

using Test
using HTTP
using JSON3
using ProjecturedKernel
using ProjecturedKernelTest
using ProjecturedAnthropic

import ProjecturedKernel.ToolModule: Tool
import ProjecturedKernel.LlmModule:
    make_llm, default_llm_model, get_llm_backend_names, stream_turn, render_tool_schema,
    LlmText, LlmMessage, LlmRequest,
    LlmTextStart, LlmTextDelta, LlmTextStop, LlmTurnEnd

include("../../../test/anthropic/AnthropicTest.jl")
include("../../../test/anthropic/AnthropicSuite.jl")

end # module ProjecturedAnthropicTest
