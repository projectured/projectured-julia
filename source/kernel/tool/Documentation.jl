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
keeps bare names (`concepts`, `getting-started`, …); each slice's folder under
`documentation/package/` is namespaced by slice (`kernel/reference`,
`widget/widget`, …) so two slices may both have a guide of one name.

The bare walk skips `documentation/package/`, which its own roots cover. Without
that, every slice guide would be listed twice under two names.
"""
function _guide_roots()
    repo = joinpath(@__DIR__, "../../..")
    roots = Tuple{String,String}[(joinpath(repo, "documentation"), "")]
    pkg_dir = joinpath(repo, "documentation", "package")
    if isdir(pkg_dir)
        for pkg in sort(readdir(pkg_dir))
            d = joinpath(pkg_dir, pkg)
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
            # The per-slice roots below cover documentation/package/, and they
            # give a guide the namespaced name every citation uses. Walking it
            # here as well would list each of those guides twice.
            (prefix == "" && occursin(joinpath("documentation", "package"), dir)) && continue
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

# Is this name one the declaration gives? An empty declaration is the whole
# surface, where every name of a reachable module is.
#
# A model that reads the documentation of a name it cannot write spends a round
# learning that it cannot, which is the same waste `_index_declared` avoids by
# indexing only what is declared.
function _is_declared(api, mod::Module, name::Symbol)
    isempty(api) && return true
    for entry in api
        entry.module_ === mod && return name in api_entry_names(entry)
    end
    false
end

function _find_module(name::String, api = ApiEntry[])
    # A declared module is not a submodule of the umbrella, so the declared ones
    # are looked in first — and, when there are any, only there.
    for entry in api
        String(nameof(entry.module_)) == name && return entry.module_
    end
    isempty(api) || return nothing
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

"""
What a search scores an entry on: the signature and the sentence under it.

**The first paragraph is the signature**, not the description. Julia strips a
docstring's common indentation before it is stored, so the indented signature
block arrives flush left and `_first_paragraph`'s guard against it never fires.
That is right for what a hit *shows* — the prompt promises a one-line signature,
and a model calls a verb off it without reading more — and wrong for what a hit
is *found* by: scored on the signature alone, no word of the description is
searchable, and a verb is reachable only through its name. `show_layout`'s
docstring says "Which panes are open"; a search for "panes" answered nothing.

