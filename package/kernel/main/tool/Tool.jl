# Fragment of `ToolModule` — the three types the capability surface is made of.

"""
    Tool(name, description, parameters, handler)

An action the editor can be asked to perform.

- `parameters` is a vector of `NamedTuple`s with fields `name::String`,
  `type::String` ("string", "number", …), `description::String`, `required::Bool`.
  They describe the arguments abstractly; rendering them into a provider's schema
  (Anthropic's `input_schema`, MCP's parameter list) is the *adapter's* job, so no
  wire format appears here.
- `handler(target, args::Dict) -> String` performs the work and returns a textual
  result. `args` keys are strings matching the parameter names; `target` is
  whatever the caller is acting on (the `Editor`, in practice) and is passed
  through untouched.
"""
struct Tool
    name::String
    description::String
    parameters::Vector{NamedTuple}
    handler::Function
end

"""
    Resource(uri, name, description, provider; mime_type = "text/markdown")

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

Resource(uri, name, description, provider; mime_type::AbstractString = "text/markdown") =
    Resource(String(uri), String(name), String(description), String(mime_type), provider)

"""
    ToolSet()

The tools and resources one editor exposes, plus the state its built-in tools
need to keep between calls.

Per editor, never process-global: `scratch` is the module
`execute_julia_code` evaluates into — so a top-level assignment in one call is
still bound in the next — and `last_value` is that call's actual return value,
which lets a caller embed a returned `Document` live instead of stringifying it.
Two editors in one process each get their own, so neither can see the other's
tools or evaluate into the other's namespace.
"""
mutable struct ToolSet
    tools::Vector{Tool}
    resources::Vector{Resource}
    scratch::Union{Module,Nothing}
    last_value::Any
    observers::Vector{Any}
end

ToolSet() = ToolSet(Tool[], Resource[], nothing, nothing, Any[])

"""
    observe_evaluations!(f, set) -> f

Be told what each `execute_julia_code` call produced. `f(value)` is called with
the value the code evaluated to — `nothing` when it errored or answered nothing.

A host registers one when a value MEANS something to it beyond being a result.
The simulator's editor uses it to give a simulation a reader made in a cell the
watch that keeps its picture still: the value is a live thing, and only the host
knows what living costs.

Every registration is called, in order, and a failure in one is reported and
does not stop the others or the evaluation. An observer is a side effect on a
result, never a step of producing it.
"""
observe_evaluations!(f, set::ToolSet) = (push!(set.observers, f); f)
