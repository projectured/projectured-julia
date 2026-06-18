"""
    McpModule

MCP (Model Context Protocol) server. Uses ModelContextProtocol.jl to speak
JSON-RPC 2.0 over HTTP+SSE so an AI assistant can inspect and manipulate the
editor's document and projection at runtime.

This module provides the server skeleton bound to the editor and registers
tools for AI-driven manipulation.
"""
module McpModule

using ModelContextProtocol
using ModelContextProtocol: HttpTransport, TextResourceContents, ServerConfig
import ..ToolRegistryModule: Tool, Resource,
                              register_tool!, register_resource!,
                              list_tools, list_resources,
                              mcp_tools, mcp_resources
import ..WorkbenchModule: DEFAULT_ASSISTANT_SYSTEM

export McpServer, mcp_start!, mcp_stop!,
       execute_julia_code, list_guides, read_guide,
       list_modules, list_classes, list_functions,
       read_module_documentation, read_class_documentation, read_function_documentation,
       search_documentation, search_api,
       register_default_tools_and_resources!

# ═══════════════════════════════════════════════════════════════════════
# MCP server
# ═══════════════════════════════════════════════════════════════════════

"""
    McpServer(editor)

An MCP server bound to an editor.  Call [`mcp_start!`](@ref) to begin
processing in the background and [`mcp_stop!`](@ref) to shut it down.
"""
mutable struct McpServer
    editor::Any
    server::Server
    task::Union{Task,Nothing}
end

function McpServer(editor)
    srv = mcp_server(
        name        = "projectured",
        version     = "0.1.0",
        description = "MCP server for ProjecturEd — a projectional editor built in Julia.",
        resources   = _make_resources(),
    )
    # `mcp_server` does not expose `instructions`, but `ServerConfig` does —
    # and that's the field the MCP `initialize` handler delivers to clients,
    # so the in-editor assistant and any external MCP client share the same
    # prompt.
    srv.config = ServerConfig(
        name         = srv.config.name,
        version      = srv.config.version,
        description  = srv.config.description,
        capabilities = srv.config.capabilities,
        instructions = DEFAULT_ASSISTANT_SYSTEM,
        title        = srv.config.title,
        icons        = srv.config.icons,
    )
    McpServer(editor, srv, nothing)
end

"""
    mcp_start!(mcp::McpServer) -> McpServer

Launch the MCP server as an async task (HTTP transport on port 9876).
"""
function mcp_start!(mcp::McpServer)
    for tool in _make_tools(mcp.editor)
        register!(mcp.server, tool)
    end
    transport = HttpTransport(
        host     = "127.0.0.1",
        port     = 9876,
        endpoint = "/mcp",
    )
    mcp.server.transport = transport
    try
        ModelContextProtocol.connect(transport)
        mcp.task = @async start!(mcp.server)
    catch e
        @warn "MCP server failed to start" exception = e
    end
    mcp
end

# ═══════════════════════════════════════════════════════════════════════
# Tool handlers (can be called directly from REPL)
# ═══════════════════════════════════════════════════════════════════════

