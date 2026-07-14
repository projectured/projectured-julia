# Fragment of `ToolModule` — reading and searching the project's own
# documentation: the guides on disk, and the API (modules / types / functions)
# reachable by reflection.
#
# These are read-only and derived from source that does not change while the
# process runs, which is why the two indexes below may be process-global caches.

# ═══════════════════════════════════════════════════════════════════════
# Guides
# ═══════════════════════════════════════════════════════════════════════

"""
    _guide_roots() -> Vector{Tuple{String,String}}

The directories scanned for guide documentation, each paired with the prefix
prepended to the guide names found under it. The top-level `documentation/` tree
keeps bare names (`concepts`, `getting-started`, …); each package's `doc/` tree is
namespaced by package (`kernel/reference`, `visual/widget`, …) so guides live next
to the code they document without name collisions.
"""
function _guide_roots()
    repo = joinpath(@__DIR__, "../../../..")
    roots = Tuple{String,String}[(joinpath(repo, "documentation"), "")]
    pkg_dir = joinpath(repo, "package")
    if isdir(pkg_dir)
        for pkg in sort(readdir(pkg_dir))
            d = joinpath(pkg_dir, pkg, "doc")
            isdir(d) && push!(roots, (d, "$pkg/"))
        end
    end
    roots
end

"""
    _all_guides() -> Vector{Tuple{String,String}}

Every guide as `(guide_name, filepath)`, across every root in `_guide_roots()`.
"""
function _all_guides()
    guides = Tuple{String,String}[]
    for (root, prefix) in _guide_roots()
        isdir(root) || continue
        for (dir, _, files) in walkdir(root)
            for file in sort(files)
                endswith(file, ".md") || continue
                filepath = joinpath(dir, file)
                rel = replace(filepath, root * "/" => "")
                push!(guides, (prefix * replace(rel, ".md" => ""), filepath))
            end
        end
    end
    guides
end

"""
    list_guides() -> String

List all available documentation with a one-paragraph description for each guide.
Guides are markdown files containing tips and tricks for using ProjecturEd.
"""
function list_guides()
    guides = _all_guides()
    isempty(guides) && return "No guide directory found."

    guides_info = String[]
    for (guide_name, filepath) in guides
        content = read(filepath, String)
        # The first paragraph after the title is the description.
        description_lines = String[]
        in_description = false
        seen_heading = false
        for line in split(content, '\n')
            stripped = strip(line)
            if isempty(stripped)
                in_description && break
                continue
            elseif startswith(stripped, "#")
                seen_heading = true
            elseif seen_heading && !startswith(stripped, "#")
                in_description = true
                push!(description_lines, stripped)
            end
        end
        push!(guides_info, "**$guide_name**: $(join(description_lines, " "))")
    end
    isempty(guides_info) && return "No documentation found."
    "# Available Guides\n\n" * join(guides_info, "\n\n")
end

"""
    read_guide(guide_name) -> String

Read the full content of a specific guide by name.
"""
function read_guide(guide_name)
    for (name, filepath) in _all_guides()
        if name == guide_name
            try
                return read(filepath, String)
            catch e
                return "Error reading documentation '$guide_name': $(e)"
            end
        end
    end
    "Documentation '$guide_name' not found."
end

# ═══════════════════════════════════════════════════════════════════════
# Reflection over the loaded package
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

Full documentation for the binding `mod.sym` as plain markdown, or `""` if none.
This is the `(module, symbol)` form `@doc` lowers to — the only path that works on
Julia 1.12, where `Base.Docs.doc(obj)` has no method for modules/types/functions.
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
    para = String[]
    started = false
    for line in split(doc, '\n')
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
    for name in sort!(collect(names(proj; all = true)))
        isdefined(proj, name) || continue
        obj = getfield(proj, name)
        obj isa Module || continue
        (obj === proj || obj === Base || obj === Core) && continue
        push!(mods, name => obj)
    end
    mods
end

# True for compiler-generated names that should never surface to a human/AI:
# gensym'd closure and method types (`#print_document##0#…`, `##BookBook#1`,
# `#10#11`). They flood the listings with hundreds of meaningless entries.
_is_gensym_name(sname::AbstractString) = occursin('#', sname)

