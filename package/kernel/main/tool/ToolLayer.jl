# ── Tool layer — the editor's capability surface ───────────────────────────
# The ordered include list of the tool layer; a fragment of ProjecturedKernel.
# ToolModule is what the editor can be *asked to do*: an action (`Tool`) and a
# read-only datum (`Resource`), collected in a `ToolSet`, plus the built-in
# tools an editor ships with — code execution and documentation/API search.
#
# The layer depends on nothing. It knows about neither LLMs nor MCP: the tool
# surface is the pivot both of them turn on, and each reaches it from its own
# side — an agent loop drives a ToolSet locally (the `agent` layer), an MCP
# server exposes one to the outside (the opt-in ProjecturedMcp package), and a
# provider adapter renders a Tool into its own schema (ProjecturedLlm).
include("ToolModule.jl")
