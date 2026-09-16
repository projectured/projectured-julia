"""
    ProjecturedOllamaTest

The Ollama tier of the test-package DAG: the suite for the Ollama adapter.

What is worth testing here is translation, and translation needs no server. The
suite renders a request into Ollama's JSON and feeds recorded stream lines back
through the reader, so it runs on a machine with no model installed. The meaning
vectors are asked of a stand-in server that the test starts on this machine. Two
tests talk to the real server, and each skips itself when the server or its model
is missing.

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
    make_llm, default_llm_model, get_llm_backend_names, stream_turn, render_tool_schema,
    has_meaning_model, get_meaning_model_name, compute_meaning_vectors,
    LlmContent, LlmText, LlmThinking, LlmToolUse, LlmToolResult,
    LlmMessage, LlmRequest,
    LlmTextStart, LlmTextDelta, LlmTextStop,
    LlmThinkingStart, LlmThinkingDelta, LlmThinkingStop,
    LlmToolUseStart, LlmToolInputDelta, LlmToolUseStop,
    LlmTurnEnd, LlmFailure

include("../../../test/ollama/OllamaTest.jl")
include("../../../test/ollama/OllamaSuite.jl")

end # module ProjecturedOllamaTest
