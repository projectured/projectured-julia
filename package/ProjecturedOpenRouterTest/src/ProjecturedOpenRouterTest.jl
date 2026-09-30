"""
    ProjecturedOpenRouterTest

The OpenRouter tier of the test-package DAG: the suite for the relevance model
on the Decisions API.

What is worth testing here is translation, and it needs no network: the suite
gives the model a stand-in for the request, checks the requests it builds, and
answers them from a table. One test asks the real API, and it skips itself when
no key is exported.

Everything is aggregated by `test_openrouter()`.
"""
module ProjecturedOpenRouterTest

using Test
using JSON3
using ProjecturedKernel
using ProjecturedKernelTest
using ProjecturedOpenRouter

import ProjecturedKernel.ToolModule: RelevanceModel, ToolSet, declare_api!, set_relevance_model!,
                                     search_api

include("../../../test/adapter/openrouter/OpenRouterTest.jl")
include("../../../test/adapter/openrouter/OpenRouterSuite.jl")

end # module ProjecturedOpenRouterTest
