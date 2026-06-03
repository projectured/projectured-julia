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
       read_module_documentation, read_class_documentation, read_function_documentation

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
        "NEVER guess names or signatures. Look them up.\n" *
        "NEVER call print(). NEVER include code comments.\n\n" *
        "Additional resources (via MCP list_resources):\n" *
        "- resource://guide/{guide_name}\n" *
        "- resource://module/{module_name}\n" *
        "- resource://class/{module_name}/{class_name}\n" *
        "- resource://function/{module_name}/{function_signature}",
        NamedTuple[
            (name="code", type="string",
             description="Julia source code to evaluate", required=true),
        ],
        (editor, args) -> execute_julia_code(editor, args["code"]),
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
        for (fn_sym, _) in _module_functions(mod)
            let mn = String(mod_sym), fn = String(fn_sym)
                register_resource!(Resource(
                    "resource://function/$mn/$fn",
                    "Function: $mn.$fn",
                    "Full documentation for function $fn in module $mn.",
                    () -> read_function_documentation(mn, fn),
                ))
            end
        end
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

function _doc_string(obj)
    md = Base.Docs.doc(obj)
    str = string(md)
    startswith(str, "No documentation found") && return ""
    String(strip(str))
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
