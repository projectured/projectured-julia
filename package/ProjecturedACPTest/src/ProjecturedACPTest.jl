"""
    ProjecturedACPTest

The ACP tier of the test-package DAG: the suite for the client of the Agent
Client Protocol.

What is worth testing here is the exchange with an agent, and the exchange needs
no real agent. The suite translates recorded shapes of updates, talks to a fake
agent in this process through two streams, and starts a small child process in
plain Julia to test the start and the end of an agent process.

Everything is aggregated by `test_acp()`.
"""
module ProjecturedACPTest

using Test
using JSON3
using ProjecturedKernel
using ProjecturedKernelTest
using ProjecturedACP

using ProjecturedKernel.LlmModule: LlmText, LlmToolUse,
    LlmTextStart, LlmTextDelta, LlmTextStop,
    LlmThinkingStart, LlmThinkingDelta, LlmThinkingStop
using ProjecturedKernel.AgentModule: make_agent_connection, start_agent_connection!,
    open_agent_session!, set_agent_option!, send_agent_prompt!, cancel_agent_prompt!,
    close_agent_session!, stop_agent_connection!, AgentToolCallUpdate, AgentPlanEntry,
    AgentPlanUpdate, AgentPermissionRequest, AgentOptionsUpdate, AgentUsageUpdate,
    AgentSessionInfoUpdate

include("../../../test/adapter/acp/FakeAcpAgent.jl")
include("../../../test/adapter/acp/AcpUpdateTest.jl")
include("../../../test/adapter/acp/AcpConnectionTest.jl")
include("../../../test/adapter/acp/AcpTransportTest.jl")
include("../../../test/adapter/acp/AcpSuite.jl")

end # module ProjecturedACPTest