# True for the `IFoo` interface type `@document` generates next to each document
# type `Foo` — internal plumbing the caller should not see. Only treats a name as
# an interface when the sibling `Foo` actually exists in the module, so legitimate
# I-prefixed names (`Inset`, …) are kept.
function _is_interface_name(sname::AbstractString, present::Set{Symbol})
    length(sname) > 1 && sname[1] == 'I' && isuppercase(sname[2]) &&
        Symbol(sname[2:end]) in present
end

function _struct_types(mod::Module)
    types = Pair{Symbol,Type}[]
    allnames = names(mod; all = true)
    present = Set(allnames)
    for name in sort!(collect(allnames))
        sname = string(name)
        (_is_gensym_name(sname) || _is_interface_name(sname, present)) && continue
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
    for name in sort!(collect(names(mod; all = true)))
        _is_gensym_name(string(name)) && continue
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
# Documentation readers
# ═══════════════════════════════════════════════════════════════════════

"""
    list_modules() -> String

List all modules with one-paragraph documentation for each and a list of its
top-level types.
"""
function list_modules()
    modules_info = String[]
    for (name, mod) in _submodules(_projectured())
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
    list_types(module_name) -> String

List all types within a module with their one-paragraph documentation.
"""
function list_types(module_name)
    mod = _find_module(module_name)
    isnothing(mod) && return "Module '$module_name' not found."
    types_info = String[]
    for (name, T) in _struct_types(mod)
        doc = _doc_string(T)
        summary = isempty(doc) ? "No documentation available." : _first_paragraph(doc)
        mutable_str = ismutabletype(T) ? "mutable " : ""
        push!(types_info, "**$mutable_str$name**: $summary")
    end
    isempty(types_info) && return "No types found in module '$module_name'."
    join(types_info, "\n\n")
end

"""
    list_functions(module_name, type_name = nothing) -> String

List all functions within a module (optionally only those mentioning `type_name`
in a signature) with their one-paragraph documentation.
"""
function list_functions(module_name, type_name = nothing)
    mod = _find_module(module_name)
    isnothing(mod) && return "Module '$module_name' not found."
    functions_info = String[]
    for (name, fn) in _module_functions(mod)
        if type_name !== nothing && !any(occursin(type_name, string(m.sig)) for m in methods(fn))
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

Read the full documentation for a module.
"""
function read_module_documentation(module_name)
    mod = _find_module(module_name)
    isnothing(mod) && return "Module '$module_name' not found."
    doc = _doc_string(mod)
    isempty(doc) && return "Module $module_name — no documentation available."
    doc
end

"""
    read_type_documentation(module_name, type_name) -> String

Read the full documentation for a type within a module. A type with no docstring
falls back to a listing of its fields, which is more use than nothing.
"""
function read_type_documentation(module_name, type_name)
    mod = _find_module(module_name)
    isnothing(mod) && return "Module '$module_name' not found."
    sym = Symbol(type_name)
    (isdefined(mod, sym) && getfield(mod, sym) isa Type) ||
        return "Type '$type_name' not found in module '$module_name'."
    T = getfield(mod, sym)
    doc = _doc_string(T)
    if isempty(doc)
        fields = fieldnames(T)
        isempty(fields) && return "$type_name — no documentation available."
        field_info = join(["- `$(f)::$(fieldtype(T, f))`" for f in fields], "\n")
        return "# $type_name\n\n## Fields\n$field_info"
    end
    doc
end

"""
    read_function_documentation(module_name, function_signature, type_name = nothing) -> String

Read the full documentation for a function within a module.
"""
function read_function_documentation(module_name, function_signature, type_name = nothing)
    mod = _find_module(module_name)
    isnothing(mod) && return "Module '$module_name' not found."
    func_name = replace(function_signature, r"\(.*" => "")
    sym = Symbol(func_name)
    isdefined(mod, sym) ||
        return "Function '$function_signature' not found in module '$module_name'."
    doc = _doc_string(getfield(mod, sym))
    isempty(doc) && return "No documentation available for '$function_signature'."
    doc
end

# ═══════════════════════════════════════════════════════════════════════
# Search
# ═══════════════════════════════════════════════════════════════════════
#
# Two read-only search functions, so a caller can find the right guide section or
# API entry in one call instead of listing and reading every resource.

