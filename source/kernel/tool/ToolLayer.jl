# ── Tool layer — the editor's capability surface ───────────────────────────
# The ordered include list of the tool layer; a fragment of ProjecturedKernel.
# ToolModule is what the editor can be *asked to do*: an action (`Tool`) and a
# read-only datum (`Resource`), collected in a `ToolSet`, plus the built-in
# tools an editor ships with — code execution and documentation/API search.
#
# The layer depends on nothing and knows about neither LLMs nor MCP: the tool
# surface is a pivot that higher layers turn on, and each reaches it from its own
# side — an in-process agent loop drives a ToolSet, an out-of-process protocol
# server exposes one, a provider adapter renders a Tool into its own schema —
# without this layer naming any of them.
include("ToolModule.jl")
