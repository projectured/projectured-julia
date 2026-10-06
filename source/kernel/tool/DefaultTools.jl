# Fragment of `ToolModule` — the tools and resources an editor ships with.

# What the tool answers, as both descriptions say it.
const _ANSWER_DESCRIPTION =
    "The tool answers what your code prints, whole, and then the value of the last " *
    "expression: a short value as it is, and a long one as the Julia REPL shows it, " *
    "trimmed with a note when it is still long. " *
    "Print what you want to read: println(x), show(x) or @show x.\n\n"

# How the model keeps what it found between calls, as both descriptions say it.
const _VARIABLES_DESCRIPTION =
    "Each call runs in the same module, so a variable that one call binds at the top " *
    "level is still there in every later call. Keep each object that you find or make " *
    "in its own variable, named by what it holds and numbered: `items_tab_1`, " *
    "`items_1`, `rows_1`. When you make another object of the same kind, give it the " *
    "next number, `rows_2`, and do not overwrite the first. Use a variable again in a " *
    "later call instead of finding its object again.\n\n"

# How the model changes the editor's document, as both descriptions say it. A direct
# write works, but the editor does not handle it as an edit, so the model is told
# before its first write and does not learn it from a failure. `ways` names only
# what the model can call: a description that names what it can not call wastes a
# round.
_make_editing_description(ways::AbstractString) =
    "Change the editor's document through " * ways * ", and not by a direct write " *
    "such as `part.value = new_value`. A direct write works, but the editor does not " *
    "handle it as an edit: Ctrl+Z can not undo it, and the editor does not check its " *
    "permissions or transform it, as it does for an operation.\n\n"

# The verbs that edit, as the description names them.
const _EDITING_VERBS = (:replace_referenced_value! => "`replace_referenced_value!(part, new_value)`",
                        :insert_elements! => "`insert_elements!(collection, index, values)`",
                        :delete_elements! => "`delete_elements!(collection, index)`")

_join_verbs(texts) = length(texts) == 1 ? only(texts) :
                     join(texts[1:(end - 1)], ", ") * " or " * texts[end]

function _make_editing_description(set::ToolSet)
    declared = Set(name for entry in set.api for name in get_api_entry_names(entry))
    texts = [text for (name, text) in _EDITING_VERBS if name in declared]
    _make_editing_description(isempty(texts) ? "a verb that changes it" :
                              "a verb, such as " * _join_verbs(texts))
end

# What the model is told about the code it may write. It follows the declaration,
# because a description that names a surface the `ToolSet` does not have is an
# instruction to waste a round.
const _WHOLE_SURFACE_DESCRIPTION =
    "Execute arbitrary Julia code in the editor process. " *
    "The variable `editor` is bound to the running Editor instance " *
    "which holds `editor.document` and `editor.projection`. A verb acts on this " *
    "editor, so the code does not pass it to the verb.\n\n" *
    "Every loaded Projectured package is already imported before executing the code, " *
    "making all its exports available, and `Projectured.X` names any of them. " *
    "Do NOT add `using Projectured` to your code - it is already included automatically.\n\n" *
    _ANSWER_DESCRIPTION *
    _VARIABLES_DESCRIPTION *
    _make_editing_description("a verb, such as " * _join_verbs([last(verb) for verb in _EDITING_VERBS]) *
                              ", or an operation that `evaluate_operation(editor, operation)` runs") *
    "MANDATORY — read these resources BEFORE writing any code:\n" *
    "1. resource://guides\n" *
    "2. resource://modules\n" *
    "3. resource://guide/guide/setup-guide\n" *
    "4. resource://guide/kernel/reference\n" *
    "5. resource://guide/kernel/selection\n\n" *
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
        (chosen == 0 ? " are " : ", and " * string(chosen) * " more names, are ")
end

function _execute_julia_code_description(set::ToolSet)
    isempty(set.api) && return _WHOLE_SURFACE_DESCRIPTION
    "Execute Julia code in the editor process. " *
    "The variable `editor` is bound to the running editor. A verb acts on this " *
    "editor, so the code does not pass it to the verb.\n\n" *
    _declared_sentence(set) * "in scope, and they are the whole of what " *
    "you may call. Anything else is an UndefVarError.\n\n" *
    "FIND THEM BEFORE YOU WRITE ANY CODE, with the two tools that answer that:\n" *
    "- `search_api` lists them, with one line of description each. When you know " *
    "what you want to do but not its name, call it with mode \"description\" and " *
    "say it in a sentence.\n" *
    "- `read_function_documentation` reads one in full and says what its " *
    "arguments are.\n\n" *
    _ANSWER_DESCRIPTION *
    _VARIABLES_DESCRIPTION *
    _make_editing_description(set) *
    "NEVER guess a name — search for it. NEVER write comments."
