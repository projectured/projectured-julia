# Fragment of `ApplicationModule` — the settings that the application reads when
# it starts.

"""
    StartSettings(; assistant = :ollama, model = "", context = 0, mcp = false)

The assistant the application starts with, its model, how much of the
conversation it can see, and whether the MCP server starts too.

What the application starts with: the backend and the model of the assistant, the
context of the model, and whether the MCP server starts beside the window. The
application reads them once, when it starts, so a change takes effect at the next
start. The command line wins over them for its run.
"""
@settings struct StartSettings
    "Assistant: the backend of the assistant, a local model, a model of Anthropic, or none."
    assistant::Symbol = :ollama in APPLICATION_ASSISTANTS
    "Model: the model of the assistant; empty takes the default of its backend."
    model::String = ""
    "Context: the tokens of the conversation that the model may see; 0 leaves it to the backend."
    context::Int = 0 in 0:1024:1048576
    "MCP server: start the MCP server beside the window."
    mcp::Bool = false
end

is_settings_group_read_at_start(::Type{StartSettings}) = true
