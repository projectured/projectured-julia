# Fragment of `ToolModule` — registering, listing, finding, and calling the
# contents of a `ToolSet`. Every function takes the set explicitly; there is no
# ambient registry to fall back on.

"""
    register_tool!(set, tool) -> tool

Add `tool` to `set`, replacing any tool already registered under the same name.
Idempotent, so a `register_default_tools!` on an editor that already has them
refreshes rather than duplicates.
"""
function register_tool!(set::ToolSet, t::Tool)
    i = findfirst(x -> x.name == t.name, set.tools)
    i === nothing ? push!(set.tools, t) : (set.tools[i] = t)
    t
end

register_tools!(set::ToolSet, ts) = (foreach(t -> register_tool!(set, t), ts); set.tools)

"""
    list_tools(set) -> Vector{Tool}
"""
list_tools(set::ToolSet) = copy(set.tools)

"""
    find_tool(set, name) -> Tool | nothing
"""
function find_tool(set::ToolSet, name::AbstractString)
    i = findfirst(t -> t.name == name, set.tools)
    i === nothing ? nothing : set.tools[i]
end

"""
    call_tool(set, name, args, target) -> String

Invoke a registered tool against `target`. Throws `KeyError` if `set` has no tool
of that name.
"""
function call_tool(set::ToolSet, name::AbstractString, args, target)
    t = find_tool(set, name)
    t === nothing && throw(KeyError(name))
    t.handler(target, args)
end

"""
    register_resource!(set, resource) -> resource

Add `resource` to `set`, replacing any resource already registered under the same
URI.
"""
function register_resource!(set::ToolSet, r::Resource)
    i = findfirst(x -> x.uri == r.uri, set.resources)
    i === nothing ? push!(set.resources, r) : (set.resources[i] = r)
    r
end

register_resources!(set::ToolSet, rs) =
    (foreach(r -> register_resource!(set, r), rs); set.resources)

"""
    list_resources(set) -> Vector{Resource}
"""
list_resources(set::ToolSet) = copy(set.resources)

"""
    find_resource(set, uri) -> Resource | nothing
"""
function find_resource(set::ToolSet, uri::AbstractString)
    i = findfirst(r -> r.uri == uri, set.resources)
    i === nothing ? nothing : set.resources[i]
end

"""
    read_resource(set, uri) -> String

Read a registered resource's body. Returns an error *message* rather than
throwing: a caller is usually an LLM that guessed a URI, and a sentence it can
read and retry from beats an exception it cannot.
"""
function read_resource(set::ToolSet, uri::AbstractString)
    r = find_resource(set, uri)
    r === nothing && return "Resource '$uri' not found."
    r.provider()
end