end

# The two parameters both search tools share. A tool description is sent with
# every request, so the syntax is said here in four lines, and the guide says the
# rest.
const _QUERY_PARAMETER = (name = "query", type = "string",
    description = "What to look for. `mode` says how it is read. It can be a sentence " *
                  "that says what this step needs; the search reads it whole.",
    required = true)

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

# What the documentation tools answer: a guide is a Markdown file, a docstring is
# Markdown, and a list of hits is written as Markdown around them.
const _DOCUMENTATION_MIME_TYPE = "text/markdown"

# ── The tools ───────────────────────────────────────────────────────────────

# The tool that runs Julia code in the scratch module of `set`. A call with no
# `code` argument gets the answer of `execute_julia_code!` for no code.
function _register_code_tool!(set::ToolSet)
    register_tool!(set, Tool(
        "execute_julia_code";
        description = _execute_julia_code_description(set),
        parameters = NamedTuple[
            (name = "code", type = "string",
             description = "Julia source code to evaluate", required = true),
        ],
        handler = (target, args) ->
            execute_julia_code!(set, target, get(args, "code", nothing)),
    ))
end

# The two searches: the sections of the guides, and the names a model may write.
function _register_search_tools!(set::ToolSet)
    register_tool!(set, Tool(
        "search_guides";
        description =
            "Learn how the parts fit together: search the guides, prose with worked " *
            "examples. A hit is one section, with the URI `read_resource` reads it by. " *
            "Use it when no single name does what was asked, or to see an example.",
        parameters = NamedTuple[
            _QUERY_PARAMETER,
            _MODE_PARAMETER,
            _DETAIL_PARAMETER,
            _LIMIT_PARAMETER,
        ],
        handler = (target, args) -> search_guides(set, _get_query_argument(args);
                                        mode = get(args, "mode", nothing),
                                        detail = get(args, "detail", nothing),
                                        limit = _arg_limit(get(args, "limit", nothing))),
        result_mime_type = _DOCUMENTATION_MIME_TYPE,
    ))

    register_tool!(set, Tool(
        "search_api";
        description =
            "Find the name to call: search the modules, types and functions you may " *
            "write, by name and docstring. A hit shows the signature and one sentence; " *
            "one clear hit shows its whole docstring. Use it before you write code, " *
            "and NEVER guess a name or a signature.",
        parameters = NamedTuple[
            _QUERY_PARAMETER,
            _MODE_PARAMETER,
            _DETAIL_PARAMETER,
            (name = "kind", type = "string",
             description = "Optional filter: \"module\", \"type\", or \"function\"",
             required = false),
            _LIMIT_PARAMETER,
        ],
        handler = (target, args) -> search_api(set, _get_query_argument(args);
                                     mode   = get(args, "mode", nothing),
                                     detail = get(args, "detail", nothing),
                                     kind   = _arg_kind(get(args, "kind", nothing)),
                                     limit  = _arg_limit(get(args, "limit", nothing))),
        result_mime_type = _DOCUMENTATION_MIME_TYPE,
    ))
end

# The tool that reads the whole docstring of one function.
function _register_function_documentation_tool!(set::ToolSet)
    # A function's docstring is reachable *as a tool*, and it is the one piece of
    # documentation no other tool reaches. A module or a type has a resource:// URI,
    # so `read_resource` reads it; a function has none, and `search_api` answers a
    # `read_function_documentation(…)` call instead. The tool has that name, so every
    # hit `search_api` returns is one tool call away from its full text.
    register_tool!(set, Tool(
        "read_function_documentation";
        description =
            "Read the full documentation of a function. `search_api` names the module " *
            "and the function of every hit; this reads the whole docstring of one, " *
            "which says what its keywords do. Call it before you write a call you are " *
            "not sure of, and NEVER guess a signature.",
        parameters = NamedTuple[
            (name = "module_name", type = "string",
             description = "Module holding the function, as `search_api` printed it",
             required = true),
            (name = "function_name", type = "string",
             description = "Function to read, without its argument list",
             required = true),
            (name = "type_name", type = "string",
             description = "Optional type, when the function is documented per type",
             required = false),
        ],
        handler = (target, args) -> read_function_documentation(
            get(args, "module_name", ""),
            get(args, "function_name", ""),
            get(args, "type_name", nothing);
            api = set.api),
        result_mime_type = _DOCUMENTATION_MIME_TYPE,
    ))