Two paragraphs, not the whole text: the sentence under the signature is where a
docstring says what the thing does, and the rest is detail that would only blur
the ranking.
"""
function _search_text(doc::AbstractString)
    isempty(doc) && return ""
    paragraphs = String[]
    current = String[]
    for line in split(doc, '\n')
        stripped = strip(line)
        if isempty(stripped)
            isempty(current) || (push!(paragraphs, join(current, " ")); current = String[])
            length(paragraphs) == 2 && break
        else
            push!(current, String(stripped))
        end
    end
    (isempty(current) || length(paragraphs) == 2) || push!(paragraphs, join(current, " "))
    join(paragraphs, " ")
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

# True for the `ICFoo` interface type `@document` generates next to each document
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
function list_modules(; api = ApiEntry[])
    modules_info = String[]
    for (name, mod) in (isempty(api) ? _submodules(_projectured()) :
                        [(nameof(e.module_), e.module_) for e in api])
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
function read_module_documentation(module_name; api = ApiEntry[])
    mod = _find_module(String(module_name), api)
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
function read_type_documentation(module_name, type_name; api = ApiEntry[])
    mod = _find_module(String(module_name), api)
    isnothing(mod) && return "Module '$module_name' not found."
    sym = Symbol(type_name)
    _is_declared(api, mod, sym) ||
        return "Type '$type_name' is not one of the names you may write."
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
function read_function_documentation(module_name, function_signature, type_name = nothing;
                                    api = ApiEntry[])
    mod = _find_module(String(module_name), api)
    isnothing(mod) && return "Module '$module_name' not found."
    func_name = replace(function_signature, r"\(.*" => "")
    sym = Symbol(func_name)
    _is_declared(api, mod, sym) ||
        return "Function '$func_name' is not one of the names you may write."
    # A declaration may have renamed it, and the module knows it by its own name.
    sym = api_source_name(api, mod, sym)
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
# Each term becomes the forms it could be written in, and a score counts the best
# of them once. A person asks to "plot the vectors" and the verb is called
# `plot_vector`; a person asks about "a result" and the column is `results`. The
# fold is one `s` either way, which is the whole of the difference that was
# costing a round.
function _term_forms(term::AbstractString)
    forms = String[String(term)]
    length(term) > 3 && endswith(term, "s") && push!(forms, String(term[1:end-1]))
    length(term) > 2 && !endswith(term, "s") && push!(forms, String(term) * "s")
    forms
end

_matchers(q::AbstractString) = ([_term_forms(t) for t in _query_terms(q)], lowercase)
_matchers(q::Regex)          = (Any[Any[q]], identity)

# Count occurrences of every pattern in `text` (after `fold`), scaled by `weight`.
function _term_score(groups, text::AbstractString, weight::Int, fold)
    isempty(text) && return 0
    ft = fold(text)
    s = 0
    for forms in groups
        s += weight * maximum(length(findall(t, ft)) for t in forms)
    end
    s
end

# A short, whitespace-collapsed excerpt of `body` centred on the first match.
function _excerpt(body::AbstractString, patterns, fold; width::Int = 240)
    isempty(body) && return ""
    fb = fold(body)
    pos = nothing
    for forms in patterns, t in forms
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
    doc::String       # what a hit SHOWS: the first paragraph, which is the signature
    text::String      # what a hit is SCORED on: the signature and the description
    full::String      # the whole documentation, for a search that answers one thing
    locator::String   # how to read the full docs
end

# The index of a declared API: each named module, and the names it exports. It
# mirrors what the scratch module holds, name for name, because a model that finds
# a function it cannot call wastes a round and learns to distrust the answer.
"""
    describe_api(api; signatures = true) -> String

Every name a declaration gives, grouped by module: one signature line each, or
just the names when `signatures` is false.

**It is what a search answers when it matched nothing.** A search that says only
"no match" costs a round and teaches nothing, and the round after it is a guess.
The names are short, and they are the answer to "then what may I write?".

**It is not carried in a prompt.** The surface is 43 names and 900 tokens today,
and it grows with the application; a menu in every round is a cost that never
stops. The lookup it would save is bought instead by `search_api` answering one
clear hit in full — one round, paid only by the turn that asks.

