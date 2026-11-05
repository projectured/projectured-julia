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

"""
    AssistantIndexSettings(; preset = :automatic, module_sentences = :preset,
                           function_names = :preset, function_sentences = :preset,
                           types = :preset)

How large the index of names is that the assistant gets with its text: a preset,
and each part of the index, which takes the value of the preset until a person
sets it. The automatic preset gives the compact index to a local model and the
full index to every other backend. [`describe_api`](@ref) says what each part
and each preset holds.
"""
@settings struct AssistantIndexSettings
    "Index: the preset of the index of names; automatic gives a local model the compact one and any other the full one."
    preset::Symbol = :automatic in (:automatic, :full, :compact)
    "Module sentences: a sentence for each module, after its name."
    module_sentences::Symbol = :preset in (:preset, :on, :off)
    "Function names: the names of the functions of each module."
    function_names::Symbol = :preset in (:preset, :on, :off)
    "Function sentences: a sentence for each function, after its name."
    function_sentences::Symbol = :preset in (:preset, :on, :off)
    "Types: the names of the types of each module, how many it has, or none."
    types::Symbol = :preset in (:preset, :names, :count, :none)
end

is_settings_group_read_at_start(::Type{AssistantIndexSettings}) = true

"""
    describe_api_index(api, backend; settings = AssistantIndexSettings()) -> String

The index of the names that `api` declares, as [`describe_api`](@ref) makes it,
with the parts that `settings` gives to an assistant of the backend `backend`,
such as `:ollama` or `:anthropic`.
"""
function describe_api_index(api, backend::Symbol; settings::AssistantIndexSettings = AssistantIndexSettings())
    preset = settings.preset === :automatic ? (backend === :ollama ? :compact : :full) : settings.preset
    describe_api(api; preset,
                 module_sentences = _get_index_switch(settings.module_sentences),
                 function_names = _get_index_switch(settings.function_names),
                 function_sentences = _get_index_switch(settings.function_sentences),
                 types = settings.types === :preset ? nothing : settings.types)
end

# A part that is on or off, or `nothing` for the value of the preset.
_get_index_switch(value::Symbol) = value === :preset ? nothing : value === :on