"""
    execute_julia_code(editor, code) -> String

Evaluate `code` in the editor process with `editor` bound and `using Projectured`
pre-loaded. Returns repr of last value plus captured stdout/stderr.
"""
function execute_julia_code(editor, code)
    try
        # Prepend 'using Projectured' to make Projectured exports available
        code_with_using = "using Projectured\n" * code
        # Use parseall for multi-line code support
        expr = Meta.parseall(code_with_using)
        # Use Pipe for redirect_stdio
        stdout_pipe = Pipe()
        stderr_pipe = Pipe()

        redirect_stdio(stdout=stdout_pipe, stderr=stderr_pipe) do
            # Evaluate with editor bound in a let block
            # Handle :toplevel expression from Meta.parseall
            local result
            if expr isa Expr && expr.head == :toplevel
                # Extract the actual expressions (skip line info nodes)
                actual_exprs = filter(e -> !(e isa LineNumberNode), expr.args)
                if length(actual_exprs) == 1
                    # Single expression - evaluate directly with editor bound
                    result = Core.eval(@__MODULE__, :(let editor = $(QuoteNode(editor))
                        $(actual_exprs[1])
                    end))
                else
                    # Multiple expressions - wrap in a begin block
                    result = Core.eval(@__MODULE__, :(let editor = $(QuoteNode(editor))
                        begin
                            $(actual_exprs...)
                        end
                    end))
                end
            else
                # Non-toplevel expression (shouldn't happen with parseall, but handle anyway)
                result = Core.eval(@__MODULE__, :(let editor = $(QuoteNode(editor))
                    $expr
                end))
            end

            # Append the repr of the result if it's not nothing
            if result !== nothing
                println(repr(result))
            end
        end

        close(stdout_pipe.in)
        close(stderr_pipe.in)

        stdout_output = String(read(stdout_pipe.out))
        stderr_output = String(read(stderr_pipe.out))

        close(stdout_pipe.out)
        close(stderr_pipe.out)

        stdout_output * stderr_output
    catch e
        sprint(showerror, e, catch_backtrace())
    end
end

"""
    list_guides() -> String

List all available documentation with a one-paragraph description for each guide.
Documentation files are markdown files containing tips and tricks for using ProjecturEd.
"""
function list_guides()
    doc_dir = joinpath(@__DIR__, "../../../guide")
    if !isdir(doc_dir)
        return "No guide directory found."
    end

    guides_info = String[]
    for (root, dirs, files) in walkdir(doc_dir)
        for file in sort(files)
            endswith(file, ".md") || continue
            filepath = joinpath(root, file)
            content = read(filepath, String)
            # Extract first paragraph after title
            lines = split(content, '\n')
            description_lines = String[]
            in_description = false
            seen_heading = false
            for line in lines
                stripped = strip(line)
                if isempty(stripped)
                    if in_description
                        break
                    end
                    continue
                elseif startswith(stripped, "#")
                    seen_heading = true
                elseif seen_heading && !startswith(stripped, "#")
                    in_description = true
                    push!(description_lines, stripped)
                end
            end
            description = join(description_lines, " ")
            relpath = replace(filepath, doc_dir * "/" => "")
            guide_name = replace(relpath, ".md" => "")
            push!(guides_info, "**$guide_name**: $description")
        end
    end

    if isempty(guides_info)
        return "No documentation found."
    end
    "# Available Guides\n\n" * join(guides_info, "\n\n")
end

"""
    read_guide(guide_name) -> String

Read the full content of a specific documentation file by name.
"""
function read_guide(guide_name)
    doc_dir = joinpath(@__DIR__, "../../../guide")
    filepath = joinpath(doc_dir, guide_name * ".md")

    if !isfile(filepath)
        return "Documentation '$guide_name' not found."
    end

    try
        content = read(filepath, String)
        content
    catch e
        "Error reading documentation '$guide_name': $(e)"
    end
end

"""
    list_modules() -> String

List all modules in the ProjecturEd codebase with one-paragraph documentation
for each module and a list of top-level classes (structs).
"""
function list_modules()
    proj = _projectured()
    modules_info = String[]
    for (name, mod) in _submodules(proj)
        doc = _doc_string(mod)
        summary = isempty(doc) ? "No documentation available." : _first_paragraph(doc)
        structs = [String(n) for (n, _) in _struct_types(mod)]
        struct_list = isempty(structs) ? "" : "\n\nClasses: $(join(structs, ", "))"
        push!(modules_info, "**$name**: $summary$struct_list")
    end
    isempty(modules_info) && return "No modules found."
    "Available Modules\n\n" * join(modules_info, "\n\n---\n\n")
end

