# Fragment of `ToolModule` — reading and searching the project's own
# documentation: the guides on disk, and the API (modules / types / functions)
# reachable by reflection.
#
# These are read-only and derived from source that does not change while the
# process runs, which is why the two indexes below may be process-global caches.

# ═══════════════════════════════════════════════════════════════════════
# Guides
# ═══════════════════════════════════════════════════════════════════════

# The roots an application added, in the order it added them. A window built on
# this editor has guides of its own — how to run a simulation, what a result
# frame holds — and without them the only documentation a model can read is the
# editor's own. Measured 2026-09-13: asked to plot a result, a model searched the
# documentation and was answered with `CellVector` and `@document`.
const _EXTRA_GUIDE_ROOTS = Tuple{String,String}[]

"""
    register_guide_root!(directory; prefix = "") -> Nothing

Add a tree of markdown guides to what `search_guides` reads and
`resource://guide/…` names.

`prefix` goes in front of every guide name found under it, so two applications
may both have a guide called `getting-started`.

**An application registers its own at load.** The editor's guides are about the
editor; a window built on it has guides about the window, and a model that can
read only the first has been handed a library about the wrong subject.
"""
function register_guide_root!(directory::AbstractString; prefix::AbstractString = "")
    entry = (String(directory), String(prefix))
    entry in _EXTRA_GUIDE_ROOTS && return nothing
    push!(_EXTRA_GUIDE_ROOTS, entry)
    # The index is built once and cached; a root added after that must be seen.
    _GUIDE_INDEX[] = nothing
    nothing
end

"""
    _get_bundle_directory(bindir = Sys.BINDIR) -> Union{String,Nothing}

The folder `share/projectured/` beside the running executable, or `nothing`.
A binary that a build made has this folder, and the folder holds the files that
the binary reads while it runs. A Julia session has no such folder, and it reads
those files in the checkout.
"""
function _get_bundle_directory(bindir::AbstractString = Sys.BINDIR)
    directory = normpath(joinpath(bindir, "..", "share", "projectured"))
    isdir(directory) ? directory : nothing
end

# The guides of the editor: `documentation/` in the bundle of a binary, or in
# the checkout, three levels above this file.
function _get_documentation_directory(bundle = _get_bundle_directory())
    bundled = bundle === nothing ? "" : joinpath(bundle, "documentation")
    isdir(bundled) ? bundled : normpath(joinpath(@__DIR__, "..", "..", "..", "documentation"))
end

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
    documentation = _get_documentation_directory()
    roots = Tuple{String,String}[(documentation, "")]
    pkg_dir = joinpath(documentation, "package")
    if isdir(pkg_dir)
        for pkg in sort(readdir(pkg_dir))
            d = joinpath(pkg_dir, pkg)
            isdir(d) && push!(roots, (d, "$pkg/"))
        end
    end
    append!(roots, _EXTRA_GUIDE_ROOTS)
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
        # The first paragraph after the title is the description. The header
        # line of a document — `> **Kind:** … **Status:** … **Stands on:** …` —
        # sits between the two, and it is metadata: a model that reads it
        # learns the kind of the document and nothing about its subject. So a
        # quoted line is skipped, and the paragraph after it is the summary
        # that `writing-rules.md` asks every document to carry.
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
            elseif startswith(stripped, ">")
                continue
            elseif seen_heading
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
    # A module two entries name gives the names of both.
    any(entry -> entry.module_ === mod && name in get_api_entry_names(entry), api)
end

# The module the declaration gives `name` in, or `nothing`.
function _find_declaring_module(api, name::Symbol)
    for entry in api
        name in get_api_entry_names(entry) && return entry.module_
    end
    nothing
end

# What a reader answers for a name the URI puts under the wrong module: a model
# guesses the module of a verb it found, and the guess is often the window's
# verbs module. The name is declared, so the answer says where, and the URI
# that reads it, rather than that it is not one of the names.
function _say_not_declared(kind::AbstractString, name::AbstractString, module_name,
                           api, shape::AbstractString)
    owner = _find_declaring_module(api, Symbol(name))
    owner === nothing && return "$kind '$name' is not one of the names you may write."
    owner_name = String(nameof(owner))
    "$kind '$name' is not in module '$module_name'. It is declared in '$owner_name': " *
        "read `resource://$shape/$owner_name/$name`."
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

**The first paragraph is the signature**, not the description: Julia strips a
docstring's common indentation before it is stored, so the indented signature
block arrives flush left. A hit shows it, and `_read_doc_heading` reads the
sentence under it; but scored on the signature alone, no word of the
description is searchable, and a verb is reachable only through its name.

