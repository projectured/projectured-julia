# ── Agent layer — the AI control surface (side-stack) ──────────────────────
# The ordered include list of the agent layer; a fragment of ProjecturedKernel.
# AgentModule declares the make_agent_server / start_agent_server! /
# stop_agent_server! seam the editor loop reaches through: the *inbound*
# direction, where something outside — an external agent — drives this editor.
#
# The outbound direction (this editor driving a model) is the llm layer below;
# what an agent may *do* is the tool layer below that. The layer knows nothing of
# MCP: that is a protocol, and the transport implementing this seam is the opt-in
# ProjecturedMcp package.
include("Agent.jl")
