"""
    ToolModule

The **capability surface**: what the editor can be asked to do, and what it can
be asked to read. Five fragments share this namespace:

- [`Tool.jl`](Tool.jl) — `Tool` (an action), `Resource` (a read-only datum), and
  the `ToolSet` that holds them.
- [`ToolSet.jl`](ToolSet.jl) — registering, listing, finding, and calling them.
- [`CodeExecution.jl`](CodeExecution.jl) — the `execute_julia_code` tool and its
  persistent scratch namespace.
- [`Documentation.jl`](Documentation.jl) — the guide / module / type / function
  documentation readers and the two search functions over them.
- [`DefaultTools.jl`](DefaultTools.jl) — `register_default_tools!`, which puts the
  above into a `ToolSet`.

A tool surface is **not** an AI concept. It is what an editor exposes; who calls
it is someone else's question. Three callers reach the same `ToolSet` from three
directions, and none of them knows about the others: the `agent` layer's loop
drives it locally on behalf of an LLM, the opt-in `ProjecturedMcp` package
exposes it over the Model Context Protocol, and a human calls the same functions
from the REPL.

**One `ToolSet` per editor** (AR-PER-EDITOR-STATE). Nothing here is
process-global: the tool list, the resource list, the code-execution scratch
namespace, and its last
result all live on the `ToolSet` instance an `Editor` owns, so two editors in one
process never share a tool registry or evaluate into each other's namespace.
"""
module ToolModule

export Tool, Resource, ToolSet,
       register_tool!, register_tools!, list_tools, find_tool, call_tool,
       register_resource!, register_resources!, list_resources, find_resource,
       read_resource,
       register_default_tools!,
       execute_julia_code, last_evaluated_value,
       list_guides, read_guide,
       list_modules, list_types, list_functions,
       read_module_documentation, read_type_documentation, read_function_documentation,
       search_documentation, search_api

include("Tool.jl")
include("ToolSet.jl")
include("CodeExecution.jl")
include("Documentation.jl")
include("DefaultTools.jl")

end # module
