"""
    ProjecturedLanguageServerTest

The language server tier of the test-package DAG: the suite for the language
server adapter.

A language server in this process (`FakeLanguageServer`) answers the tests on
two streams, so the suite runs on a machine with no language server. The tests
that start `clangd` skip themselves when it is not installed.

Everything is aggregated by `test_languageserver()`.
"""
module ProjecturedLanguageServerTest

using Test
using JSON3
using ProjecturedKernel
using ProjecturedKernelTest
using ProjecturedPlatform
using ProjecturedLanguageServer

include("../../../test/adapter/languageserver/FakeLanguageServer.jl")
include("../../../test/adapter/languageserver/LanguageServerConnectionTest.jl")
include("../../../test/adapter/languageserver/LanguageServerSuite.jl")

end # module ProjecturedLanguageServerTest
