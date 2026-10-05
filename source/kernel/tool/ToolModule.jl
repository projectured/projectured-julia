"""
    ToolModule

The **capability surface**: what the editor can be asked to do, and what it can
be asked to read. Eight fragments share this namespace:

- [`Tool.jl`](Tool.jl) — `Tool` (an action), `Resource` (a read-only datum), the
  `ApiEntry` lines of the API that a set declares, the `MeaningModel` and the
  `RelevanceModel` a search by description ranks with, the `ToolSet` that holds
  them, and `observe_evaluations!`, which tells a host what each code call produced.
- [`ToolSet.jl`](ToolSet.jl) — registering, listing, finding, and calling them.
- [`CodeExecution.jl`](CodeExecution.jl) — `execute_julia_code!` and
  `execute_julia_expression!`, which run the code of the `execute_julia_code` tool,
  and their persistent scratch namespace.
- [`SearchQuery.jl`](SearchQuery.jl) — what a search query says: keywords with
  their classes, a regular expression, or a description.
- [`Documentation.jl`](Documentation.jl) — the guide / module / type / function
  documentation readers and the two search functions over them.
- [`DocstringSummary.jl`](DocstringSummary.jl) — `compute_docstring_summary`, the
  first paragraph of the docstring of a type, which the Help lists and the cards
  of the appearance and the settings tabs show.
- [`MeaningSearch.jl`](MeaningSearch.jl) — how a description is ranked by what it
  means, where the vectors of that rank are kept, and how a guide section's
  meaning rank joins the rank of its words.
- [`RelevanceSearch.jl`](RelevanceSearch.jl) — how a `RelevanceModel` ranks a
  description, its context and each thing a search could find, read together.
- [`DefaultTools.jl`](DefaultTools.jl) — `register_default_tools!`, which puts the
  above into a `ToolSet`.

A tool surface is **not** an AI concept. It is what an editor exposes, and it
holds no reference to a caller. Callers reach the same `ToolSet` from several
directions, and no caller depends on another: an in-process agent loop calls it
for a model, an out-of-process protocol server gives it to a client, and a person
calls the same functions from the REPL.

**One `ToolSet` per editor**. The tool list, the resource list, the declared API,
the code-execution scratch namespace, and its last result all live on the `ToolSet`
instance an `Editor` owns, so two editors in one process never share a tool
registry or evaluate into each other's namespace.

A few values of the layer are process-global, each for a reason:

- `_GUIDE_INDEX` and `_API_INDEX` hold the indexes of the guides and of the whole
  surface, and `_DECLARED_INDEX` holds one index for each declared API. Each is
  built on first use and kept, so it is the same for every editor that reads it.
  `_API_INDEX` does not see a package that loads after it is built, and
  `register_guide_root!` resets `_GUIDE_INDEX`.
- `_EXTRA_GUIDE_ROOTS` holds the guide roots that an application adds with
  `register_guide_root!` when it loads, for every window that it opens.
- `_MEANING_STORES` holds the stores of meaning vectors, one for each model. A
  vector comes from a text that does not change and from its model, so it is the
  same for every editor that names that model.
- `_MEANING_FOLDER` and `_MEANING_WAIT_SECONDS` say where the vector files go and
  how long a search waits for a build. A test sets them.
- A call of the code tool redirects the `stdout` and the `stderr` of the process
  while the code runs, so that the answer holds what the code printed.
"""
module ToolModule

using ..FaultModule

export Tool, Resource, ToolSet, ApiEntry, MeaningModel, set_meaning_model!,
       RelevanceModel, set_relevance_model!,
       get_api_entry_names,
       get_api_entry_bindings, get_api_source_name, describe_api, register_guide_root!,
       register_tool!, list_tools, find_tool, call_tool, declare_api!,
       register_resource!, list_resources, find_resource,
       read_resource, describe_resources,
       register_default_tools!,
       observe_evaluations!,
       execute_julia_code!, execute_julia_expression!, get_last_evaluated_value,
       get_last_evaluation_exception, get_evaluation_exception_count,
       describe_value_for_person,
       list_guides, read_guide, read_guide_section,
       list_modules, list_types, list_functions,
       read_module_documentation, read_type_documentation, read_function_documentation,
       read_value_documentation,
       search_guides, search_api,
       compute_docstring_summary, strip_code_marks,
       SearchTerm, KeywordQuery, parse_keyword_query, is_keyword_match

include("Tool.jl")
include("ToolSet.jl")
include("CodeExecution.jl")
include("SearchQuery.jl")
include("Documentation.jl")
include("DocstringSummary.jl")
include("MeaningSearch.jl")
include("RelevanceSearch.jl")
include("DefaultTools.jl")

end # module