"""
    list_classes(module_name) -> String

List all classes (structs) within a specific module with their one-paragraph documentation.
"""
function list_classes(module_name)
    mod = _find_module(module_name)
    isnothing(mod) && return "Module '$module_name' not found."
    classes_info = String[]
    for (name, T) in _struct_types(mod)
        doc = _doc_string(T)
        summary = isempty(doc) ? "No documentation available." : _first_paragraph(doc)
        mutable_str = ismutabletype(T) ? "mutable " : ""
        push!(classes_info, "**$mutable_str$name**: $summary")
    end
    isempty(classes_info) && return "No classes found in module '$module_name'."
    join(classes_info, "\n\n")
end

"""
    list_functions(module_name, class_name=nothing) -> String

List all functions within a specific module or class with their signatures and one-paragraph documentation.
"""
function list_functions(module_name, class_name=nothing)
    mod = _find_module(module_name)
    isnothing(mod) && return "Module '$module_name' not found."
    functions_info = String[]
    for (name, fn) in _module_functions(mod)
        if class_name !== nothing && !any(occursin(class_name, string(m.sig)) for m in methods(fn))
            continue
        end
        doc = _doc_string(fn)
        summary = isempty(doc) ? "No documentation available." : _first_paragraph(doc)
        push!(functions_info, "**$name**: $summary")
    end
    isempty(functions_info) && return "No functions found in module '$module_name'."
    join(functions_info, "\n\n")
end

"""
    read_module_documentation(module_name) -> String

Read the full documentation for a specific module.
"""
function read_module_documentation(module_name)
    mod = _find_module(module_name)
    isnothing(mod) && return "Module '$module_name' not found."
    doc = _doc_string(mod)
    isempty(doc) && return "Module $module_name — no documentation available."
    doc
end

"""
    read_class_documentation(module_name, class_name) -> String

Read the full documentation for a specific class within a module.
"""
function read_class_documentation(module_name, class_name)
    mod = _find_module(module_name)
    isnothing(mod) && return "Module '$module_name' not found."
    sym = Symbol(class_name)
    (isdefined(mod, sym) && getfield(mod, sym) isa Type) || return "Class '$class_name' not found in module '$module_name'."
    T = getfield(mod, sym)
    doc = _doc_string(T)
    if isempty(doc)
        fields = fieldnames(T)
        isempty(fields) && return "$class_name — no documentation available."
        field_info = join(["- `$(f)::$(fieldtype(T, f))`" for f in fields], "\n")
        return "# $class_name\n\n## Fields\n$field_info"
    end
    doc
end

"""
    read_function_documentation(module_name, function_signature, class_name=nothing) -> String

Read the full documentation for a specific function within a module or class.
"""
function read_function_documentation(module_name, function_signature, class_name=nothing)
    mod = _find_module(module_name)
    isnothing(mod) && return "Module '$module_name' not found."
    func_name = replace(function_signature, r"\(.*" => "")
    sym = Symbol(func_name)
    isdefined(mod, sym) || return "Function '$function_signature' not found in module '$module_name'."
    fn = getfield(mod, sym)
    doc = _doc_string(fn)
    isempty(doc) && return "No documentation available for '$function_signature'."
    doc
end

# ═══════════════════════════════════════════════════════════════════════
# Tool and resource registration
# ═══════════════════════════════════════════════════════════════════════

