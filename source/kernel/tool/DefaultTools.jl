# Fragment of `ToolModule` — the tools and resources an editor ships with.

# What the model is told about the code it may write. It follows the declaration,
# because a description that names a surface the `ToolSet` does not have is an
# instruction to waste a round.
const _WHOLE_SURFACE_DESCRIPTION =
    "Execute arbitrary Julia code in the editor process. " *
    "The variable `editor` is bound to the running Editor instance " *
    "which holds `editor.document` and `editor.projection`.\n\n" *
    "Projectured is already imported with `using Projectured` before executing the code, " *
    "making all Projectured exports available. Do NOT add `using Projectured` to your code - " *
    "it is already included automatically.\n\n" *
    "The tool answers what your code prints, whole. The value of the last " *
    "expression is described in one line, and shown only when it is short. " *
    "Print what you want to read: println(x), show(x) or @show x.\n\n" *
    "MANDATORY — read these resources BEFORE writing any code:\n" *
    "1. resource://guides\n" *
    "2. resource://modules\n" *
    "3. resource://guide/getting-started\n" *
    "4. resource://guide/editor/reference\n" *
    "5. resource://guide/editor/selection\n\n" *
    "TO FIND A SPECIFIC API OR GUIDE — do this BEFORE writing code:\n" *
    "- Call the `search_api` tool to find the right module, struct, or function " *
    "(it ranks by name and docstring and returns how to read full docs).\n" *
    "- Call the `search_guides` tool to find the relevant guide section.\n" *
    "- When you know what you want to do but not what it is called, call either " *
    "search with mode \"description\" and say it in a sentence.\n" *
    "- Read full text with the `read_resource` tool, and a function's full docs " *
    "with the `read_function_documentation` tool.\n\n" *
    "NEVER guess names or signatures — search for them.\n" *
    "NEVER include code comments."

# The modules a `ToolSet` publishes as resources: the ones it declared, or every
# submodule of the project when it declared none.
_api_modules(set::ToolSet) =
    isempty(set.api) ? _submodules(_projectured()) :
                       [(nameof(e.module_), e.module_) for e in set.api]

# The types of one module a model may name. An empty declaration is the whole
# surface, where every type of the module is one.
function _api_types(set::ToolSet, mod::Module)
    all = _struct_types(mod)
    isempty(set.api) && return all
    for entry in set.api
        entry.module_ === mod || continue
        given = get_api_entry_names(entry)
        return [pair for pair in all if first(pair) in given]
    end
    empty(all)
end

# What a declaration can be said in one sentence. A module that gave every name
# it exports is named; a module that gave a few is not, because "the functions of
# DataFrames" would be false of eight of its eighty-six. The few are counted
# instead, and `search_api` is what finds them — a tool description is sent with
# every request, and a list of names does not belong in one.
function _declared_sentence(set::ToolSet)
    whole = [String(nameof(e.module_)) for e in set.api if e.names === nothing]
    chosen = sum(length(e.names) for e in set.api if e.names !== nothing; init = 0)
    isempty(whole) && return "The " * string(chosen) * " names this editor declares are "
    "The functions of " * join(whole, ", ") *
        (chosen == 0 ? "" : ", and " * string(chosen) * " more names, are ")
end

function _execute_julia_code_description(set::ToolSet)
    isempty(set.api) && return _WHOLE_SURFACE_DESCRIPTION
    "Execute Julia code in the editor process. " *
    "The variable `editor` is bound to the running editor.\n\n" *
    _declared_sentence(set) * "in scope, and they are the whole of what " *
    "you may call. Anything else is an UndefVarError.\n\n" *
    "FIND THEM BEFORE YOU WRITE ANY CODE, with the two tools that answer that:\n" *
    "- `search_api` lists them, with one line of description each. When you know " *
    "what you want to do but not its name, call it with mode \"description\" and " *
    "say it in a sentence.\n" *
    "- `read_function_documentation` reads one in full and says what its " *
    "arguments are.\n\n" *
    "The tool answers what your code prints, whole. The value of the last " *
    "expression is described in one line, and shown only when it is short. " *
    "Print what you want to read: println(x), show(x) or @show x.\n\n" *
    "NEVER guess a name — search for it. NEVER write comments."
end

# The two parameters both search tools share. A tool description is sent with
# every request, so the syntax is said here in four lines, and the guide says the
# rest.
const _QUERY_PARAMETER = (name = "query", type = "string",
    description = "What to look for. `mode` says how it is read.", required = true)

const _MODE_PARAMETER = (name = "mode", type = "string",
    description = "How `query` is read. \"keywords\" (the default): words that rank a " *
                  "hit; +word must match, -word must not, a|b is either, \"two words\" " *
                  "is a phrase; a guessed name is a good query, its words match the " *
                  "parts of the real name. \"regex\": a regular expression; a (?i) " *
                  "prefix ignores case. \"description\": a sentence that says what you " *
                  "want to do, when you do not know what it is called.",
    required = false)

const _DETAIL_PARAMETER = (name = "detail", type = "string",
    description = "How much a hit shows. \"names\": one line each, up to 25. " *
                  "\"summary\" (the default): the signature and one sentence, up to 8. " *
                  "\"full\": the whole text, up to 3.",
    required = false)

