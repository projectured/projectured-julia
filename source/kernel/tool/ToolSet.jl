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
declare_api!(set, [AgentModule,
                   PaneModule => (:PaneSplit, :PaneGroup, :PaneTab),
                   ReferenceModule => (Symbol("@reference"),)])
```

A name a pair gives arrives unqualified, exactly as an exported one does, and no
module re-exports it — see [`ApiEntry`](@ref).

Call it before the first evaluation. The namespace the code runs in is built on
first use and then kept, so this drops it — a declaration that arrived after the
namespace was built would otherwise be a declaration that did nothing.

Declaring nothing restores the whole surface.

**A name its module does not have is refused**, and so is **a name two entries
both give**. The first fails when the namespace is built, and the second is an
ambiguity Julia reports only when the model writes the name — both far from the
line a person can fix. The declaration is that line.
"""
function declare_api!(set::ToolSet, declaration)
    entries = _api_entries(declaration)
    _refuse_missing_names(entries)
    _refuse_declared_twice(entries)
    set.api = entries
    # The namespace is built from the declaration, so a new declaration needs a
    # new namespace. What the model had assigned in it goes with it, which is
    # right: those bindings were made against names that may no longer resolve.
    set.scratch = nothing
    set
end

"""
    set_meaning_model!(set, model) -> set

Give `set` the [`MeaningModel`](@ref) its searches by description rank with,
and start computing the vectors of what those searches look in: the entries of
its API and the sections of the guides. `nothing` takes the model away, and such
a search then ranks by its words.
"""
function set_meaning_model!(set::ToolSet, model::Union{Nothing,MeaningModel})
    set.meaning_model = model
    _start_meaning_vectors!(set)
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

# A pair names what it wants, and a typo in one is a name nothing answers to.
# `using M: x` would fail on it when the namespace is built, which is a round the
# model spends on a fault the declaration already had.
function _refuse_missing_names(entries::Vector{ApiEntry})
    for entry in entries
        entry.names === nothing && continue
        # The name in the module, not the name the model writes: a renamed entry
        # is given as `describe => summarize_frame`, and it is `describe` that
        # has to be there.
        for (name, _) in entry.names
            isdefined(entry.module_, name) && continue
            error("The module " * String(nameof(entry.module_)) * " has no name " *
                  repr(name) * " to give.")
        end
    end
    entries
end

function _refuse_declared_twice(entries::Vector{ApiEntry})
    source = Dict{Symbol,Module}()
    # The name the MODEL writes is what can collide. Two modules may both own a
    # `describe`; only one of them may arrive under that word.
    for entry in entries, name in get_api_entry_names(entry)
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

Read a resource's body: a registered one by its URI, or one section of a guide
by `resource://guide/<name>#<heading>` and one function by
`resource://function/<module>/<name>`, which are read by the shape of the URI
and never listed. Returns an error *message* rather than throwing: a caller is
usually an LLM that guessed a URI, and a sentence it can read and retry from
beats an exception it cannot.
"""
function read_resource(set::ToolSet, uri::AbstractString)
    r = find_resource(set, uri)
    r === nothing || return r.provider()
    addressed = _read_addressed_resource(set, uri)
    addressed === nothing ? "Resource '$uri' not found." : addressed
end