"""
    register_default_tools_and_resources!()

Populate the shared `ToolRegistry` with the editor's built-in tool
(`execute_julia_code`) and the read-only documentation resources
(guides, module/class/function docs). Idempotent — repeated calls
replace entries rather than duplicating them.
"""
function register_default_tools_and_resources!()
    register_tool!(Tool(
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
        "- Read full text with read_resource(uri); read a function's full docs with " *
        "read_function_documentation(\"Module\", \"name\") (callable directly here).\n\n" *
        "NEVER guess names or signatures — search for them.\n" *
        "NEVER call print(). NEVER include code comments.",
        NamedTuple[
            (name="code", type="string",
             description="Julia source code to evaluate", required=true),
        ],
        (editor, args) -> execute_julia_code(editor, args["code"]),
    ))

    register_tool!(Tool(
        "search_documentation",
        "Search the ProjecturEd guide documentation by keyword. Returns ranked guide " *
        "sections with their resource:// URIs and a short excerpt. Read the full text " *
        "with read_resource(uri). Call this to locate the relevant guide section BEFORE " *
        "reading whole guides.",
        NamedTuple[
            (name="query", type="string",
             description="Search terms (matched against guide headings and body)", required=true),
            (name="limit", type="number",
             description="Maximum number of results (default 8)", required=false),
        ],
        (editor, args) -> search_documentation(
            String(args["query"]); limit=_arg_int(get(args, "limit", 8), 8)),
    ))

    register_tool!(Tool(
        "search_api",
        "Search ProjecturEd modules, structs (classes), and functions by name and " *
        "docstring. Returns ranked hits with a one-line doc and how to read the full " *
        "docs: a resource:// URI for modules/classes, or a read_function_documentation(…) " *
        "call for functions. Use this to find the right type or function and NEVER guess " *
        "names or signatures.",
        NamedTuple[
            (name="query", type="string",
             description="Search terms (matched against names and docstrings)", required=true),
            (name="kind", type="string",
             description="Optional filter: \"module\", \"class\", or \"function\"", required=false),
            (name="limit", type="number",
             description="Maximum number of results (default 8)", required=false),
        ],
        (editor, args) -> search_api(
            String(args["query"]);
            kind=_arg_kind(get(args, "kind", nothing)),
            limit=_arg_int(get(args, "limit", 8), 8)),
    ))

    register_resource!(Resource(
        "resource://guides",
        "Documentation Guides",
        "List all available documentation with a one-paragraph description for each guide. " *
        "Documentation files are markdown files containing tips and tricks for using ProjecturEd.",
        list_guides,
    ))
    register_resource!(Resource(
        "resource://modules",
        "ProjecturEd Modules",
        "List all modules in the ProjecturEd codebase with one-paragraph documentation " *
        "for each module and a list of top-level classes (structs).",
        list_modules,
    ))

    doc_dir = joinpath(@__DIR__, "../../../guide")
    if isdir(doc_dir)
        for (root, dirs, files) in walkdir(doc_dir)
            for file in sort(files)
                endswith(file, ".md") || continue
                filepath = joinpath(root, file)
                relpath = replace(filepath, doc_dir * "/" => "")
                guide_name = replace(relpath, ".md" => "")
                let gd_name = guide_name
                    register_resource!(Resource(
                        "resource://guide/$gd_name",
                        "Guide: $gd_name",
                        "Full content of the $gd_name documentation guide.",
                        () -> read_guide(gd_name),
                    ))
                end
            end
        end
    end

    proj = _projectured()
    for (mod_sym, mod) in _submodules(proj)
        let mn = String(mod_sym)
            register_resource!(Resource(
                "resource://module/$mn",
                "Module: $mn",
                "Full documentation for the $mn module.",
                () -> read_module_documentation(mn),
            ))
        end
        for (cls_sym, _) in _struct_types(mod)
            let mn = String(mod_sym), cn = String(cls_sym)
                register_resource!(Resource(
                    "resource://class/$mn/$cn",
                    "Class: $mn.$cn",
                    "Full documentation for the $cn class in module $mn.",
                    () -> read_class_documentation(mn, cn),
                ))
            end
        end
        # Per-function resources are intentionally NOT registered: that fans out
        # to hundreds of entries and bloats the resource list. Functions are
        # discovered via the `search_api` tool and read on demand with
        # `read_function_documentation(module, name)`.
    end
    nothing
end

function _make_tools(editor)
    register_default_tools_and_resources!()
    mcp_tools(editor, list_tools())
end

function _make_resources()
    register_default_tools_and_resources!()
    mcp_resources(list_resources())
end

# ═══════════════════════════════════════════════════════════════════════
# Reflection helpers
# ═══════════════════════════════════════════════════════════════════════

_projectured() = parentmodule(@__MODULE__)