Two paragraphs, not the whole text: the sentence under the signature is where a
docstring says what the thing does, and the rest is detail that would only blur
the ranking. **And the "Use it to" paragraph**, wherever it stands: a declared
name says there what a person wants it for, in the person's words, which is what
a person then searches for.
"""
function _search_text(doc::AbstractString)
    isempty(doc) && return ""
    paragraphs = String[]
    for lines in _split_doc_paragraphs(doc)
        paragraph = join(strip.(lines), " ")
        isempty(paragraph) && continue
        if length(paragraphs) < 2
            push!(paragraphs, paragraph)
        elseif startswith(paragraph, "Use it to")
            push!(paragraphs, paragraph)
            break
        end
    end
    join(paragraphs, " ")
end

# ── What a docstring opens with ───────────────────────────────────────────────
#
# A hit and a catalogue line show a signature and a sentence. A docstring here
# opens with an indented signature block and then says what the thing does, and
# `_first_paragraph` answers the block, so these read the two apart.

# The paragraphs of a docstring, each as its lines. A blank line ends a
# paragraph, except inside a fenced code block, which is one paragraph.
function _split_doc_paragraphs(doc::AbstractString)
    paragraphs = Vector{String}[]
    current = String[]
    fenced = false
    for line in split(doc, '\n')
        startswith(strip(line), "```") && (fenced = !fenced)
        if !fenced && isempty(strip(line))
            isempty(current) || (push!(paragraphs, current); current = String[])
        else
            push!(current, String(line))
        end
    end
    isempty(current) || push!(paragraphs, current)
    paragraphs
end

# The lines of a paragraph, without the fence around them.
_get_unfenced_lines(lines::Vector{String}) =
    length(lines) >= 2 && startswith(strip(lines[1]), "```") &&
    startswith(strip(lines[end]), "```") ? lines[2:end-1] : lines

# Whether a paragraph is the signature of `name`, or the name alone, which is
# how a docstring opens.
function _is_signature_paragraph(lines::Vector{String}, name::AbstractString)
    inner = _get_unfenced_lines(lines)
    isempty(inner) && return false
    line = strip(first(inner))
    # A constant's signature says its type: `Fill -> SizePolicy`.
    line == name || startswith(line, name * "(") || startswith(line, name * "{") ||
        startswith(line, name * " ->") ||
        (startswith(name, "@") && startswith(line, name * " "))
end

# Whether a paragraph is prose: not code, a heading, a table, a list, a quote or
# an admonition.
function _is_prose_paragraph(lines::Vector{String})
    line = first(lines)
    startswith(line, "    ") && return false
    stripped = lstrip(line)
    !any(prefix -> startswith(stripped, prefix), ("```", "#", "|", "!!!", "- ", "* ", "+ ", ">")) &&
        !occursin(r"^\d+\. ", stripped)
end

# The first signature of a signature paragraph, as one line. A third-party
# docstring runs several together, and a hit shows one.
function _get_first_signature(lines::Vector{String}, name::AbstractString; limit::Int = 200)
    text = replace(join(strip.(_get_unfenced_lines(lines)), ' '), r"\s+" => " ")
    cuts = [first(found) for found in (findnext(" " * name * "(", text, 1),
                                        findnext(" " * name * "{", text, 1))
            if found !== nothing]
    isempty(cuts) || (text = rstrip(text[1:prevind(text, minimum(cuts))]))
    length(text) > limit ? first(text, limit - 1) * "…" : String(text)
end

# A prose paragraph as one line without bold: its first sentence, or all of it.
# A sentence ends at `.`, `!` or `?` after two word characters, before a capital,
# a backtick, a `*`, an `_` or a bracket, so "e.g." ends none.
function _get_prose_text(lines::Vector{String}; whole::Bool, limit::Int)
    text = replace(replace(join(strip.(lines), ' '), "**" => ""), r"\s+" => " ")
    if !whole
        found = match(r"^.*?(?<=[\w`)\]]{2})[.!?](?=\s+[A-Z`*_(\[])", text)
        found === nothing || (text = found.match)
    end
    length(text) > limit ? first(text, limit - 1) * "…" : String(text)
end

"""
    _read_doc_heading(doc, source, shown = source; whole = false) -> (signature, summary)

What a docstring opens with: its first signature, and the first sentence of its
first prose paragraph, or that whole paragraph with `whole`. The signature is
empty when the docstring opens without one, and both are empty for no docstring.

`source` is the name the docstring uses, and `shown` the name the signature
shows; they differ where a declaration renamed a function.
"""
function _read_doc_heading(doc::AbstractString, source::AbstractString,
                           shown::AbstractString = source; whole::Bool = false)
    paragraphs = _split_doc_paragraphs(doc)
    signature = ""
    if !isempty(paragraphs) && _is_signature_paragraph(paragraphs[1], source)
        signature = _get_first_signature(paragraphs[1], source)
        source == shown || (signature = shown * chop(signature; head = length(source), tail = 0))
        paragraphs = paragraphs[2:end]
    end
    prose = findfirst(_is_prose_paragraph, paragraphs)
    summary = prose === nothing ? "" :
        _get_prose_text(paragraphs[prose]; whole = whole, limit = whole ? 400 : 160)
    (signature, summary)
end

# The paragraph a catalogue line shows for `name`.
function _get_catalogue_summary(doc::AbstractString, name::AbstractString)
    isempty(strip(doc)) && return "No documentation available."
    summary = last(_read_doc_heading(doc, name; whole = true))
    isempty(summary) ? "No description." : summary
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
        summary = _get_catalogue_summary(_doc_string(mod), String(name))
        structs = [String(n) for (n, _) in _struct_types(mod)]
        struct_list = isempty(structs) ? "" : "\n\nTypes: $(join(structs, ", "))"
        push!(modules_info, "**$name**: $summary$struct_list")
    end
    isempty(modules_info) && return "No modules found."
    "Available Modules\n\n" * join(modules_info, "\n\n---\n\n")
end

# The names of `mod` that a declaration gives, or `nothing` when no declaration
# narrows the module: an empty API is the whole surface. A module that two
# entries name gives the names of both.
function _find_declared_names(mod::Module, api)
    isempty(api) && return nothing
    given = Set{Symbol}()
    for entry in api
        entry.module_ === mod || continue
        union!(given, get_api_entry_names(entry))
    end
    given
end

"""
    list_types(module_name; api = ApiEntry[]) -> String

