# Fragment of `ToolModule` — the three types the capability surface is made of.

"""
    Tool(name; description, parameters, handler, result_mime_type = "text/plain")

An action the editor can be asked to perform. The name stands first; the other parts
take a name at the call, as the parts of a `Resource` do.

- `parameters` is a vector of `NamedTuple`s with fields `name::String`,
  `type::String` ("string", "number", …), `description::String`, `required::Bool`.
  They describe the arguments abstractly; rendering them into a provider's schema
  (Anthropic's `input_schema`, MCP's parameter list) is the *adapter's* job, so no
  wire format appears here.
- `handler(target, args::Dict) -> String` performs the work and returns a textual
  result. `args` keys are strings matching the parameter names; `target` is
  whatever the caller is acting on (the `Editor`, in practice) and is passed
  through untouched.
- `result_mime_type` is the media type of the text the handler returns, as a
  `Resource` names its own: `"text/markdown"` for a page of documentation. A
  front end that shows a result reads it to choose how to draw the text; the
  text itself is the same for every front end.
"""
struct Tool
    name::String
    description::String
    parameters::Vector{NamedTuple}
    handler::Function
    result_mime_type::String
end

Tool(name; description, parameters, handler,
     result_mime_type::AbstractString = "text/plain") =
    Tool(name, description, parameters, handler, result_mime_type)

"""
    Resource(uri, name; description, provider, mime_type = "text/markdown")

A read-only piece of data identified by `uri`. `provider()` returns the resource
body as a `String`, lazily — so registering a resource costs nothing until it is
read.
"""
struct Resource
    uri::String
    name::String
    description::String
    mime_type::String
    provider::Function
end

Resource(uri, name; description, provider, mime_type::AbstractString = "text/markdown") =
    Resource(String(uri), String(name), String(description), String(mime_type), provider)

"""
    ApiEntry(module, names)

One line of a declaration: a module, and which of its names a model may write.
`names` is `nothing` for every name the module exports, which is what a bare
module in a declaration means.

**A name here is not an export.** A module goes on exporting exactly what it
owns; this says which of those names *this* model is given, and a name listed
here arrives in the model's namespace unqualified. So a declaration can give a
name that no other module re-exports.

**A name can be given another name.** An entry of `:describe => :describe_table`
gives the `describe` of its module to the model as `describe_table`. Two packages
own the same common word often enough that the surface would otherwise have to
drop one of them. A rename is a declaration, not a wrapper —
`using M: describe as describe_table` is what the scratch module writes — so the
owning module is untouched and there is one function, not two.
"""
struct ApiEntry
    module_::Module
    names::Union{Nothing,Vector{Pair{Symbol,Symbol}}}
end

# A name given as itself, which is what most of them are.
_api_name(name::Symbol) = name => name
_api_name(pair::Pair) = Symbol(first(pair)) => Symbol(last(pair))
_api_name(other) = error("A declared name is a symbol or a `name => alias` pair, and " *
                         repr(other) * " is neither.")

ApiEntry(module_::Module, names) =
    ApiEntry(module_, names === nothing ? nothing :
                      Pair{Symbol,Symbol}[_api_name(one) for one in names])

# A declaration is a cache key — one search index per declared list — so two
# entries that say the same thing must be the same key.
Base.:(==)(a::ApiEntry, b::ApiEntry) = a.module_ === b.module_ && a.names == b.names
Base.hash(entry::ApiEntry, h::UInt) = hash(entry.names, hash(objectid(entry.module_), h))

"""
    get_api_entry_names(entry) -> Vector{Symbol}

The names one entry gives, whether it named them or took the module's exports.
"""
get_api_entry_names(entry::ApiEntry) =
    Symbol[last(pair) for pair in get_api_entry_bindings(entry)]

"""
    get_api_entry_bindings(entry) -> Vector{Pair{Symbol,Symbol}}

The name each binding has in its own module, and the name the model writes. They
differ only where a declaration renamed one.
"""
get_api_entry_bindings(entry::ApiEntry) =
    entry.names === nothing ?
        Pair{Symbol,Symbol}[n => n for n in names(entry.module_)
                            if n !== nameof(entry.module_) && isdefined(entry.module_, n)] :
        entry.names

# A declaration is written as modules and `module => names` pairs, and stored as
# entries. Every other reader sees one shape.
_api_entries(declaration) = ApiEntry[_api_entry(one) for one in declaration]

_api_entry(entry::ApiEntry) = entry
_api_entry(mod::Module) = ApiEntry(mod, nothing)
_api_entry(pair::Pair{Module}) = ApiEntry(first(pair), collect(last(pair)))
_api_entry(other) = error("A declared API is a module or a `module => names` pair, and " *
                          repr(other) * " is neither.")

"""
    get_api_source_name(api, module, name) -> Symbol

The name `module` knows a model-facing `name` by. They are the same word unless a
declaration renamed it, and a caller that looks a value up in the module needs
this one rather than the word the model wrote.
"""
function get_api_source_name(api, mod::Module, name::Symbol)
    for entry in api
        entry.module_ === mod || continue
        for (source, model) in get_api_entry_bindings(entry)
            model === name && return source
        end
    end
    name
end

