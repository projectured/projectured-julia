# Fragment of `ToolModule` — registering, listing, finding, and calling the
# contents of a `ToolSet`. Every function takes the set explicitly; there is no
# ambient registry to fall back on.

"""
    declare_api!(set, declaration) -> set

Say what a model may write on this `ToolSet`: the names `execute_julia_code` can
resolve, and the names the documentation tools search and read.

An entry of `declaration` is a **module**, which gives every name it exports, or
a **`module => names` pair**, which gives those names and no others:

```julia
declare_api!(set, [PaneAgentModule,
                   PaneModule => (:PaneSplit, :PaneGroup, :PaneTab),
                   ReferenceModule => (Symbol("@reference"),)])
```

A name a pair gives arrives unqualified, exactly as an exported one does, and no
module re-exports it — see [`ApiEntry`](@ref).

Call it before the first evaluation. The namespace the code runs in is built on
first use and then kept, so this drops it — a declaration that arrived after the
namespace was built would otherwise be a declaration that did nothing.

Declaring nothing restores the whole surface.

**Two entries that give one name are refused.** `using A: x` beside `using B: x`
is an ambiguity Julia reports only when the model writes `x`, and the declaration
is where a person can fix it, so it is caught here with both sources named.
"""
function declare_api!(set::ToolSet, declaration)
    entries = _api_entries(declaration)
    _refuse_declared_twice(entries)
    set.api = entries
    # The namespace is built from the declaration, so a new declaration needs a
    # new namespace. What the model had assigned in it goes with it, which is
    # right: those bindings were made against names that may no longer resolve.
    set.scratch = nothing
    set
end

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

function _refuse_declared_twice(entries::Vector{ApiEntry})
    source = Dict{Symbol,Module}()
    for entry in entries, name in api_entry_names(entry)
        first_one = get(source, name, nothing)
        first_one === nothing && (source[name] = entry.module_; continue)
        error("Two modules give the name " * repr(name) * " to one model: " *
              String(nameof(first_one)) * " and " * String(nameof(entry.module_)) *
              ". Declare the name from one of them.")
    end
    entries
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