const _LIMIT_PARAMETER = (name = "limit", type = "number",
    description = "How many hits; the detail decides when absent.", required = false)

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
        _execute_julia_code_description(set),
        NamedTuple[
            (name = "code", type = "string",
             description = "Julia source code to evaluate", required = true),
        ],
        (target, args) -> execute_julia_code(set, target, args["code"]),
    ))

    register_tool!(set, Tool(
        "search_guides",
        "Learn how the parts fit together: search the guides, prose with worked " *
        "examples. A hit is one section, with the URI `read_resource` reads it by. " *
        "Use it when no single name does what was asked, or to see an example.",
        NamedTuple[
            _QUERY_PARAMETER,
            _MODE_PARAMETER,
            _DETAIL_PARAMETER,
            _LIMIT_PARAMETER,
        ],
        (target, args) -> search_guides(set, _get_query_argument(args);
                                        mode = get(args, "mode", nothing),
                                        detail = get(args, "detail", nothing),
                                        limit = _arg_limit(get(args, "limit", nothing))),
    ))

    register_tool!(set, Tool(
        "search_api",
        "Find the name to call: search the modules, types and functions you may " *
        "write, by name and docstring. A hit shows the signature and one sentence; " *
        "one clear hit shows its whole docstring. Use it before you write code, and " *
        "NEVER guess a name or a signature.",
        NamedTuple[
            _QUERY_PARAMETER,
            _MODE_PARAMETER,
            _DETAIL_PARAMETER,
            (name = "kind", type = "string",
             description = "Optional filter: \"module\", \"type\", or \"function\"", required = false),
            _LIMIT_PARAMETER,
        ],
        (target, args) -> search_api(set, _get_query_argument(args);
                                     mode   = get(args, "mode", nothing),
                                     detail = get(args, "detail", nothing),
                                     kind   = _arg_kind(get(args, "kind", nothing)),
                                     limit  = _arg_limit(get(args, "limit", nothing))),
    ))

    # A function's docstring is reachable *as a tool*, and it is the one piece of
    # documentation no other tool reaches. A module or a type has a resource:// URI,
    # so `read_resource` reads it; a function has none, and `search_api` answers a
    # `read_function_documentation(…)` call instead. That call is Julia, and a model
    # sent to it looked for a tool of that name, found none, and called
    # `execute_julia_code` with an empty body — then read the blank answer as a
    # broken tool and stopped writing code at all. Named here, the asymmetry is
    # gone: every hit `search_api` returns is one tool call away from its full text.
    register_tool!(set, Tool(
        "read_function_documentation",
        "Read the full documentation of a function. `search_api` names the module " *
        "and the function of every hit; this reads the whole docstring of one, " *
        "which says what its keywords do. Call it before you write a call you are " *
        "not sure of, and NEVER guess a signature.",
        NamedTuple[
            (name = "module_name", type = "string",
             description = "Module holding the function, as `search_api` printed it",
             required = true),
            (name = "function_name", type = "string",
             description = "Function to read, without its argument list", required = true),
            (name = "type_name", type = "string",
             description = "Optional type, when the function is documented per type",
             required = false),
        ],
        (target, args) -> read_function_documentation(
            get(args, "module_name", ""),
            get(args, "function_name", ""),
            get(args, "type_name", nothing);
            api = set.api),
    ))

    # The resource list is reachable *as a tool*, not only as a protocol concept:
    # an agent driving a ToolSet directly has no other way to see it, and MCP's own
    # resource list is just this rendered onto the wire.
    register_tool!(set, Tool(
        "list_resources",
        "The kinds of documentation resource, each with its count and how it is " *
        "addressed: the catalogues, the guides and their sections, the modules, the " *
        "types, and a function.",
        NamedTuple[],
        (target, args) -> describe_resources(set),
    ))

    register_tool!(set, Tool(
        "read_resource",
        "Read a documentation resource in full by its URI: a guide, one section of " *
        "a guide (resource://guide/<name>#<heading>), a module, a type, or a function " *
        "(resource://function/<module>/<name>). A search hit carries its URI.",
        NamedTuple[
            (name = "uri", type = "string",
             description = "Resource URI from `list_resources`", required = true),
        ],
        (target, args) -> read_resource(set, String(get(args, "uri", ""))),
    ))

    # **The guides are offered whatever the declaration says.** A declaration
    # narrows the NAMES a model may write, and a guide is prose about how to use
    # them — an application registers its own with `register_guide_root!`, and
    # that is the documentation a declared surface most wants.
    #
    # It was once the other way: guides only when nothing was declared. But
    # `search_guides` went on printing `resource://guide/…` for every hit,
    # and `read_resource` could not resolve one, so a model told to read a guide
    # spent a round on "Resource not found". Measured 2026-09-13.
    register_resource!(set, Resource(
        "resource://guides",
        "Documentation Guides",
        "List all available documentation with a one-paragraph description for each guide. " *
        "Documentation files are markdown files containing tips and tricks.",
        list_guides,
    ))
    for (guide_name, _) in _all_guides()
        let gd_name = guide_name
            register_resource!(set, Resource(
                "resource://guide/$gd_name",
                "Guide: $gd_name",
                "Full content of the $gd_name documentation guide.",
                () -> _add_guide_footer(gd_name, read_guide(gd_name)),
            ))
        end
    end

    let declared = set.api
        register_resource!(set, Resource(
            "resource://modules",
            "Modules",
            "List the modules you may call, with one-paragraph documentation for each " *
            "and a list of its types.",
            () -> list_modules(; api = declared),
        ))
    end

    for (mod_sym, mod) in _api_modules(set)
        let mn = String(mod_sym)
            register_resource!(set, Resource(
                "resource://module/$mn",
                "Module: $mn",
                "Full documentation for the $mn module.",
                () -> read_module_documentation(mn; api = set.api),
            ))
        end
        for (cls_sym, _) in _api_types(set, mod)
            let mn = String(mod_sym), cn = String(cls_sym)
                register_resource!(set, Resource(
                    "resource://type/$mn/$cn",
                    "Type: $mn.$cn",
                    "Full documentation for the $cn type in module $mn.",
                    () -> read_type_documentation(mn, cn; api = set.api),
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