end

# The two tools of the resources: the kinds of resource, and one resource by its URI.
function _register_resource_tools!(set::ToolSet)
    # The resource list is reachable *as a tool*, not only as a protocol concept:
    # an agent driving a ToolSet directly has no other way to see it, and MCP's own
    # resource list is just this rendered onto the wire.
    register_tool!(set, Tool(
        "list_resources";
        description =
            "The kinds of documentation resource, each with its count and how it is " *
            "addressed: the catalogues, the guides and their sections, the modules, " *
            "the types, and a function.",
        parameters = NamedTuple[],
        handler = (target, args) -> describe_resources(set),
        result_mime_type = _DOCUMENTATION_MIME_TYPE,
    ))

    register_tool!(set, Tool(
        "read_resource";
        description =
            "Read a documentation resource in full by its URI: a guide, one section of " *
            "a guide (resource://guide/<name>#<heading>), a module, a type, or a " *
            "function (resource://function/<module>/<name>). A search hit carries " *
            "its URI.",
        parameters = NamedTuple[
            (name = "uri", type = "string",
             description = "Resource URI from `list_resources`", required = true),
        ],
        handler = (target, args) -> read_resource(set, String(get(args, "uri", ""))),
        result_mime_type = _DOCUMENTATION_MIME_TYPE,
    ))
end

# ── The resources ───────────────────────────────────────────────────────────

# The catalogue of the guides, and each guide.
function _register_guide_resources!(set::ToolSet)
    # **The guides are offered whatever the declaration says.** A declaration
    # narrows the NAMES a model may write, and a guide is prose about how to use
    # them — an application registers its own with `register_guide_root!`, and
    # that is the documentation a declared surface most wants. `search_guides`
    # prints `resource://guide/…` for every hit, so each of those must resolve.
    register_resource!(set, Resource("resource://guides", "Documentation Guides";
        description = "List all available documentation with a one-paragraph " *
                      "description for each guide. The guides are the markdown " *
                      "files of the documentation.",
        provider = list_guides))
    for (guide_name, _) in _all_guides()
        let gd_name = guide_name
            uri = "resource://guide/$gd_name"
            register_resource!(set, Resource(uri, "Guide: $gd_name";
                description = "Full content of the $gd_name documentation guide.",
                provider = () -> _add_guide_footer(gd_name, read_guide(gd_name))))
        end
    end
end

# The catalogue of the modules a model may call, and each of those modules with
# its types.
function _register_module_resources!(set::ToolSet)
    let declared = set.api
        register_resource!(set, Resource("resource://modules", "Modules";
            description = "List the modules you may call, with one-paragraph " *
                          "documentation for each and a list of its types.",
            provider = () -> list_modules(; api = declared)))
    end

    for (mod_sym, mod) in _api_modules(set.api)
        let mn = String(mod_sym)
            register_resource!(set, Resource("resource://module/$mn", "Module: $mn";
                description = "Full documentation for the $mn module.",
                provider = () -> read_module_documentation(mn; api = set.api)))
        end
        for (cls_sym, _) in _api_types(set.api, mod)
            let mn = String(mod_sym), cn = String(cls_sym)
                uri = "resource://type/$mn/$cn"
                register_resource!(set, Resource(uri, "Type: $mn.$cn";
                    description = "Full documentation for the $cn type in module $mn.",
                    provider = () -> read_type_documentation(mn, cn; api = set.api)))
            end
        end
        # Per-function resources are intentionally NOT registered: that fans out to
        # hundreds of entries and bloats the resource list. Functions are discovered
        # via the `search_api` tool and read on demand with
        # `read_function_documentation(module, name)`.
    end
end

"""
    register_default_tools!(set) -> set

Populate `set` with the editor's built-in tools — code execution, documentation
and API search, and the two that expose the resource list itself — plus the
read-only documentation resources (the guides, and each module/type's docs).

Idempotent: registering again replaces entries rather than duplicating them.

Every handler **closes over `set`**, which is how the code-execution tool reaches
its own scratch namespace and last value without a registry global and without a
context argument in the `(target, args)` handler signature that every tool has.
"""
function register_default_tools!(set::ToolSet)
    _register_code_tool!(set)
    _register_search_tools!(set)
    _register_function_documentation_tool!(set)
    _register_resource_tools!(set)
    _register_guide_resources!(set)
    _register_module_resources!(set)
    set
end