List the types within a module with their one-paragraph documentation. With a
declared `api`, the module is looked up among the declared ones, and only the
types the declaration gives are listed, which are the ones a model can write.
"""
function list_types(module_name; api = ApiEntry[])
    mod = _find_module(String(module_name), api)
    isnothing(mod) && return "Module '$module_name' not found."
    declared = _find_declared_names(mod, api)
    types_info = String[]
    for (name, T) in _struct_types(mod)
        declared === nothing || name in declared || continue
        summary = _get_catalogue_summary(_doc_string(T), String(name))
        mutable_str = ismutabletype(T) ? "mutable " : ""
        push!(types_info, "**$mutable_str$name**: $summary")
    end
    isempty(types_info) && return "No types found in module '$module_name'."
    join(types_info, "\n\n")
end

"""
    list_functions(module_name, type_name = nothing; api = ApiEntry[]) -> String

List the functions within a module (optionally only those mentioning
`type_name` in a signature) with their one-paragraph documentation. With a
declared `api`, the module is looked up among the declared ones, and only the
functions the declaration gives are listed, which are the ones a model can call.
"""
function list_functions(module_name, type_name = nothing; api = ApiEntry[])
    mod = _find_module(String(module_name), api)
    isnothing(mod) && return "Module '$module_name' not found."
    declared = _find_declared_names(mod, api)
    functions_info = String[]
    for (name, fn) in _module_functions(mod)
        declared === nothing || name in declared || continue
        if type_name !== nothing && !any(occursin(type_name, string(m.sig)) for m in methods(fn))
            continue
        end
        summary = _get_catalogue_summary(_doc_string(fn), String(name))
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
        return _say_not_declared("Type", String(type_name), module_name, api, "type")
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
        return _say_not_declared("Function", func_name, module_name, api, "function")
    # A declaration may have renamed it, and the module knows it by its own name.
    sym = api_source_name(api, mod, sym)
    isdefined(mod, sym) ||
        return "Function '$function_signature' not found in module '$module_name'."
    doc = _doc_string(getfield(mod, sym))
    isempty(doc) && return "No documentation available for '$function_signature'."
    doc
end

"""
    read_value_documentation(module_name, name; api = ApiEntry[]) -> String