**It is generated from the declaration**, so what it says cannot drift from what
a model may write.
"""
function describe_api(api; signatures::Bool = true)
    entries = _api_entries(api)
    lines = String[]
    for entry in entries
        mod = entry.module_
        own = String[]
        for (source, name) in api_entry_bindings(entry)
            name === nameof(mod) && continue
            isdefined(mod, source) || continue
            text = String(name)
            if !signatures
                push!(own, text)
                continue
            end
            signature = _first_paragraph(_binding_doc(mod, source))
            # A name whose documentation opens with its own signature says it
            # once; anything else is named with what it is.
            push!(own, isempty(signature) ? text :
                       startswith(strip(signature), text) ? strip(signature) :
                       text * " — " * strip(signature))
        end
        isempty(own) && continue
        if signatures
            push!(lines, String(nameof(mod)))
            append!(lines, ("  " * one for one in own))
        else
            push!(lines, String(nameof(mod)) * ": " * join(own, ", "))
        end
    end
    isempty(lines) ? "" : join(lines, "\n")
end

function _index_declared(api)
    entries = _ApiEntry[]
    for declared in api
        mod = declared.module_
        mn = String(nameof(mod))
        raw = _doc_string(mod)
        push!(entries, _ApiEntry("module", mn, _first_paragraph(raw), _search_text(raw),
                                 raw, "resource://module/$mn"))
        # The names the declaration gives, and no others. A name a model finds
        # here is a name it can write, which is the whole point of the list.
        # Indexed under the name the MODEL writes, and read from the module by
        # the name the module knows: a renamed entry is found by the word the
        # model would type, and its documentation is still its own.
        for (source, sym) in api_entry_bindings(declared)
            sym === nameof(mod) && continue
            isdefined(mod, source) || continue
            value = getfield(mod, source)
            nn = String(sym)
            raw = _binding_doc(mod, source)
            doc = _first_paragraph(raw)
            text = _search_text(raw)
            if value isa Type
                push!(entries, _ApiEntry("type", "$mn.$nn", doc, text, raw,
                                         "resource://type/$mn/$nn"))
            elseif value isa Function
                push!(entries, _ApiEntry("function", "$mn.$nn", doc, text, raw,
                                         "read_function_documentation(\"$mn\", \"$nn\")"))
            end
        end
    end
    entries
end

function _index_api()
    proj = _projectured()
    entries = _ApiEntry[]
    for (mod_sym, mod) in _submodules(proj)
        mn = String(mod_sym)
        raw = _binding_doc(proj, mod_sym)
        push!(entries, _ApiEntry("module", mn, _first_paragraph(raw), _search_text(raw),
                                 raw, "resource://module/$mn"))
        for (cls_sym, _) in _struct_types(mod)
            cn = String(cls_sym)
            raw = _binding_doc(mod, cls_sym)
            push!(entries, _ApiEntry("type", "$mn.$cn", _first_paragraph(raw), _search_text(raw),
                                     raw, "resource://type/$mn/$cn"))
        end
        for (fn_sym, _) in _module_functions(mod)
            fnn = String(fn_sym)
            # Per-function resources are not pre-registered (that would fan out to
            # hundreds); full docs are read on demand via this call instead.
            raw = _binding_doc(mod, fn_sym)
            push!(entries, _ApiEntry("function", "$mn.$fnn",
                                     _first_paragraph(raw), _search_text(raw), raw,
                                     "read_function_documentation(\"$mn\", \"$fnn\")"))
        end
    end
    entries
end

# Process-global, deliberately: lazily-built read-only indexes of the project's own
# guides and API, identical for every editor and derived from sources that do not
# change at runtime. This is the "state identical for every editor" carve-out
# PAR-PER-EDITOR-STATE grants (alongside the wall clock).
const _GUIDE_INDEX = Ref{Union{Nothing,Vector{_GuideSection}}}(nothing)
const _API_INDEX   = Ref{Union{Nothing,Vector{_ApiEntry}}}(nothing)
# One index per declared list, keyed by the list. Two editors that declare two
# different lists need two indexes and neither may see the other's
# (PAR-PER-EDITOR-STATE); the key is what keeps them apart while the carve-out
# above still holds — every entry is read-only and identical for every editor that
# declares that list.
const _DECLARED_INDEX = Dict{Vector{ApiEntry},Vector{_ApiEntry}}()

_guide_index() =
    (_GUIDE_INDEX[] === nothing && (_GUIDE_INDEX[] = _index_guide_sections()); _GUIDE_INDEX[])

function _api_index(api = ApiEntry[])
    isempty(api) || return get!(() -> _index_declared(api),
                                _DECLARED_INDEX, collect(ApiEntry, api))
    _API_INDEX[] === nothing && (_API_INDEX[] = _index_api())
    _API_INDEX[]
end

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
# **A hit is ranked on two numbers, not one.** The name score decides first and
# the prose score only separates entries the name could not. One number let each
# spoil the other: with them added, a long docstring outranked the verb the person
# named, and with the prose capped to stop that, a query matching no name at all
# collapsed into ties that the tie-break then settled by length — "scalars delay
# table" answered `DataFrames.nrow`. Both were measured, on 2026-09-13.
#
# **A stem may not earn a name match.** A term scores against the NAME exactly as
# the person wrote it, and against the prose in any of its forms. The two halves
# want opposite things: recall in the prose, where an extra hit is cheap, and
# precision in the name, where it is not. Measured the same day: with a stem
# allowed in a name, "stop runs" answered `run_simulations_in_conversation` before
# `stop_simulations`, because `run` is inside almost every verb of that module.
function _api_score(groups, e::_ApiEntry, fold)
    name = fold(last(split(e.qualname, '.')))
    qualified = fold(e.qualname)
    doc  = fold(e.text)
    named = 0
    prose = 0
    for forms in groups
        written = first(forms)
        named += (written isa AbstractString && name == written) ? 100 :
                 occursin(written, name) ? 20 :
                 occursin(written, qualified) ? 10 : 0
        prose += maximum(length(findall(t, doc)) for t in forms)
    end
    (named, prose)
end

"""
    search_api(query; kind = nothing, limit = 8) -> String