function _find_module(name::String)
    proj = _projectured()
    name == string(nameof(proj)) && return proj
    sym = Symbol(name)
    isdefined(proj, sym) || return nothing
    obj = getfield(proj, sym)
    obj isa Module ? obj : nothing
end

# Render a doc object (as returned by `Base.Docs._doc`) to plain markdown source.
# On Julia 1.12 `_doc` yields a raw `DocStr`/`MultiDoc`, not a `Markdown.MD`.
function _render_doc(md)
    md === nothing && return ""
    if md isa Base.Docs.DocStr
        return strip(join(md.text))
    elseif md isa Base.Docs.MultiDoc
        isempty(md.order) && return ""
        d = md.docs[md.order[1]]
        return d isa Base.Docs.DocStr ? strip(join(d.text)) : strip(string(d))
    else
        return strip(string(md))
    end
end

"""
    _binding_doc(mod, sym) -> String

Full documentation for the binding `mod.sym` as plain markdown, or "" if none.
This is the `(module, symbol)` form `@doc` lowers to — the only path that works
on Julia 1.12, where `Base.Docs.doc(obj)` has no method for modules/types/functions.
"""
function _binding_doc(mod::Module, sym::Symbol)
    md = try
        Base.Docs._doc(Base.Docs.Binding(mod, sym))
    catch
        nothing
    end
    str = _render_doc(md)
    (isempty(str) || startswith(str, "No documentation found")) && return ""
    String(str)
end

# Object-based convenience: derive the binding from a module/type/function value.
function _doc_string(obj)
    if obj isa Module
        return _binding_doc(parentmodule(obj), nameof(obj))
    elseif obj isa Type || obj isa Function
        return _binding_doc(parentmodule(obj), nameof(obj))
    end
    ""
end

function _first_paragraph(doc::AbstractString)
    isempty(doc) && return ""
    lines = split(doc, '\n')
    para = String[]
    started = false
    for line in lines
        s = strip(line)
        if isempty(s)
            started && break
            continue
        end
        if !started && startswith(line, "  ")
            continue
        end
        started = true
        push!(para, s)
    end
    join(para, " ")
end

function _submodules(proj::Module)
    mods = Pair{Symbol,Module}[]
    for name in sort!(collect(names(proj; all=true)))
        isdefined(proj, name) || continue
        obj = getfield(proj, name)
        obj isa Module || continue
        (obj === proj || obj === Base || obj === Core) && continue
        push!(mods, name => obj)
    end
    mods
end

function _struct_types(mod::Module)
    types = Pair{Symbol,Type}[]
    for name in sort!(collect(names(mod; all=true)))
        isdefined(mod, name) || continue
        obj = getfield(mod, name)
        obj isa Type || continue
        isstructtype(obj) || continue
        parentmodule(obj) === mod || continue
        push!(types, name => obj)
    end
    types
end

function _module_functions(mod::Module)
    proj = _projectured()
    fns = Pair{Symbol,Any}[]
    for name in sort!(collect(names(mod; all=true)))
        isdefined(mod, name) || continue
        obj = getfield(mod, name)
        obj isa Function || continue
        obj isa Type && continue
        pm = parentmodule(obj)
        (pm === mod || parentmodule(pm) === proj) || continue
        push!(fns, name => obj)
    end
    fns
end

# ═══════════════════════════════════════════════════════════════════════
# Documentation & API search
# ═══════════════════════════════════════════════════════════════════════
#
# Two read-only search functions, also exposed as MCP tools, so an AI can
# find the right guide section or API entry in one call instead of listing
# and reading every resource. Both reuse the reflection/guide helpers above.

# Split a query into lowercase alphanumeric/underscore terms (drop 1-char noise).
_query_terms(q::AbstractString) =
    filter(t -> length(t) >= 2, split(lowercase(q), r"[^a-z0-9_]+"))

# Count case-insensitive occurrences of every term in `text`, scaled by `weight`.
function _term_score(terms, text::AbstractString, weight::Int)
    isempty(text) && return 0
    lt = lowercase(text)
    s = 0
    for t in terms
        s += weight * length(findall(t, lt))
    end
    s