The docstring of a declared constant — a name that is neither a type nor a
function, such as a size policy — read by the binding that holds it.
"""
function read_value_documentation(module_name, name; api = ApiEntry[])
    mod = _find_module(String(module_name), api)
    isnothing(mod) && return "Module '$module_name' not found."
    sym = Symbol(name)
    _is_declared(api, mod, sym) ||
        return _say_not_declared("Value", String(name), module_name, api, "value")
    sym = api_source_name(api, mod, sym)
    isdefined(mod, sym) || return "Value '$name' not found in module '$module_name'."
    doc = _binding_doc(mod, sym)
    isempty(doc) && return "No documentation available for '$name'."
    doc
end

# ═══════════════════════════════════════════════════════════════════════
# Search
# ═══════════════════════════════════════════════════════════════════════
#
# Two read-only search functions, so a caller can find the right guide section or
# API entry in one call instead of listing and reading every resource.

# Count how often each term occurs in `text`, which is folded already, and scale
# the count by `weight`. A term counts its best form once.
function _term_score(terms, text::AbstractString, weight::Int)
    isempty(text) && return 0
    score = 0
    for term in terms
        score += weight * maximum(length(findall(form, text)) for form in term.forms)
    end
    score
end

# A short, whitespace-collapsed excerpt of `body` centred on the first match.
function _excerpt(body::AbstractString, terms, fold; width::Int = 240)
    isempty(body) && return ""
    fb = fold(body)
    pos = nothing
    for term in terms, form in term.forms
        r = findfirst(form, fb)
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
    kind::String       # "module" | "type" | "function"
    qualname::String   # "Mod" or "Mod.Name"
    signature::String  # what a hit shows first: its first signature, or nothing
    summary::String    # what a hit shows under it: the first sentence of its description
    text::String       # what a hit is SCORED on: the signature and the description
    full::String       # the whole documentation, for a search that answers one thing
end

# An entry named `qualname`, read from its documentation. `source` is the name the
# documentation uses, which a declaration can have renamed; every text of the
# entry then shows the name the model writes.
function _make_api_entry(kind::String, qualname::String, doc::AbstractString,
                         source::AbstractString = last(split(qualname, '.')))
    shown = String(last(split(qualname, '.')))
    doc = source == shown ? String(doc) : _rename_signature_paragraph(doc, source, shown)
    signature, summary = _read_doc_heading(doc, shown)
    _ApiEntry(kind, qualname, signature, summary, _search_text(doc), doc)
end

# The docstring with `shown` in place of `source` in its signature paragraph, and
# nowhere else: the prose keeps its words, and a model that copies the signature
# writes a name it may write.
function _rename_signature_paragraph(doc::AbstractString, source::AbstractString,
                                     shown::AbstractString)
    paragraphs = _split_doc_paragraphs(doc)
    (isempty(paragraphs) || !_is_signature_paragraph(paragraphs[1], source)) && return String(doc)
    pattern = Regex("(?<![\\w!@])" * escape_string(source) * "(?=[({\\s]|\$)")
    renamed = [replace(line, pattern => shown) for line in paragraphs[1]]
    join(vcat([join(renamed, '\n')], [join(lines, '\n') for lines in paragraphs[2:end]]), "\n\n")
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
            signature = first(_read_doc_heading(_binding_doc(mod, source), String(source), text))
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

# The names `@document` writes beside a schema: one per storage kind, `ACFoo`,
# `RCFoo`, `ICFoo`, `MCFoo`, `DCFoo` and `AFoo`, and the struct of the native
# layout, `MFoo` or `IFoo`. The macro exports them all, so a declaration of a
# module holds them all.
const _SCHEMA_PREFIXES = ("AC", "RC", "IC", "MC", "DC", "A", "M", "I")

# Whether `name` is one of those. It is a variant when the name is a prefix and
# a type that the same module has: `ACCellVector` beside `CellVector`. The check
# of the base name is what keeps `Action`, whose "A" is a letter of a word.
#
# **A variant is not a hit.** It carries no documentation of its own — 281 of
# projectured's 1,584 declared types had a sentence, and 790 of them were
# variants — and it stands for a type that is a hit already. Measured
# 2026-09-18: they are a third of a whole-module corpus, 2,355 entries against
# 1,389, and every vector, every listing and every index costs that third. They
# did not change where the golden names ranked, because a name with no words of
# its own answers no query; what they cost is the work and what a listing of
# names shows.
# A name that opens with an underscore is the module's own business, whatever it
# exports. A caller does not write one, so a search does not answer one.
_is_private_name(name::Symbol) = startswith(String(name), "_")

function _is_schema_variant(mod::Module, name::Symbol, value)
    value isa Type || return false
    written = String(name)
    for prefix in _SCHEMA_PREFIXES
        startswith(written, prefix) || continue
        length(written) > length(prefix) || continue
        base = Symbol(written[length(prefix) + 1:end])
        isdefined(mod, base) && getfield(mod, base) isa Type && return true
    end
    false
end

function _index_declared(api)
    entries = _ApiEntry[]
    indexed = Set{Module}()
    # What a name the model writes already resolved to. A module that re-exports
    # another's name gives the same binding, and one binding is one hit.
    bound = Dict{Symbol,Any}()
    for declared in api
        mod = declared.module_
        mn = String(nameof(mod))
        # A module two entries name is one module, and one hit.
        mod in indexed || push!(entries, _make_api_entry("module", mn, _doc_string(mod)))
        push!(indexed, mod)
        # The names the declaration gives, and no others. A name a model finds
        # here is a name it can write, which is the whole point of the list.
        # Indexed under the name the MODEL writes, and read from the module by
        # the name the module knows: a renamed entry is found by the word the
        # model would type, and its documentation is still its own.
        for (source, sym) in api_entry_bindings(declared)
            sym === nameof(mod) && continue
            isdefined(mod, source) || continue
            _is_private_name(sym) && continue
            value = getfield(mod, source)
            _is_schema_variant(mod, source, value) && continue
            get(bound, sym, nothing) === value && continue
            bound[sym] = value
            qualname = "$mn." * String(sym)
            doc = _binding_doc(mod, source)
            if value isa Type
                push!(entries, _make_api_entry("type", qualname, doc, String(source)))
            elseif value isa Function
                push!(entries, _make_api_entry("function", qualname, doc, String(source)))
            else
                # A constant the model writes as it is: a size policy, a default.
                push!(entries, _make_api_entry("value", qualname, doc, String(source)))
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
        push!(entries, _make_api_entry("module", mn, _binding_doc(proj, mod_sym)))
        for (type_sym, type_value) in _struct_types(mod)
            (_is_private_name(type_sym) || _is_schema_variant(mod, type_sym, type_value)) &&
                continue
            push!(entries, _make_api_entry("type", "$mn.$type_sym", _binding_doc(mod, type_sym)))
        end
        # A function has no resource of its own: a resource per function fans out
        # to hundreds, so a hit is read with `read_function_documentation`.
        for (function_sym, _) in _module_functions(mod)
            _is_private_name(function_sym) && continue
            push!(entries, _make_api_entry("function", "$mn.$function_sym",
                                           _binding_doc(mod, function_sym)))
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
# The indexes are built on first use, and the task that computes meaning vectors
# reads them too, so one lock guards the building.
const _INDEX_LOCK = ReentrantLock()

function _guide_index()
    lock(_INDEX_LOCK) do
        _GUIDE_INDEX[] === nothing && (_GUIDE_INDEX[] = _index_guide_sections())
        _GUIDE_INDEX[]
    end
end

function _api_index(api = ApiEntry[])
    lock(_INDEX_LOCK) do
        isempty(api) || return get!(() -> _index_declared(api),
                                    _DECLARED_INDEX, collect(ApiEntry, api))
        _API_INDEX[] === nothing && (_API_INDEX[] = _index_api())
        _API_INDEX[]
    end
end

"""
    search_guides(query; mode = "keywords", detail = "summary", limit = nothing,
                  meaning_model = nothing) -> String

Search the guides. They are split into sections at their headings, and the hits
are sections, each with the URI `read_resource` reads it by:
`resource://guide/<name>#<heading>`.

