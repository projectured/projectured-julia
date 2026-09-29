# Fragment of `ProjecturedKernelExample` — the call sites of the names of a search
# corpus: where a caller writes a name, found with the parser of Julia.
#
# A docstring says what a name does, and a call site shows how a caller writes it
# and which names it goes with. `plan/done/a-classifier-ranks-the-search.md`
# measures whether a search ranks better with them.

const _JS = Base.JuliaSyntax

"""
    CallSite(name, file, line, text, caller)

One call of `name`: the `file` and the `line` it is on, the `text` of that line,
and the first line of the signature of the function that holds it, or an empty
`caller` at the top level. A constructor call of a type is a call site of the
type.
"""
struct CallSite
    name::String
    file::String
    line::Int
    text::String
    caller::String
end

# The longest line text and caller text a call site keeps, in characters.
const _CALL_SITE_TEXT_LIMIT = 160
const _CALL_SITE_CALLER_LIMIT = 100

_cut_text(text::AbstractString, limit::Int) =
    length(text) <= limit ? String(text) : first(text, limit - 1) * "…"

# The name a callee node calls: `f`, `M.f`, `T{X}`, or nothing for anything else,
# such as a call of a call or of a field of a value.
function _get_callee_name(node)
    kind = _JS.kind(node)
    if _JS.is_leaf(node)
        return kind === _JS.K"Identifier" ? _JS.sourcetext(node) : nothing
    end
    children = _JS.children(node)
    if kind === _JS.K"curly"
        return _get_callee_name(children[1])
    elseif kind === _JS.K"." && length(children) == 2
        # `Module.name` calls the name; `value.field(x)` calls a field. A module is
        # spelled in CamelCase and a value in lower case.
        left, right = children
        (_JS.is_leaf(left) && _JS.kind(left) === _JS.K"Identifier" &&
         isuppercase(first(_JS.sourcetext(left)))) || return nothing
        return _get_callee_name(right)
    end
    nothing
end

# Whether a call node is the signature of a definition rather than a call. The
# parser gives `f(x) = y` as a `function` node too, and the call of its body is
# its second child.
_is_definition_signature(parent_kind, index::Int) =
    index == 1 && parent_kind in (_JS.K"function", _JS.K"=", _JS.K"::", _JS.K"where")

# Whether a node is the signature of a definition: a call, or a call under a
# return type or a `where`. `x::Int` is a typed name and not a signature.
function _is_signature_node(node)
    _JS.is_leaf(node) && return false
    kind = _JS.kind(node)
    kind === _JS.K"call" && return true
    kind in (_JS.K"where", _JS.K"::") && return _is_signature_node(_JS.children(node)[1])
    false
end

# The signature of a definition node, or nothing when the node is not one.
function _get_definition_signature(node)
    _JS.is_leaf(node) && return nothing
    kind = _JS.kind(node)
    kind in (_JS.K"function", _JS.K"=") || return nothing
    children = _JS.children(node)
    (isempty(children) || !_is_signature_node(children[1])) && return nothing
    text = first(split(_JS.sourcetext(children[1]), '\n'))
    _cut_text(strip(text), _CALL_SITE_CALLER_LIMIT)
end

# Every call site of `source`, whose first line is line `first_line` of `file`.
function _collect_source_call_sites!(found::Vector{CallSite}, source::AbstractString,
                                     file::AbstractString; first_line::Int = 1)
    tree = try
        _JS.parseall(_JS.SyntaxNode, String(source); filename = String(file),
                     ignore_errors = true)
    catch
        return found
    end
    lines = split(source, '\n')
    function visit(node, parent_kind, index, caller)
        _JS.is_leaf(node) && return
        kind = _JS.kind(node)
        signature = _get_definition_signature(node)
        signature === nothing || (caller = signature)
        children = _JS.children(node)
        if (kind === _JS.K"call" && _JS.is_prefix_call(node)) || kind === _JS.K"dotcall"
            if !_is_definition_signature(parent_kind, index) && !isempty(children)
                name = _get_callee_name(children[1])
                if name !== nothing
                    line = _JS.source_line(node)
                    text = 1 <= line <= length(lines) ? strip(lines[line]) : ""
                    push!(found, CallSite(name, String(file), first_line + line - 1,
                                          _cut_text(text, _CALL_SITE_TEXT_LIMIT), caller))
                end
            end
        end
        for (position, child) in enumerate(children)
            visit(child, kind, position, caller)
        end
    end
    visit(tree, _JS.K"toplevel", 0, "")
    found