end

# A short, whitespace-collapsed excerpt of `body` centred on the first term hit.
function _excerpt(body::AbstractString, terms; width::Int=240)
    isempty(body) && return ""
    lt = lowercase(body)
    pos = nothing
    for t in terms
        r = findfirst(t, lt)
        r === nothing && continue
        (pos === nothing || first(r) < pos) && (pos = first(r))
    end
    pos === nothing && (pos = 1)
    start = thisind(body, max(1, pos - 60))
    stop  = thisind(body, min(lastindex(body), pos + width))
    snippet = strip(replace(body[start:stop], r"\s+" => " "))
    (start > 1 ? "…" : "") * snippet * (stop < lastindex(body) ? "…" : "")
end

# ── Guide documentation index ──────────────────────────────────────────────

struct _GuideSection
    guide::String
    heading::String
    body::String
end

function _index_guide_sections()
    doc_dir = joinpath(@__DIR__, "../../../guide")
    sections = _GuideSection[]
    isdir(doc_dir) || return sections
    for (root, dirs, files) in walkdir(doc_dir)
        for file in sort(files)
            endswith(file, ".md") || continue
            filepath = joinpath(root, file)
            relpath = replace(filepath, doc_dir * "/" => "")
            guide_name = replace(relpath, ".md" => "")
            content = read(filepath, String)
            heading = ""
            buf = String[]
            for line in split(content, '\n')
                if startswith(strip(line), "#")
                    body = strip(join(buf, "\n"))
                    (isempty(body) && isempty(heading)) ||
                        push!(sections, _GuideSection(guide_name, heading, body))
                    heading = strip(replace(line, r"^\s*#+\s*" => ""))
                    empty!(buf)
                else
                    push!(buf, line)
                end
            end
            body = strip(join(buf, "\n"))
            (isempty(body) && isempty(heading)) ||
                push!(sections, _GuideSection(guide_name, heading, body))
        end
    end
    sections
end

const _GUIDE_INDEX = Ref{Union{Nothing,Vector{_GuideSection}}}(nothing)
_guide_index() = (_GUIDE_INDEX[] === nothing && (_GUIDE_INDEX[] = _index_guide_sections()); _GUIDE_INDEX[])

"""
    search_documentation(query; limit=8) -> String

Keyword-search the ProjecturEd guide documentation. Splits guides into
heading-delimited sections, ranks them by how often the query terms appear
(headings weighted higher than body), and returns the top `limit` hits as a
markdown list of `resource://guide/{name}` URIs plus a short excerpt. Read the
full text with `read_resource(uri)`.
"""
function search_documentation(query::AbstractString; limit::Integer=8)
    terms = _query_terms(query)
    isempty(terms) && return "Provide a search query (two or more characters)."
    scored = Tuple{Int,_GuideSection}[]
    for sec in _guide_index()
        s = _term_score(terms, sec.heading, 5) + _term_score(terms, sec.body, 1)
        s > 0 && push!(scored, (s, sec))
    end
    isempty(scored) && return "No documentation matches \"$query\"."
    sort!(scored; by = x -> -x[1])
    io = IOBuffer()
    println(io, "# Documentation matches for \"$query\"\n")
    for (s, sec) in first(scored, min(limit, length(scored)))
        head = isempty(sec.heading) ? "" : " — $(sec.heading)"
        println(io, "## resource://guide/$(sec.guide)$head")
        println(io, _excerpt(sec.body, terms))
        println(io)
    end
    String(take!(io))
end

# ── API (module / class / function) index ──────────────────────────────────

struct _ApiEntry
    kind::String      # "module" | "class" | "function"
    qualname::String  # "Mod" or "Mod.Name"
    doc::String       # first-paragraph documentation
    locator::String   # how to read the full docs
end

