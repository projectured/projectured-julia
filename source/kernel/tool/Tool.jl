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
    ToolSet(; api = Module[])

The tools and resources one editor exposes, plus the state its built-in tools
need to keep between calls.

Per editor, never process-global: `scratch` is the module
`execute_julia_code` evaluates into — so a top-level assignment in one call is
still bound in the next — and `last_value` is that call's actual return value,
which lets a caller embed a returned `Document` live instead of stringifying it.
Two editors in one process each get their own, so neither can see the other's
tools or evaluate into the other's namespace.

`api` is **the whole of what a model may write**: the modules whose exported names
`execute_julia_code` can resolve, and the modules the documentation tools search.
The two are one list on purpose — a model that finds a function it cannot call
wastes a round and learns to distrust the answer.

Empty, the default, means the editor's whole surface: every loaded `Projectured`
package, which is what the workbench and the MCP server want. A caller that names
modules gets those and nothing else.

Naming modules **opens** as much as it narrows. The default surface is gathered by
package name, so a module outside the `Projectured` packages is unreachable until
some `ToolSet` names it.

This is a focus mechanism and **not a security boundary**. `Base` and `Core` stay
in scope, as they do in every Julia module, and code that means to reach `Main`
can. What it buys is that a name outside the list fails in the round that used it,
with an error the model reads and corrects, instead of the model choosing among
thousands of names that mean nothing to the task.
"""
mutable struct ToolSet
    tools::Vector{Tool}
    resources::Vector{Resource}
    scratch::Union{Module,Nothing}
    last_value::Any
    observers::Vector{Any}
    api::Vector{Module}
end

ToolSet(; api::AbstractVector{Module} = Module[]) =
    ToolSet(Tool[], Resource[], nothing, nothing, Any[], collect(Module, api))

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