end

# The Julia blocks of a Markdown file, each with the line its code starts on. A
# REPL line loses its `julia> ` prompt, and a line of output is left as it is,
# where the parser skips it.
function _get_markdown_julia_blocks(text::AbstractString)
    blocks = Tuple{String,Int}[]
    lines = split(text, '\n')
    index = 1
    while index <= length(lines)
        fence = match(r"^\s*```\s*(julia|jldoctest)", lines[index])
        if fence === nothing
            index += 1
            continue
        end
        start = index + 1
        stop = start
        while stop <= length(lines) && !startswith(strip(lines[stop]), "```")
            stop += 1
        end
        code = [replace(line, r"^\s*julia>\s?" => "") for line in lines[start:stop-1]]
        push!(blocks, (join(code, '\n'), start))
        index = stop + 1
    end
    blocks
end

"""
    collect_call_sites(roots; excluded = ()) -> Dict{String,Vector{CallSite}}

Every call site in the `.jl` files and in the Julia blocks of the `.md` files
under the folders `roots`, by the name called. A file whose path ends with one of
`excluded` is not read, so the files that hold the questions of a measurement,
and the scripts that answer them, do not answer them a second time.
"""
function collect_call_sites(roots; excluded = ())
    found = CallSite[]
    for root in roots, (folder, _, files) in walkdir(root), file in files
        path = joinpath(folder, file)
        any(suffix -> endswith(path, suffix), excluded) && continue
        if endswith(file, ".jl")
            _collect_source_call_sites!(found, read(path, String), path)
        elseif endswith(file, ".md")
            for (code, line) in _get_markdown_julia_blocks(read(path, String))
                _collect_source_call_sites!(found, code, path; first_line = line)
            end
        end
    end
    sites = Dict{String,Vector{CallSite}}()
    for site in found
        push!(get!(() -> CallSite[], sites, site.name), site)
    end
    sites
end

"""
    find_module_folder(mod) -> Union{String,Nothing}

The folder that holds most of the methods `mod` defines, or `nothing` when it
defines none. A call site outside this folder is a call from outside the module.
"""
function find_module_folder(mod::Module)
    counts = Dict{String,Int}()
    for name in names(mod; all = true)
        (isdefined(mod, name) && !Base.isdeprecated(mod, name)) || continue
        value = getfield(mod, name)
        (value isa Function || value isa Type) || continue
        for method in methods(value)
            method.module === mod || continue
            folder = dirname(String(method.file))
            counts[folder] = get(counts, folder, 0) + 1
        end
    end
    isempty(counts) ? nothing : first(argmax(last, collect(counts)))
end

"""
    rank_call_sites(sites, home) -> Vector{CallSite}

The call sites of one name, best first: a call from outside the folder `home`
before a call from inside it, one call site per calling function, and one per
file before a second from a file already shown. `home` is `nothing` when the
folder of the name is not known, and then every call counts as outside.
"""
function rank_call_sites(sites::Vector{CallSite}, home)
    is_inside(site) = home !== nothing && startswith(site.file, home * "/")
    ordered = sort(sites; by = site -> (is_inside(site), site.file, site.line))
    unique_callers = CallSite[]
    callers = Set{Tuple{String,String}}()
    for site in ordered
        key = (site.file, isempty(site.caller) ? string(site.line) : site.caller)
        key in callers && continue
        push!(callers, key)
        push!(unique_callers, site)
    end
    first_of_file = CallSite[]
    rest = CallSite[]
    files = Set{String}()
    for site in unique_callers
        if site.file in files
            push!(rest, site)
        else
            push!(first_of_file, site)
            push!(files, site.file)
        end
    end
    # A file shown once comes before a second site of any file, and within each
    # group the order stays: outside before inside.
    vcat(first_of_file, rest)
