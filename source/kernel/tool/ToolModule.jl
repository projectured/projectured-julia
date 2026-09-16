"""
    ToolModule

The **capability surface**: what the editor can be asked to do, and what it can
be asked to read. Seven fragments share this namespace:

- [`Tool.jl`](Tool.jl) — `Tool` (an action), `Resource` (a read-only datum), the
  `MeaningModel` a search by description ranks with, and the `ToolSet` that holds
  them.
- [`ToolSet.jl`](ToolSet.jl) — registering, listing, finding, and calling them.
- [`CodeExecution.jl`](CodeExecution.jl) — the `execute_julia_code` tool and its
  persistent scratch namespace.
- [`SearchQuery.jl`](SearchQuery.jl) — what a search query says: keywords with
  their classes, a regular expression, or a description.
- [`Documentation.jl`](Documentation.jl) — the guide / module / type / function
  documentation readers and the two search functions over them.
- [`MeaningSearch.jl`](MeaningSearch.jl) — how a description is ranked by what it
  means, and how that rank joins the rank of its words.
- [`DefaultTools.jl`](DefaultTools.jl) — `register_default_tools!`, which puts the
  above into a `ToolSet`.

A tool surface is **not** an AI concept. It is what an editor exposes; who calls
it is someone else's question. Callers reach the same `ToolSet` from several
directions, and none of them knows about the others: an in-process agent loop
drives it on behalf of a model, an out-of-process protocol server exposes it to
the outside, and a human calls the same functions from the REPL.

**One `ToolSet` per editor**. Nothing here is
process-global: the tool list, the resource list, the code-execution scratch
namespace, and its last
result all live on the `ToolSet` instance an `Editor` owns, so two editors in one
process never share a tool registry or evaluate into each other's namespace.
"""
module ToolModule

export Tool, Resource, ToolSet, ApiEntry, MeaningModel, set_meaning_model!,
       get_api_modules, get_api_entry_names,
       api_entry_bindings, api_source_name, describe_api, register_guide_root!,
       register_tool!, register_tools!, list_tools, find_tool, call_tool, declare_api!,
       register_resource!, register_resources!, list_resources, find_resource,
       read_resource,
       register_default_tools!,
       observe_evaluations!,
       execute_julia_code, get_last_evaluated_value,
       list_guides, read_guide,
       list_modules, list_types, list_functions,
       read_module_documentation, read_type_documentation, read_function_documentation,
       search_documentation, search_api,
       SearchTerm, KeywordQuery, parse_keyword_query, is_keyword_match

include("Tool.jl")
include("ToolSet.jl")
include("CodeExecution.jl")
include("SearchQuery.jl")
include("Documentation.jl")
include("MeaningSearch.jl")
include("DefaultTools.jl")

end # module