"""
    MeaningModel(name, compute)

What turns a text into a **meaning vector**: a list of numbers that lies close to
the list of another text when the two texts mean nearly the same thing. A search
by description ranks what it finds by these vectors.

- `name` says which model computes them, as `"ollama/nomic-embed-text"`. The
  vectors of two models can not be compared, so the name keeps them apart, and it
  names the file they are kept in.
- `compute(texts, purpose)` answers a `Matrix{Float32}` with one column per text.
  `purpose` is `:query` for the text a search looks for, and `:document` for the
  texts it looks in.

A `ToolSet` holds one or none. `bind_meaning_model!` makes one from a language
model backend that has one, so the tool layer holds a function and never the
backend.
"""
struct MeaningModel
    name::String
    compute::Function
end

"""
    RelevanceModel(name, score, choose)

What reads a search and each thing it could find **together**, and says how
likely each thing is what the search wants: a classifier, where a
[`MeaningModel`](@ref) compares two vectors made apart.

- `name` says which model, as `"openrouter/typesafe/jev-1.13"`.
- `score(query, context, texts)` answers a `Vector{Float64}`, one probability per
  text that the thing it describes does what `query` asks, or a step of it.
  `context` is what the search is asked in, such as the request of the person,
  and it is empty when there is none.
- `choose(query, context, options)` answers a `Vector{Float64}`, one probability
  per option, which add up to one: which option holds what `query` asks. An
  option is an identifier and one short line; a call holds at most 255.

A `ToolSet` holds one or none; [`set_relevance_model!`](@ref) gives one. A
search by description ranks with it when it has one, and a model that throws
leaves the ranking to the meaning model.
"""
struct RelevanceModel
    name::String
    score::Function
    choose::Function
end

"""
    ToolSet(; api = ApiEntry[], meaning_model = nothing, relevance_model = nothing)

The tools and resources one editor exposes, plus the state its built-in tools
need to keep between calls.

Per editor, never process-global: `scratch` is the module
`execute_julia_code!` evaluates into — so a top-level assignment in one call is
still bound in the next — and `last_value` is that call's actual return value,
which lets a caller embed a returned `Document` live instead of stringifying it.
`last_exception` is the exception that the code of that call threw, or `nothing`:
the answer of the call is its message. `exception_count` is the number of calls
whose code threw. A caller that must tell a failed evaluation from an answered
one, such as the MCP log, compares that count before and after the call: two
exceptions can be equal, as two `ErrorException`s with one message are.
Two editors in one process each get their own, so neither can see the other's
tools or evaluate into the other's namespace.

`api` is **the whole of what a model may write**: the names
`execute_julia_code` can resolve, and the names the documentation tools search
and read. The two are one list on purpose — a model that finds a function it
cannot call wastes a round and learns to distrust the answer. Each line of it is
an [`ApiEntry`](@ref), and [`declare_api!`](@ref) is how one is written.

Empty, the default, means the editor's whole surface: every loaded `Projectured`
package, which is what the assistant and the MCP server want. The documentation
tools read that surface from an index that the process builds on first use, so a
package that loads after it is not in their answers. A caller that names modules
gets those and nothing else.

Naming modules **opens** as much as it narrows. The default surface is gathered by
package name, so a module outside the `Projectured` packages is unreachable until
some `ToolSet` names it.

This is a focus mechanism and **not a security boundary**. `Base` and `Core` stay
in scope, as they do in every Julia module, and code that means to reach `Main`
can. What it buys is that a name outside the list fails in the round that used it,
with an error the model reads and corrects, instead of the model choosing among
thousands of names that mean nothing to the task.

`meaning_model` is the [`MeaningModel`](@ref) a search by description ranks with,
or `nothing`, where such a search ranks by its words alone.
[`set_meaning_model!`](@ref) gives one.

`relevance_model` is the [`RelevanceModel`](@ref) that ranks a search by
description before the meaning model does, or `nothing`.
[`set_relevance_model!`](@ref) gives one.
"""
mutable struct ToolSet
    tools::Vector{Tool}
    resources::Vector{Resource}
    scratch::Union{Module,Nothing}
    last_value::Any
    last_exception::Any
    exception_count::Int
    observers::Vector{Any}
    # What a model may write, name by name. Each entry is a module and the names
    # of it a model may use, or `nothing` for every name it exports. An empty
    # `api` is the whole surface — see `declare_api!`.
    api::Vector{ApiEntry}
    meaning_model::Union{Nothing,MeaningModel}
    relevance_model::Union{Nothing,RelevanceModel}
end

ToolSet(; api = ApiEntry[], meaning_model::Union{Nothing,MeaningModel} = nothing,
        relevance_model::Union{Nothing,RelevanceModel} = nothing) =
    ToolSet(Tool[], Resource[], nothing, nothing, nothing, 0, Any[], _api_entries(api), meaning_model,
            relevance_model)

"""
    observe_evaluations!(f, set) -> f

Be told what each `execute_julia_code!` call produced. `f(value)` is called with
the value the code evaluated to — `nothing` when it errored or answered nothing.

A host registers one when a value MEANS something to it beyond being a result,
such as a value that goes on running and that the host must watch. The tool set
gives each value to every observer and does nothing else with it.

Every registration is called, in order, and a failure in one is reported and
does not stop the others or the evaluation. An observer is a side effect on a
result, never a step of producing it.
"""
observe_evaluations!(f, set::ToolSet) = (push!(set.observers, f); f)
