# Fragment of `ToolModule` — the tools and resources an editor ships with.

"""
    register_default_tools!(set) -> set

Populate `set` with the editor's built-in tools — code execution, documentation
and API search, and the two that expose the resource list itself — plus the
read-only documentation resources (the guides, and each module/type's docs).

Idempotent: registering again replaces entries rather than duplicating them.

Every handler **closes over `set`**, which is how the code-execution tool reaches
its own scratch namespace and last value without a registry global
(PAR-PER-EDITOR-STATE) and without threading a context argument through the
`(target, args)` handler signature every other tool is happy with.
"""
function register_default_tools!(set::ToolSet)
    register_tool!(set, Tool(
        "execute_julia_code",
        "Execute arbitrary Julia code in the editor process. " *
        "The variable `editor` is bound to the running Editor instance " *
        "which holds `editor.document` and `editor.projection`.\n\n" *
        "Projectured is already imported with `using Projectured` before executing the code, " *
        "making all Projectured exports available. Do NOT add `using Projectured` to your code - " *
        "it is already included automatically.\n\n" *
        "Returns the repr of the last expression's value (if any), followed by any " *
        "captured stdout/stderr. There is no need to call print().\n\n" *
        "MANDATORY — read these resources BEFORE writing any code:\n" *
        "1. resource://guides\n" *
        "2. resource://modules\n" *
        "3. resource://guide/getting-started\n" *
        "4. resource://guide/editor/reference\n" *
        "5. resource://guide/editor/selection\n\n" *
        "TO FIND A SPECIFIC API OR GUIDE — do this BEFORE writing code:\n" *
        "- Call the `search_api` tool to find the right module, struct, or function " *
        "(it ranks by name and docstring and returns how to read full docs).\n" *
        "- Call the `search_documentation` tool to find the relevant guide section.\n" *
        "- Read full text with the `read_resource` tool; read a function's full docs with " *
        "read_function_documentation(\"Module\", \"name\") (callable directly here).\n\n" *
        "NEVER guess names or signatures — search for them.\n" *
        "NEVER call print(). NEVER include code comments.",
        NamedTuple[
            (name = "code", type = "string",
             description = "Julia source code to evaluate", required = true),
        ],
        (target, args) -> execute_julia_code(set, target, args["code"]),
    ))

    register_tool!(set, Tool(
        "search_documentation",
        "Search the ProjecturEd guide documentation by keyword. Returns ranked guide " *
        "sections with their resource:// URIs and a short excerpt. Read the full text " *
        "with the `read_resource` tool. Call this to locate the relevant guide section " *
        "BEFORE reading whole guides.",
        NamedTuple[
            (name = "query", type = "string",
             description = "Keywords by default (case-insensitive substring match against guide " *
                           "headings and body; more matching terms rank higher). With regex=true " *
                           "it is a regular expression instead (use a (?i) prefix for " *
                           "case-insensitivity).", required = true),
            (name = "regex", type = "boolean",
             description = "Treat `query` as a regular expression instead of keywords (default false)",
             required = false),
            (name = "limit", type = "number",
             description = "Maximum number of results (default 8)", required = false),
        ],
        (target, args) -> begin
            q = try
                _query_arg(args)
            catch e
                return "Invalid regex: $(sprint(showerror, e))"
            end
            search_documentation(q; limit = _arg_int(get(args, "limit", 8), 8))
        end,
    ))

    register_tool!(set, Tool(
        "search_api",
        "Search ProjecturEd modules, structs (types), and functions by name and " *
        "docstring. Returns ranked hits with a one-line doc and how to read the full " *
        "docs: a resource:// URI for modules/types, or a read_function_documentation(…) " *
        "call for functions. Use this to find the right type or function and NEVER guess " *
        "names or signatures.",
        NamedTuple[
            (name = "query", type = "string",
             description = "Keywords by default (case-insensitive substring match against names " *
                           "and docstrings; exact name matches rank highest). With regex=true it " *
                           "is a regular expression instead (use a (?i) prefix for " *
                           "case-insensitivity).", required = true),
            (name = "regex", type = "boolean",
             description = "Treat `query` as a regular expression instead of keywords (default false)",
             required = false),
            (name = "kind", type = "string",
             description = "Optional filter: \"module\", \"type\", or \"function\"", required = false),
            (name = "limit", type = "number",
             description = "Maximum number of results (default 8)", required = false),
        ],
        (target, args) -> begin
            q = try
                _query_arg(args)
            catch e
                return "Invalid regex: $(sprint(showerror, e))"
            end
            search_api(q;
                       kind  = _arg_kind(get(args, "kind", nothing)),
                       limit = _arg_int(get(args, "limit", 8), 8))
        end,
    ))

    # The resource list is reachable *as a tool*, not only as a protocol concept:
    # an agent driving a ToolSet directly has no other way to see it, and MCP's own
    # resource list is just this rendered onto the wire.
    register_tool!(set, Tool(
        "list_resources",
        "List every read-only documentation resource registered in the editor. " *
        "Returns a markdown bullet list of URIs and their one-line descriptions.",
        NamedTuple[],
        (target, args) -> begin
            io = IOBuffer()
            println(io, "# Resources")
            for r in list_resources(set)
                println(io, "- `", r.uri, "` — ", r.description)
            end
            String(take!(io))
        end,
    ))

    register_tool!(set, Tool(
        "read_resource",
        "Read the full body of a documentation resource by URI " *
        "(URIs come from `list_resources`).",
        NamedTuple[
            (name = "uri", type = "string",
             description = "Resource URI from `list_resources`", required = true),
        ],
        (target, args) -> read_resource(set, String(get(args, "uri", ""))),
    ))

    register_resource!(set, Resource(
        "resource://guides",
        "Documentation Guides",
        "List all available documentation with a one-paragraph description for each guide. " *
        "Documentation files are markdown files containing tips and tricks for using ProjecturEd.",
        list_guides,
    ))
    register_resource!(set, Resource(
        "resource://modules",
        "ProjecturEd Modules",
        "List all modules in the ProjecturEd codebase with one-paragraph documentation " *
        "for each module and a list of top-level types (structs).",
        list_modules,
    ))

    for (guide_name, _) in _all_guides()
        let gd_name = guide_name
            register_resource!(set, Resource(
                "resource://guide/$gd_name",
                "Guide: $gd_name",
                "Full content of the $gd_name documentation guide.",
                () -> read_guide(gd_name),
            ))
        end
    end

    for (mod_sym, mod) in _submodules(_projectured())
        let mn = String(mod_sym)
            register_resource!(set, Resource(
                "resource://module/$mn",
                "Module: $mn",
                "Full documentation for the $mn module.",
                () -> read_module_documentation(mn),
            ))
        end
        for (cls_sym, _) in _struct_types(mod)
            let mn = String(mod_sym), cn = String(cls_sym)
                register_resource!(set, Resource(
                    "resource://type/$mn/$cn",
                    "Type: $mn.$cn",
                    "Full documentation for the $cn type in module $mn.",
                    () -> read_type_documentation(mn, cn),
                ))
            end
        end
        # Per-function resources are intentionally NOT registered: that fans out to
        # hundreds of entries and bloats the resource list. Functions are discovered
        # via the `search_api` tool and read on demand with
        # `read_function_documentation(module, name)`.
    end
    set
end