`detail` says how much a hit shows, and sets the `limit` a caller does not:
`"names"` is one line each, the URI and the heading, 25 of them; `"summary"`, the
default, adds an excerpt, 8 of them; `"full"` is the whole section, 3 of them.
An answer that is long ends with what to do next.

`mode` says how a `String` query is read:

- `"keywords"`, the default — words, read by [`parse_keyword_query`](@ref):
  `+word` must match, `-word` must not, `a|b` is either, and `"two words"` is a
  phrase. A section ranks by its heading first and by its body second.
- `"regex"` — a regular expression, matched against the text as it is written;
  a `(?i)` prefix ignores case. A `Regex` query is read this way in every mode.
- `"description"` — a sentence that says what the reader wants to do. The words
  of the sentence rank the sections as keywords do, and `meaning_model` ranks
  them by what the sentence means; the two ranks are merged, and the words count
  twice. Without a meaning model, or when it fails, the words alone rank them,
  and the first line of the answer says why.

A query that can not be read answers the reason as text, and never throws.
"""
function search_guides(query::Union{AbstractString,Regex}; mode = "keywords",
                       detail = "summary", limit = nothing, meaning_model = nothing)
    read = _read_search_query(query, mode)
    read isa String && return read
    level = _read_search_detail(detail)
    haskey(_DETAIL_LIMITS, level) || return level
    refusal = _find_query_refusal(read)
    refusal === nothing || return refusal
    sections = _guide_index()
    ranked = _GuideSection[section for (_, section) in _rank_guide_sections(read, sections)]
    note = nothing
    if read isa _DescriptionQuery
        by_meaning, note = _rank_guide_sections_by_meaning(read, sections, meaning_model)
        by_meaning === nothing ||
            (ranked = _fuse_rankings(ranked, by_meaning; word_weight = _GUIDE_WORD_WEIGHT))
    end
    isempty(ranked) && return _prefix_note(note, "No documentation matches $(repr(query)).\n" *
                                                 "A verb may do it: `search_api` with the same words.")
    terms = _get_scored_terms(read)
    fold = _get_query_fold(read)
    io = IOBuffer()
    note === nothing || println(io, note, "\n")
    println(io, "# Documentation matches for $(repr(query))\n")
    shown = first(ranked, min(_get_hit_count(level, limit), length(ranked)))
    for section in shown
        head = isempty(section.heading) ? "" : " — $(section.heading)"
        if level == "names"
            println(io, "- ", _get_section_uri(section), head)
        elseif level == "summary"
            println(io, "## ", _get_section_uri(section), head)
            println(io, _excerpt(section.body, terms, fold))
            println(io)
        else
            println(io, "## ", _get_section_uri(section), head, "\n")
            println(io, section.body, "\n")
        end
    end
    body = String(take!(io))
    body * _make_footer(_get_section_uri(first(shown)), length(body); what = "a section")
end

# The sections a query finds, best first, each with its two scores.
#
# **Two numbers, as in `search_api`.** A heading is what a section is about and a
# body is where words happen to fall, so the heading decides and the body only
# separates what it could not. Added into one number, the longest document wins:
# "change the layout" answered `design/system-anatomy` while a guide held a
# section of that name. Measured 2026-09-13.
function _rank_guide_sections(query, sections::Vector{_GuideSection})
    terms = _get_scored_terms(query)
    fold = _get_query_fold(query)
    scored = Tuple{Tuple{Int,Int},_GuideSection}[]
    for section in sections
        heading = fold(section.heading)
        body = fold(section.body)
        _is_passing(query, heading, body) || continue
        heading_score = _term_score(terms, heading, 5)
        body_score = _term_score(terms, body, 1)
        (heading_score > 0 || body_score > 0) &&
            push!(scored, ((heading_score, body_score), section))
    end
    sort!(scored; by = x -> (-x[1][1], -x[1][2]))
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
#
# Every text is folded already.
# The words of an identifier: `open_pane!` is "open" and "pane", `WidgetCard` is
# "widget" and "card", and `HTTPServer` is "http" and "server".
function _split_identifier_words(name::AbstractString)
    spaced = replace(String(name), r"([a-z0-9])([A-Z])" => s"\1 \2")
    spaced = replace(spaced, r"([A-Z]+)([A-Z][a-z])" => s"\1 \2")
    String[lowercase(word) for word in split(spaced, r"[^A-Za-z0-9]+") if !isempty(word)]
end

# **A word of a name is not a piece of one.** A term that is a whole word of the
# name is what a person said — "card" in `WidgetCard` — and a term that merely
# falls inside it is often another word: "card" inside `discard`, "run" inside
# `trundle`. The word scores above the piece, and both below the whole name.
_compute_name_score(written, name::AbstractString, words::Vector{String},
                    qualified::AbstractString) =
    (written isa AbstractString && name == written) ? 100 :
    (written isa AbstractString && written in words) ? 30 :
    occursin(written, name) ? 20 :
    occursin(written, qualified) ? 10 : 0

# The entries a query finds, best first, each with its two scores.
#
# **A tie goes to the shorter name.** `run_simulations` and
# `run_simulations_in_conversation` both hold every word of "run simulation", and
# the first is what the words say; the second says them and more. Length is the
# whole of that difference, so it is the tie-break.
# What a word is worth in the prose, by the rule search engines call BM25: a word
# that few entries hold is worth more than one that most of them hold, a second
# occurrence in one entry is worth less than the first, and a long text earns no
# score for being long.
#
# **At a hundred names a count was enough; at a thousand it is not.** Measured
# 2026-09-18 on the corpus of 1,389 names: "make a field of a document computed"
# never reached `set_cell_computation!`, because "document" stands in hundreds of
# entries and counted as loudly as "computed", which stands in a few.
const _WORD_SATURATION = 1.2
const _LENGTH_WEIGHT = 0.75

function _rank_api_entries(query, entries::Vector{_ApiEntry})
    terms = _get_scored_terms(query)
    fold = _get_query_fold(query)
    kept = _ApiEntry[]
    named = Int[]
    counts = Vector{Vector{Int}}()
    lengths = Float64[]
    for entry in entries
        qualified = fold(entry.qualname)
        prose = fold(entry.text)
        _is_passing(query, qualified, prose) || continue
        name_score = 0
        words = _split_identifier_words(last(split(entry.qualname, '.')))
        short = last(split(qualified, '.'))
        for term in terms
            name_score += maximum(_compute_name_score(written, short, words, qualified)
                                  for written in term.written)
        end
        term_counts = Int[maximum(length(findall(form, prose)) for form in term.forms)
                          for term in terms]
        (name_score > 0 || any(>(0), term_counts)) || continue
        push!(kept, entry)
        push!(named, name_score)
        push!(counts, term_counts)
        push!(lengths, max(1.0, Float64(length(prose))))
    end
    isempty(kept) && return Tuple{Tuple{Int,Float64},_ApiEntry}[]
    average = sum(lengths) / length(kept)
    holders = Int[count(one -> one[index] > 0, counts) for index in eachindex(terms)]
    scored = Tuple{Tuple{Int,Float64},_ApiEntry}[]
    for place in eachindex(kept)
        said = 0.0
        for index in eachindex(terms)
            frequency = counts[place][index]
            frequency == 0 && continue
            rarity = log(1 + (length(kept) - holders[index] + 0.5) / (holders[index] + 0.5))
            said += rarity * frequency * (_WORD_SATURATION + 1) /
                    (frequency + _WORD_SATURATION *
                     (1 - _LENGTH_WEIGHT + _LENGTH_WEIGHT * lengths[place] / average))
        end
        push!(scored, ((named[place], said), kept[place]))
    end
    sort!(scored; by = x -> (-x[1][1], -x[1][2], length(x[2].qualname)))
end

_prefix_note(note, text::AbstractString) = note === nothing ? String(text) : note * "\n\n" * text

# ── How much a hit shows ────────────────────────────────────────────────────
#
# `detail` is `"names"`, `"summary"` or `"full"`, the same on both searches. A
# model that wants the lie of the land asks for names; one that has narrowed the
# search asks for full. Each level has a limit of its own, because one whole
# docstring costs what twenty names cost.
const _DETAIL_LIMITS = Dict("names" => 25, "summary" => 8, "full" => 3)

# The detail a search was asked for, as a tool argument spells it, or the reason
# it can not be read. A missing detail is the summary.
function _read_search_detail(detail)
    name = detail === nothing || isempty(strip(string(detail))) ? "summary" :
           lowercase(strip(string(detail)))
    haskey(_DETAIL_LIMITS, name) && return name
    "Unknown search detail " * repr(name) * ". The details are \"names\", \"summary\" and \"full\"."
end

_get_hit_count(detail::String, limit) = limit === nothing ? _DETAIL_LIMITS[detail] : Int(limit)

# ── What to do next ─────────────────────────────────────────────────────────
#
# An answer over `_FOOTER_THRESHOLD` characters ends with the actions that apply,
# and a shorter one ends with none: the instructions live in the answers that
# need them, and not in a tool description that is sent with every request. The
# rules are here and nowhere else, so a footer never names a tool that is not
# registered — a model was once told in prose to call a tool that did not exist,
# and it stopped writing code (measured 2026-09-13).
const _FOOTER_THRESHOLD = 600

const _NARROW_LINE =
    "Narrow the search with +word or -word, or say what you want done with mode \"description\"."

function _make_footer(first_uri::AbstractString, body_length::Int; what::AbstractString)
    body_length > _FOOTER_THRESHOLD || return ""
    "\nRead " * what * " in full: `read_resource(\"" * first_uri * "\")`.\n" * _NARROW_LINE * "\n"
end

# The URI a hit is read by. A function has no resource of its own, and its URI
# is read by its shape.
function _get_entry_uri(entry::_ApiEntry)
    parts = split(entry.qualname, '.')
    entry.kind == "module" && return "resource://module/" * entry.qualname
    "resource://" * entry.kind * "/" * join(parts[1:end-1], '.') * "/" * String(last(parts))
end

_make_heading_slug(heading::AbstractString) =
    String(strip(replace(lowercase(heading), r"[^a-z0-9]+" => "-"), '-'))

_get_section_uri(section::_GuideSection) =
    "resource://guide/" * section.guide *
    (isempty(section.heading) ? "" : "#" * _make_heading_slug(section.heading))

# ── A resource read by the shape of its URI ─────────────────────────────────
#
# A section of a guide and a function have no resource of their own — one per
# section or per function would list in the hundreds — so `read_resource` reads
# them by the shape of the URI a search hit carries.
function _read_addressed_resource(set::ToolSet, uri::AbstractString)
    guide_prefix = "resource://guide/"
    function_prefix = "resource://function/"
    if startswith(uri, guide_prefix) && occursin('#', uri)
        guide, fragment = split(uri[nextind(uri, length(guide_prefix)):end], '#'; limit = 2)
        return _read_guide_section(String(guide), String(fragment))
    end
    if startswith(uri, function_prefix)
        parts = split(uri[nextind(uri, length(function_prefix)):end], '/')
        length(parts) == 2 || return nothing
        return read_function_documentation(String(parts[1]), String(parts[2]); api = set.api)
    end
    # A type a module re-exports has no resource of its own — the resources are
    # the types a module defines — and a constant never has one; both are read
    # by the shape a hit carries.
    for (prefix, reader) in (("resource://type/", read_type_documentation),
                             ("resource://value/", read_value_documentation))
        startswith(uri, prefix) || continue
        parts = split(uri[nextind(uri, length(prefix)):end], '/')
        length(parts) == 2 || return nothing
        return reader(String(parts[1]), String(parts[2]); api = set.api)
    end
    nothing
end

function _read_guide_section(guide::AbstractString, fragment::AbstractString)
    sections = _GuideSection[section for section in _guide_index() if section.guide == guide]
    isempty(sections) && return "Documentation '$guide' not found."
    wanted = _make_heading_slug(fragment)
    for section in sections
        _make_heading_slug(section.heading) == wanted &&
            return "## " * section.heading * "\n\n" * section.body * "\n"
    end
    "Section '$fragment' not found in guide '$guide'. Its sections: " *
        join(unique(section.heading for section in sections if !isempty(section.heading)), " · ") * "."
end

# A whole guide that is long ends with its sections, so the next read is one
# section and not the guide again.
function _add_guide_footer(guide::AbstractString, text::AbstractString)
    length(text) > _FOOTER_THRESHOLD || return String(text)
    headings = unique(section.heading for section in _guide_index()
                      if section.guide == guide && !isempty(section.heading))
    isempty(headings) && return String(text)
    String(text) * "\n\nSections: " * join(headings, " · ") * ". Read one with `read_resource(\"" *
        "resource://guide/" * guide * "#" * _make_heading_slug(first(headings)) * "\")`.\n"
end

"""
    describe_resources(set) -> String