# Split a query into lowercase alphanumeric/underscore terms (drop 1-char noise).
_query_terms(q::AbstractString) =
    filter(t -> length(t) >= 2, split(lowercase(q), r"[^a-z0-9_]+"))

# Turn a query into `(patterns, fold)`: `patterns` is what we match against text,
# `fold` is applied to both query and haystack first. The query *type* selects the
# mode — a String searches keywords case-insensitively, a Regex matches
# original-case text (use the `i` flag for case-insensitivity). `findall` /
# `occursin` / `findfirst` accept both, so the scoring below is shared.
_matchers(q::AbstractString) = (_query_terms(q), lowercase)
_matchers(q::Regex)          = (Any[q], identity)

# Count occurrences of every pattern in `text` (after `fold`), scaled by `weight`.
function _term_score(patterns, text::AbstractString, weight::Int, fold)
    isempty(text) && return 0
    ft = fold(text)
    s = 0
    for t in patterns
        s += weight * length(findall(t, ft))
    end
    s
end

# A short, whitespace-collapsed excerpt of `body` centred on the first match.
function _excerpt(body::AbstractString, patterns, fold; width::Int = 240)
    isempty(body) && return ""
    fb = fold(body)
    pos = nothing
    for t in patterns
        r = findfirst(t, fb)
        r === nothing && continue
        (pos === nothing || first(r) < pos) && (pos = first(r))
    end
    pos === nothing && (pos = 1)
    start = thisind(body, max(1, pos - 60))
    stop  = thisind(body, min(lastindex(body), pos + width))
    snippet = strip(replace(body[start:stop], r"\s+" => " "))
    (start > 1 ? "…" : "") * snippet * (stop < lastindex(body) ? "…" : "")
end

struct _GuideSection
    guide::String
    heading::String
    body::String
end

function _index_guide_sections()
    sections = _GuideSection[]
    for (guide_name, filepath) in _all_guides()
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
    sections
end

struct _ApiEntry
    kind::String      # "module" | "type" | "function"
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
        for (cls_sym, _) in _struct_types(mod)
            cn = String(cls_sym)
            push!(entries, _ApiEntry("type", "$mn.$cn",
                                     _first_paragraph(_binding_doc(mod, cls_sym)),
                                     "resource://type/$mn/$cn"))
        end
        for (fn_sym, _) in _module_functions(mod)
            fnn = String(fn_sym)
            # Per-function resources are not pre-registered (that would fan out to
            # hundreds); full docs are read on demand via this call instead.
            push!(entries, _ApiEntry("function", "$mn.$fnn",
                                     _first_paragraph(_binding_doc(mod, fn_sym)),
                                     "read_function_documentation(\"$mn\", \"$fnn\")"))
        end
    end
    entries
end

# **Accepted AR-45 carve-out.** These two are process-global lazily-built caches,
# not per-editor state. They are derived read-only from source files that do not
# change while the process runs, and are identical for every editor — the same
# principled exception AR-45 grants the wall clock: one writer, read-only
# thereafter, a genuine singleton. No editor can observe another's writes through
# them, which is the cross-editor conflict AR-45 exists to prevent.
const _GUIDE_INDEX = Ref{Union{Nothing,Vector{_GuideSection}}}(nothing)
const _API_INDEX   = Ref{Union{Nothing,Vector{_ApiEntry}}}(nothing)

_guide_index() =
    (_GUIDE_INDEX[] === nothing && (_GUIDE_INDEX[] = _index_guide_sections()); _GUIDE_INDEX[])
_api_index() =
    (_API_INDEX[] === nothing && (_API_INDEX[] = _index_api()); _API_INDEX[])

