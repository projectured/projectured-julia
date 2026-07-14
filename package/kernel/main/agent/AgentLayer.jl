# ── Agent layer — the AI control surface (side-stack) ──────────────────────
# The ordered include list of the agent layer; a fragment of ProjecturedKernel.
# AgentModule declares the make_agent_server / start_agent_server! /
# stop_agent_server! seam the editor loop reaches through. Llm, ToolRegistry,
# Mcp are the dependency-free client seams the real transports (opt-in
# ProjecturedLlm / ProjecturedMcp packages) implement against.
include("Agent.jl")
include("Llm.jl")
include("ToolRegistry.jl")
include("Mcp.jl")