The kinds of resource `set` offers, each with its count and how it is addressed:
what the `list_resources` tool answers. One line per kind, and not one per URI,
because a model reads this to learn the shapes, and a search hit carries the
URI it wants.
"""
function describe_resources(set::ToolSet)
    uris = [resource.uri for resource in list_resources(set)]
    count_of(prefix) = count(uri -> startswith(uri, prefix), uris)
    io = IOBuffer()
    println(io, "# Resources")
    println(io, "- 2 catalogues: `resource://guides`, every guide in one paragraph each, and ",
            "`resource://modules`, the modules you may call, with their types.")
    println(io, "- ", count_of("resource://guide/"), " guides: `resource://guide/<name>`; ",
            "one section of a guide: `resource://guide/<name>#<heading>`.")
    println(io, "- ", count_of("resource://module/"), " modules: `resource://module/<module>`.")
    println(io, "- ", count_of("resource://type/"), " types: `resource://type/<module>/<type>`.")
    println(io, "- a function: `resource://function/<module>/<name>`, ",
            "or `read_function_documentation(module, name)`; ",
            "a constant: `resource://value/<module>/<name>`.")
    println(io, "Find a section with `search_guides` and a name with `search_api`; ",
            "each hit carries its URI.")
    String(take!(io))
end

"""
    search_api(query; mode = "keywords", detail = "summary", kind = nothing, limit = nothing,
               api = ApiEntry[], meaning_model = nothing) -> String