"""
    search_documentation(query; limit = 8) -> String

Search the guide documentation. Splits guides into heading-delimited sections,
ranks them by how often the query matches (headings weighted higher than body),
and returns the top `limit` hits as a markdown list of `resource://guide/{name}`
URIs plus a short excerpt. Read the full text with `read_resource(set, uri)`.

The **query type selects the mode** (Julia dispatch):

- `query::AbstractString` — plain keywords (**not** a regex, no boolean
  operators): lowercased and split into tokens (alphanumeric/underscore, 2+
  characters) matched case-insensitively as substrings. Any token matching
  includes the section (OR semantics); more — and heading — matches rank higher.
- `query::Regex` — regular-expression match against the original-case text (add
  the `i` flag for case-insensitivity), e.g. `search_documentation(r"replace.*range")`.
"""
function search_documentation(query::Union{AbstractString,Regex}; limit::Integer = 8)
    patterns, fold = _matchers(query)
    isempty(patterns) && return "Provide a search query (two or more characters)."
    scored = Tuple{Int,_GuideSection}[]
    for sec in _guide_index()
        s = _term_score(patterns, sec.heading, 5, fold) + _term_score(patterns, sec.body, 1, fold)
        s > 0 && push!(scored, (s, sec))
    end
    isempty(scored) && return "No documentation matches $(repr(query))."
    sort!(scored; by = x -> -x[1])
    io = IOBuffer()
    println(io, "# Documentation matches for $(repr(query))\n")
    for (_, sec) in first(scored, min(limit, length(scored)))
        head = isempty(sec.heading) ? "" : " — $(sec.heading)"
        println(io, "## resource://guide/$(sec.guide)$head")
        println(io, _excerpt(sec.body, patterns, fold))
        println(io)
    end
    String(take!(io))
end

# Rank: exact name match > name substring > qualified-name substring; doc hits add
# a little. The exact-name tier only applies to string keywords; a Regex still
# scores via its name / qualified-name / doc matches.
function _api_score(patterns, e::_ApiEntry, fold)
    name = fold(last(split(e.qualname, '.')))
    full = fold(e.qualname)
    doc  = fold(e.doc)
    s = 0
    for t in patterns
        if t isa AbstractString && name == t
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
    search_api(query; kind = nothing, limit = 8) -> String

Search modules, types, and functions by name and docstring. Ranks exact name
matches above name substrings above docstring matches and returns the top `limit`
hits. Each hit shows its kind, qualified name, one-line doc, and how to read the
full docs: a `resource://…` URI for modules and types, or a
`read_function_documentation(…)` call for functions. Pass `kind` (`"module"`,
`"type"`, or `"function"`) to filter.

The **query type selects the mode**, exactly as in `search_documentation` — a
`String` is keywords, a `Regex` is a pattern (the exact-name bonus does not apply
to a regex; ranking is by where it matches).
"""
function search_api(query::Union{AbstractString,Regex}; kind = nothing, limit::Integer = 8)
    patterns, fold = _matchers(query)
    isempty(patterns) && return "Provide a search query (two or more characters)."
    scored = Tuple{Int,_ApiEntry}[]
    for e in _api_index()
        (kind === nothing || e.kind == kind) || continue
        s = _api_score(patterns, e, fold)
        s > 0 && push!(scored, (s, e))
    end
    if isempty(scored)
        suffix = kind === nothing ? "" : " (kind=$kind)"
        return "No API matches $(repr(query))$suffix."
    end
    sort!(scored; by = x -> -x[1])
    io = IOBuffer()
    println(io, "# API matches for $(repr(query))\n")
    for (_, e) in first(scored, min(limit, length(scored)))
        doc = isempty(e.doc) ? "(no documentation)" : e.doc
        println(io, "- **$(e.kind)** `$(e.qualname)` — $doc")
        println(io, "  → read full: `$(e.locator)`")
    end
    String(take!(io))
end

# ── Tool-argument coercion ─────────────────────────────────────────────────
# A tool argument arrives from JSON, so it may be a Bool, a number, or a string
# spelling of either.

function _arg_int(v, default::Int)
    v === nothing && return default
    v isa Integer && return Int(v)
    v isa Real && return round(Int, v)
    n = tryparse(Float64, string(v))
    n === nothing ? default : round(Int, n)
end

function _arg_kind(v)
    v === nothing && return nothing
    s = lowercase(strip(string(v)))
    isempty(s) ? nothing : s
end

function _arg_bool(v, default::Bool)
    v === nothing && return default
    v isa Bool && return v
    v isa Real && return v != 0
    lowercase(strip(string(v))) in ("true", "1", "yes")
end

# The search query from tool args: a plain `String` (keywords), or a `Regex` when
# `regex=true`. Compiling an invalid pattern throws — the tool handlers catch it
# and return a readable error.
_query_arg(args) =
    _arg_bool(get(args, "regex", false), false) ?
        Regex(String(args["query"])) : String(args["query"])