Search modules, types, and functions by name and docstring. Ranks exact name
matches above name substrings above docstring matches and returns the top `limit`
hits. Each hit shows its kind, qualified name, one-line doc, and how to read the
full docs: a `resource://…` URI for modules and types, or a
`read_function_documentation(…)` call for functions. Pass `kind` (`"module"`,
`"type"`, or `"function"`) to filter.

`modules` is the declared API of a `ToolSet`. Named, the search sees those modules
and nothing else — the same names the code the model writes can resolve. Empty, it
sees the whole project.

The **query type selects the mode**, exactly as in `search_documentation` — a
`String` is keywords, a `Regex` is a pattern (the exact-name bonus does not apply
to a regex; ranking is by where it matches).
"""
function search_api(query::Union{AbstractString,Regex}; kind = nothing, limit::Integer = 8,
                    api = ApiEntry[])
    patterns, fold = _matchers(query)
    isempty(patterns) && return "Provide a search query (two or more characters)."
    scored = Tuple{Tuple{Int,Int},_ApiEntry}[]
    for e in _api_index(api)
        (kind === nothing || e.kind == kind) || continue
        s = _api_score(patterns, e, fold)
        (s[1] > 0 || s[2] > 0) && push!(scored, (s, e))
    end
    # **A miss answers what there IS.** A search that says only "no match" costs a
    # round and teaches nothing, and the round after it is a guess. The names of
    # the declaration are short, and they are the answer to "then what may I
    # write?" — so they are said here, where the question was asked, rather than
    # carried in every prompt.
    if isempty(scored)
        suffix = kind === nothing ? "" : " (kind=$kind)"
        names = isempty(api) ? "" : describe_api(api; signatures = false)
        return "No API matches $(repr(query))$suffix." *
               (isempty(names) ? "" : "\n\nWhat you may write:\n\n" * names)
    end
    # **A tie goes to the shorter name.** `run_simulations` and
    # `run_simulations_in_conversation` both hold every word of "run simulation",
    # and the first is what the words say; the second says them and more. Length
    # is the whole of that difference, so it is the tie-break.
    sort!(scored; by = x -> (-x[1][1], -x[1][2], length(x[2].qualname)))

    # **One clear answer is answered in full.** A hit shows its signature and a
    # locator, and a model that wanted the verb then spends a whole round calling
    # that locator. When the search has already decided — one hit, or one hit
    # whose name is what was asked — the documentation comes back with it and
    # that round is not spent. Measured 2026-09-13: half of a turn's tool calls
    # were this lookup pair.
    best = scored[1]
    # One hit, or one whose NAME is exactly what was asked while no other's is.
    alone = length(scored) == 1 || (best[1][1] >= 100 && scored[2][1][1] < 100)
    if alone && !isempty(best[2].full)
        io = IOBuffer()
        println(io, "# `$(best[2].qualname)` — the one API match for $(repr(query))\n")
        println(io, best[2].full)
        rest = [e.qualname for (_, e) in scored[2:min(limit, length(scored))]]
        isempty(rest) ||
            println(io, "\nAlso matched, by name: " * join(rest, ", ") * ".")
        return String(take!(io))
    end

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