Search modules, types, and functions by name and docstring. Ranks exact name
matches above name substrings above docstring matches and returns the top `limit`
hits. Each hit shows its signature, its kind and module, and the first sentence
of its description. `detail` says how much: `"names"` is the signature line only,
25 hits; `"summary"`, the default, adds the sentence, 8 hits; `"full"` is the
whole docstring, 3 hits; a `limit` given replaces the count. An answer that is
long ends with what to do next. Pass `kind` (`"module"`, `"type"`, or
`"function"`) to filter.

`api` is the declared API of a `ToolSet`. Named, the search sees those modules
and nothing else — the same names the code the model writes can resolve. Empty, it
sees the whole project.

`mode` reads the query exactly as in [`search_guides`](@ref): keywords by
default, a pattern with `"regex"` or a `Regex`, and a sentence with
`"description"`, which `meaning_model` ranks by meaning. The exact-name bonus is
for a written word only: a pattern ranks by where it matches.
"""
function search_api(query::Union{AbstractString,Regex}; mode = "keywords", detail = "summary",
                    kind = nothing, limit = nothing, api = ApiEntry[], meaning_model = nothing)
    read = _read_search_query(query, mode)
    read isa String && return read
    level = _read_search_detail(detail)
    haskey(_DETAIL_LIMITS, level) || return level
    refusal = _find_query_refusal(read)
    refusal === nothing || return refusal
    limit = _get_hit_count(level, limit)
    entries = _ApiEntry[entry for entry in _api_index(api)
                        if kind === nothing || entry.kind == kind]
    scored = _rank_api_entries(read, entries)
    ranked = _ApiEntry[entry for (_, entry) in scored]
    note = nothing
    if read isa _DescriptionQuery
        # **The meaning decides, and the words only stand in for it.** Merged,
        # the two ranks were worse than the meaning alone: a sentence's words
        # are "value", "runs" and "time", and they match a name that means
        # something else. Measured on the 88 verbs of a downstream IDE, 2026-09-16: of
        # the five weightings of a rank fusion that were tried, none put a verb
        # above where the meaning alone put it, and each put three or four of
        # eight test sentences' verbs below it.
        by_meaning, note = _rank_api_entries_by_meaning(read, entries, meaning_model)
        by_meaning === nothing || (ranked = by_meaning)
        # A sentence names no verb, so only a single hit is a clear answer.
        alone = length(ranked) == 1
    else
        # One hit, or one whose NAME is exactly what was asked while no other's is.
        alone = length(scored) == 1 ||
                (length(scored) > 1 && scored[1][1][1] >= 100 && scored[2][1][1] < 100)
    end
    # **A miss answers what there IS.** A search that says only "no match" costs a
    # round and teaches nothing, and the round after it is a guess. The names of
    # the declaration are short, and they are the answer to "then what may I
    # write?" — so they are said here, where the question was asked, rather than
    # carried in every prompt.
    if isempty(ranked)
        suffix = kind === nothing ? "" : " (kind=$kind)"
        names = isempty(api) ? "" : describe_api(api; signatures = false)
        return _prefix_note(note, "No API matches $(repr(query))$suffix. " *
                                  "A guide may say it: `search_guides` with the same words." *
                                  (isempty(names) ? "" : "\n\nWhat you may write:\n\n" * names))
    end

    # **One clear answer is answered in full.** A hit shows its signature and a
    # locator, and a model that wanted the verb then spends a whole round calling
    # that locator. When the search has already decided — one hit, or one hit
    # whose name is what was asked — the documentation comes back with it and
    # that round is not spent. Measured 2026-09-13: half of a turn's tool calls
    # were this lookup pair.
    best = ranked[1]
    io = IOBuffer()
    note === nothing || println(io, note, "\n")
    if alone && !isempty(best.full)
        println(io, "# `", last(split(best.qualname, '.')),
                    "` — the one API match for ", repr(query), "\n")
        println(io, best.full)
        rest = [entry.qualname for entry in ranked[2:min(limit, length(ranked))]]
        isempty(rest) ||
            println(io, "\nAlso matched, by name: " * join(rest, ", ") * ".")
        return String(take!(io))
    end

    println(io, "# API matches for $(repr(query))\n")
    shown = first(ranked, min(limit, length(ranked)))
    for entry in shown
        println(io, _format_api_hit(entry, level))
    end
    body = String(take!(io))
    body * _make_footer(_get_entry_uri(first(shown)), length(body); what = "one")
end

# A hit is two lines: what a caller writes, and what it does.
#
# **The signature first, and the name is in it.** A declared name arrives
# unqualified, and a hit that led with `Module.name` invited a caller to copy
# that shape: measured 2026-09-13, a model read
# `CampaignVerbsModule.select_simulations!`, wrote
# `PaneProgramModule.select_simulations!`, and lost the turn to an
# `UndefVarError`. The module follows the kind, as context.
function _format_api_hit(entry::_ApiEntry, level::String = "summary")
    parts = split(entry.qualname, '.')
    name = String(last(parts))
    head = isempty(entry.signature) ? name : entry.signature
    where = length(parts) > 1 ? " in " * join(parts[1:end-1], '.') : ""
    summary = isempty(entry.summary) ? "(no documentation)" : entry.summary
    level == "names" && return "- `" * head * "` — " * entry.kind * where
    level == "full" && return "## `" * head * "` — " * entry.kind * where * "\n\n" *
                              (isempty(entry.full) ? summary : entry.full) * "\n"
    "- `" * head * "` — " * entry.kind * where * "\n  " * summary
end

"""
    search_api(set::ToolSet, query; mode = "keywords", detail = "summary", kind = nothing,
               limit = nothing) -> String

