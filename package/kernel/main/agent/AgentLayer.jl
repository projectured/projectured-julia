# ── Agent layer — the AI control surface (side-stack) ──────────────────────
# The ordered include list of the agent layer; a fragment of ProjecturedKernel.
# AgentModule declares the make_agent_server / start_agent_server! /
# stop_agent_server! seam the editor loop reaches through — the *inbound*
# direction, where something outside drives this editor. LlmModule is the
# *outbound* seam: the provider abstraction the editor drives a model through.
#
# The layer knows nothing of MCP — that is a protocol, and the transport
# implementing the server seam is the opt-in ProjecturedMcp package, exactly as
# ProjecturedLlm implements the provider seam. What an agent can *do* is a
# ToolSet, which both directions reach from the tool layer below.
include("Agent.jl")
include("Llm.jl")
