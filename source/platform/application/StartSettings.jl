# Fragment of `ApplicationModule` — the settings that the application reads when
# it starts.

"""
    StartSettings(; assistant = :ollama, model = "", context = 0, mcp = false,
                    agent_command = DEFAULT_AGENT_COMMAND,
                    agent_session_meta = DEFAULT_AGENT_SESSION_META)

The assistant the application starts with, its model, how much of the
conversation it can see, whether the MCP server starts too, and the command and
the session options of the external agent of the backend `:acp`.

What the application starts with: the backend and the model of the assistant, the
context of the model, and whether the MCP server starts beside the window. The
application reads them once, when it starts, so a change takes effect at the next
start. The command line wins over them for its run.
"""
@settings struct StartSettings
    "Assistant: the backend of the assistant, a local model, a model of Anthropic, an external agent, or none."
    assistant::Symbol = :ollama in APPLICATION_ASSISTANTS
    "Model: the model of the assistant; empty takes the default of its backend."
    model::String = ""
    "Context: the tokens of the conversation that the model may see; 0 leaves it to the backend."
    context::Int = 0 in 0:1024:1048576
    "MCP server: start the MCP server beside the window."
    mcp::Bool = false
    "Agent command: the command line that starts the external agent of the backend acp."
    agent_command::String = DEFAULT_AGENT_COMMAND
    "Agent session options: the JSON _meta that a new session of the external agent gets."
    agent_session_meta::String = DEFAULT_AGENT_SESSION_META
end

is_settings_group_read_at_start(::Type{StartSettings}) = true