Search what the tools of `set` search: its declared API, ranked by its meaning
model when it has one. This is what the `search_api` tool answers, so a call
from the REPL and a call from a model answer the same text.
"""
search_api(set::ToolSet, query::Union{AbstractString,Regex}; mode = "keywords",
           detail = "summary", kind = nothing, limit = nothing) =
    search_api(query; mode = mode, detail = detail, kind = kind, limit = limit, api = set.api,
               meaning_model = set.meaning_model)

"""
    search_guides(set::ToolSet, query; mode = "keywords", detail = "summary", limit = nothing) -> String

Search the guides as the tools of `set` search them, ranked by its meaning model
when it has one. This is what the `search_guides` tool answers.
"""
search_guides(set::ToolSet, query::Union{AbstractString,Regex}; mode = "keywords",
              detail = "summary", limit = nothing) =
    search_guides(query; mode = mode, detail = detail, limit = limit,
                  meaning_model = set.meaning_model)

# ── Tool-argument coercion ─────────────────────────────────────────────────
# A tool argument arrives from JSON, so it may be a number, a string, or nothing.

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

# The query of a search tool call. A value that is not text is read as its text,
# and a missing one is empty, which the search answers.
_get_query_argument(args) = string(something(get(args, "query", ""), ""))

# A limit a call gave, or `nothing`, which the detail level then decides.
_arg_limit(v) = v === nothing ? nothing : _arg_int(v, 8)
