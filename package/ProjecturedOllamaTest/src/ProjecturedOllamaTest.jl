"""
    ProjecturedOllamaTest

The Ollama tier of the test-package DAG: the suite for the Ollama adapter.

What is worth testing here is translation, and translation needs no server. The
suite renders a request into Ollama's JSON and feeds recorded stream lines back
through the reader, so it runs on a machine with no model installed. One test does
talk to a server, and skips itself when none answers.

Everything is aggregated by `test_ollama()`.
"""
module ProjecturedOllamaTest

using Test
using HTTP
using JSON3
using ProjecturedKernel
using ProjecturedKernelTest
using ProjecturedOllama

import ProjecturedKernel.ToolModule: Tool
import ProjecturedKernel.LlmModule:
    make_llm, default_llm_model, llm_backend_names, stream_turn, tool_schema,
    LlmContent, LlmText, LlmThinking, LlmToolUse, LlmToolResult,
    LlmMessage, LlmRequest,
    LlmTextStart, LlmTextDelta, LlmTextStop,
    LlmThinkingStart, LlmThinkingDelta, LlmThinkingStop,
    LlmToolUseStart, LlmToolInputDelta, LlmToolUseStop,
    LlmTurnEnd, LlmFailure

include("../../../test/ollama/OllamaTest.jl")
include("../../../test/ollama/OllamaSuite.jl")

end # module ProjecturedOllamaTest
