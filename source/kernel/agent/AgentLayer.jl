# ── Agent layer — the AI control surface (side-stack) ──────────────────────
# The ordered include list of the agent layer; a fragment of ProjecturedKernel.
#
# The layer is two directions through the same tool surface:
#
#   AgentServerModule — inbound.  Something outside drives this editor. The editor
#                       loop reaches it through make_agent_server / start / stop,
#                       a seam a transport package implements out of tree.
#   AgentModule       — outbound. This editor drives a model: the Agent, and the
#                       run_turn! loop that streams a round, dispatches the tools
#                       the model asked for, and goes again until it stops asking.
#
# Neither knows about MCP, and neither knows about any particular model: what an
# agent may *do* is the tool layer, and how it *speaks* is the llm layer, both below.
include("AgentServerModule.jl")
include("AgentModule.jl")
