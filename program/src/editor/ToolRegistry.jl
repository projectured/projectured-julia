"""
    ToolRegistryModule

Shared in-process registry of tools (actions) and resources (read-only data).
Both the MCP server and the internal WorkbenchAssistant call into this
registry directly, so handlers live in exactly one place.

A `Tool` is an action with a name, JSON-Schema-style parameters, and a
handler `(editor, args::Dict) -> String`. A `Resource` is a read-only piece
of data identified by a URI and produced lazily by a `provider` function.

Helpers are provided to bridge the registry to the MCP wire format
(`mcp_tools` / `mcp_resources`) and to the Anthropic Messages API
(`anthropic_tool_schema`).
"""
module ToolRegistryModule

using ModelContextProtocol
using ModelContextProtocol: TextResourceContents

export Tool, Resource,
       register_tool!, register_tools!, list_tools, call_tool, find_tool,
       register_resource!, register_resources!, list_resources, read_resource, find_resource,
       anthropic_tool_schema, mcp_tools, mcp_resources,
       clear_registry!

# ═══════════════════════════════════════════════════════════════════════
# Types
# ═══════════════════════════════════════════════════════════════════════

"""
    Tool(name, description, parameters, handler)

An action callable both by the MCP server and the internal assistant.

- `parameters` is a vector of `NamedTuple`s with fields
  `name::String`, `type::String` ("string", "number", …),
  `description::String`, `required::Bool`.
- `handler(editor, args::Dict) -> String` performs the work and returns
  a textual result; `args` keys are strings matching the parameter names.
"""
struct Tool
    name::String
    description::String
    parameters::Vector{NamedTuple}
    handler::Function
end

"""
    Resource(uri, name, description, mime_type, provider)

A read-only piece of data identified by `uri`. `provider()` returns the
resource body as `String`. `mime_type` defaults to `"text/markdown"`.
"""
struct Resource
    uri::String
    name::String
    description::String
    mime_type::String
    provider::Function
end

Resource(uri, name, description, provider; mime_type::AbstractString="text/markdown") =
    Resource(String(uri), String(name), String(description), String(mime_type), provider)

# ═══════════════════════════════════════════════════════════════════════
# Storage
# ═══════════════════════════════════════════════════════════════════════

const _TOOLS = Tool[]
const _RESOURCES = Resource[]

"""
    clear_registry!()

Empty the tool and resource registries. Intended for tests / reload.
"""
function clear_registry!()
    empty!(_TOOLS)
    empty!(_RESOURCES)
    nothing
end

# ═══════════════════════════════════════════════════════════════════════
# Tool registration
# ═══════════════════════════════════════════════════════════════════════

function register_tool!(t::Tool)
    # Replace by name if already present
    idx = findfirst(x -> x.name == t.name, _TOOLS)
    if idx === nothing
        push!(_TOOLS, t)
    else
        _TOOLS[idx] = t
    end
    t
end

register_tools!(ts) = (for t in ts; register_tool!(t); end; _TOOLS)

list_tools() = copy(_TOOLS)

find_tool(name::AbstractString) =
    findfirst(t -> t.name == name, _TOOLS) === nothing ? nothing : _TOOLS[findfirst(t -> t.name == name, _TOOLS)]

"""
    call_tool(name, args, editor) -> String

Invoke a registered tool. Raises `KeyError` if no tool with that name.
"""
function call_tool(name::AbstractString, args, editor)
    t = find_tool(name)
    t === nothing && throw(KeyError(name))
    t.handler(editor, args)
end

# ═══════════════════════════════════════════════════════════════════════
# Resource registration
# ═══════════════════════════════════════════════════════════════════════

function register_resource!(r::Resource)
    idx = findfirst(x -> x.uri == r.uri, _RESOURCES)
    if idx === nothing
        push!(_RESOURCES, r)
    else
        _RESOURCES[idx] = r
    end
    r
end

register_resources!(rs) = (for r in rs; register_resource!(r); end; _RESOURCES)

list_resources() = copy(_RESOURCES)

find_resource(uri::AbstractString) =
    findfirst(r -> r.uri == uri, _RESOURCES) === nothing ? nothing : _RESOURCES[findfirst(r -> r.uri == uri, _RESOURCES)]

"""
    read_resource(uri) -> String

Read a registered resource by URI. Returns an error message string if
the URI is not registered.
"""
function read_resource(uri::AbstractString)
    r = find_resource(uri)
    r === nothing && return "Resource '$uri' not found."
    r.provider()
end

# ═══════════════════════════════════════════════════════════════════════
# Anthropic Messages API bridge
# ═══════════════════════════════════════════════════════════════════════

"""
    anthropic_tool_schema(tools = list_tools()) -> Vector{Dict}

Render the given tools as the JSON-Schema-shaped vector expected by the
Anthropic Messages API `tools` parameter.
"""
function anthropic_tool_schema(tools::AbstractVector{Tool} = list_tools())
    out = Dict[]
    for t in tools
        properties = Dict{String,Any}()
        required = String[]
        for p in t.parameters
            properties[String(p.name)] = Dict(
                "type"        => String(p.type),
                "description" => String(p.description),
            )
            get(p, :required, false) && push!(required, String(p.name))
        end
        push!(out, Dict(
            "name"         => t.name,
            "description"  => t.description,
            "input_schema" => Dict(
                "type"       => "object",
                "properties" => properties,
                "required"   => required,
            ),
        ))
    end
    out
end

# ═══════════════════════════════════════════════════════════════════════
# MCP bridge
# ═══════════════════════════════════════════════════════════════════════

"""
    mcp_tools(editor, tools = list_tools()) -> Vector{MCPTool}

Render the given tools into the `MCPTool` shape expected by the MCP server,
binding each handler to `editor`.
"""
function mcp_tools(editor, tools::AbstractVector{Tool} = list_tools())
    out = MCPTool[]
    for t in tools
        params = ToolParameter[
            ToolParameter(
                name        = String(p.name),
                type        = String(p.type),
                description = String(p.description),
                required    = get(p, :required, false),
            ) for p in t.parameters
        ]
        # Capture t and editor in a closure
        let tool = t
            handler = params_dict -> begin
                args = Dict{String,Any}(string(k) => v for (k, v) in pairs(params_dict))
                TextContent(text = tool.handler(editor, args))
            end
            push!(out, MCPTool(
                name        = tool.name,
                description = tool.description,
                parameters  = params,
                handler     = handler,
            ))
        end
    end
    out
end

"""
    mcp_resources(resources = list_resources()) -> Vector{MCPResource}

Render the given resources as `MCPResource` objects whose data providers
return `TextResourceContents` containing the body.
"""
function mcp_resources(resources::AbstractVector{Resource} = list_resources())
    out = MCPResource[]
    for r in resources
        let res = r
            push!(out, MCPResource(
                uri           = res.uri,
                name          = res.name,
                description   = res.description,
                mime_type     = res.mime_type,
                data_provider = () -> TextResourceContents(
                    uri       = res.uri,
                    mime_type = res.mime_type,
                    text      = res.provider(),
                ),
            ))
        end
    end
    out
end

end # module