function _index_api()
    proj = _projectured()
    entries = _ApiEntry[]
    for (mod_sym, mod) in _submodules(proj)
        mn = String(mod_sym)
        push!(entries, _ApiEntry("module", mn,
                                 _first_paragraph(_binding_doc(proj, mod_sym)),
                                 "resource://module/$mn"))
        for (cls_sym, T) in _struct_types(mod)
            cn = String(cls_sym)
            startswith(cn, "#") && continue  # skip compiler-generated closure types
            push!(entries, _ApiEntry("class", "$mn.$cn",
                                     _first_paragraph(_binding_doc(mod, cls_sym)),
                                     "resource://class/$mn/$cn"))
        end
        for (fn_sym, fn) in _module_functions(mod)
            fnn = String(fn_sym)
            startswith(fnn, "#") && continue  # skip compiler-generated closures
            # Per-function resources are not pre-registered (would fan out to
            # hundreds); read full docs on demand via this call instead.
            push!(entries, _ApiEntry("function", "$mn.$fnn",
                                     _first_paragraph(_binding_doc(mod, fn_sym)),
                                     "read_function_documentation(\"$mn\", \"$fnn\")"))
        end
    end
    entries
end

const _API_INDEX = Ref{Union{Nothing,Vector{_ApiEntry}}}(nothing)
_api_index() = (_API_INDEX[] === nothing && (_API_INDEX[] = _index_api()); _API_INDEX[])

# Rank: exact name match > name substring > qualified-name substring; doc hits add a little.
function _api_score(terms, e::_ApiEntry)
    name = lowercase(last(split(e.qualname, '.')))
    full = lowercase(e.qualname)
    doc  = lowercase(e.doc)
    s = 0
    for t in terms
        if name == t
            s += 100
        elseif occursin(t, name)
            s += 20
        elseif occursin(t, full)
            s += 10
        end
        s += length(findall(t, doc))
    end
    s
end

"""
    search_api(query; kind=nothing, limit=8) -> String

Search ProjecturEd modules, structs (classes), and functions by name and
docstring. Ranks exact name matches above name substrings above docstring
matches and returns the top `limit` hits. Each hit shows its kind, qualified
name, one-line doc, and how to read full docs: a `resource://…` URI for modules
and classes, or a `read_function_documentation(…)` call for functions. Pass
`kind` (`"module"`, `"class"`, or `"function"`) to filter.
"""
function search_api(query::AbstractString; kind=nothing, limit::Integer=8)
    terms = _query_terms(query)
    isempty(terms) && return "Provide a search query (two or more characters)."
    scored = Tuple{Int,_ApiEntry}[]
    for e in _api_index()
        (kind === nothing || e.kind == kind) || continue
        s = _api_score(terms, e)
        s > 0 && push!(scored, (s, e))
    end
    if isempty(scored)
        suffix = kind === nothing ? "" : " (kind=$kind)"
        return "No API matches \"$query\"$suffix."
    end
    sort!(scored; by = x -> -x[1])
    io = IOBuffer()
    println(io, "# API matches for \"$query\"\n")
    for (s, e) in first(scored, min(limit, length(scored)))
        doc = isempty(e.doc) ? "(no documentation)" : e.doc
        println(io, "- **$(e.kind)** `$(e.qualname)` — $doc")
        println(io, "  → read full: `$(e.locator)`")
    end
    String(take!(io))
end

# Coerce a tool argument (which may arrive as string/float/int) to an Int.
function _arg_int(v, default::Int)
    v === nothing && return default
    v isa Integer && return Int(v)
    v isa Real && return round(Int, v)
    n = tryparse(Float64, string(v))
    n === nothing ? default : round(Int, n)
end

# Normalise an optional `kind` argument to nothing or a lowercase string.
function _arg_kind(v)
    v === nothing && return nothing
    s = lowercase(strip(string(v)))
    isempty(s) ? nothing : s
end

"""
    mcp_stop!(mcp::McpServer) -> McpServer

Stop the MCP server.
"""
function mcp_stop!(mcp::McpServer)
    try
        stop!(mcp.server)
    catch e
        e isa ModelContextProtocol.ServerError || rethrow()
    end
    mcp
end

end # module McpModule