end

"""
    format_call_sites(sites; root = "") -> String

The call sites as lines a reader, or a model, reads: the file relative to `root`,
the line, the calling function, and the call.
"""
function format_call_sites(sites; root::AbstractString = "")
    lines = String[]
    for site in sites
        file = isempty(root) ? site.file : relpath(site.file, root)
        caller = isempty(site.caller) ? "" : " in `" * site.caller * "`"
        push!(lines, "- " * file * ":" * string(site.line) * caller * ": `" * site.text * "`")
    end
    join(lines, '\n')
end

# ═══════════════════════════════════════════════════════════════════════
# The code of a definition
# ═══════════════════════════════════════════════════════════════════════

# The first line of each `struct` and `abstract type` in the Julia files under
# `roots`, by the name it declares. A type that a macro declares is found here,
# because its methods point at the code the macro generates, not at the type.
function _collect_type_declarations(roots)
    found = Dict{String,Tuple{String,Int}}()
    pattern = r"^\s*(?:@\w+\s+)*(?:mutable\s+)?struct\s+(\w+)|^\s*abstract\s+type\s+(\w+)"
    for root in roots, (folder, _, files) in walkdir(root), file in files
        endswith(file, ".jl") || continue
        path = joinpath(folder, file)
        for (index, line) in enumerate(eachline(path))
            m = match(pattern, line)
            m === nothing && continue
            name = something(m.captures[1], m.captures[2])
            haskey(found, name) || (found[name] = (path, index))
        end
    end
    found
end

# Where `name` of `mod` is defined: the line of a method the module defines that
# names it, or the declaration of a type, or `nothing`.
function _find_definition_place(mod::Module, value, name::AbstractString, declarations, lines_of)
    bare = lstrip(name, '@')
    if value isa Function || value isa Type
        for method in methods(value)
            method.module === mod || continue
            file = String(method.file)
            isfile(file) || continue
            text = get(get!(() -> readlines(file), lines_of, file), Int(method.line), "")
            occursin(bare, text) && return (file, Int(method.line))
        end
    end
    get(declarations, bare, nothing)
end

"""
    collect_definition_code(entries, modules, roots; lines = 15, limit = 800)
        -> Dict{String,String}

The first `lines` lines of the definition of each function and type of `entries`,
cut at `limit` characters, by qualified name. The code starts at the line that
defines the name, so the docstring above it is not in it. `modules` maps the name
of a module to the module; `roots` are the folders a type that a macro declares
is looked for in. A name whose definition is not found has no code.
"""
function collect_definition_code(entries, modules, roots; lines::Int = 15, limit::Int = 800)
    declarations = _collect_type_declarations(roots)
    lines_of = Dict{String,Vector{String}}()
    code = Dict{String,String}()
    for entry in entries
        entry.kind in ("function", "type") || continue
        module_name, name = String.(split(entry.qualname, '.'; limit = 2))
        mod = get(modules, module_name, nothing)
        (mod === nothing || !isdefined(mod, Symbol(name))) && continue
        place = _find_definition_place(mod, getfield(mod, Symbol(name)), name, declarations, lines_of)
        place === nothing && continue
        file, line = place
        text = get!(() -> readlines(file), lines_of, file)
        code[entry.qualname] = _cut_text(join(text[line:min(end, line + lines - 1)], '\n'), limit)
    end
    code
end
