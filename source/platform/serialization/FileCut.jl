# Fragment of `SerializationModule` — saving a set of files without a storage
# node in the document.
#
# A file reference is a fact about storage, so it lives in the file and never in
# the document. The document in memory is the real graph: a JSON object holds
# the XML element, a shared subtree is one object reached twice, a cycle is a
# cycle. Saving turns that graph into files by a walk that copies each file's
# content until it must cut, and at a cut writes a reference leaf in the file's
# own notation. The copy is a pure document of one domain, so the domain's
# natural notation prints it with no special rule.
#
# Two decisions come before any copy. Which file writes a node: a node is
# written in a file of its own domain, the first one that reaches it through
# nodes of that domain; anything else is an orphan and the save aborts. And how
# a node is named from another file: `file("b.xml")` for a file's root,
# `node(file("b.xml"), "children[1]")` for a node inside it, the path in the
# reference DSL's text form.

"""
    FileProject(base_dir, files)

The context a save and a load work in: the file documents, in order, and the
directory they live in. The files are handled together, because a reference
from one into another must know that the other exists and what it holds.
"""
mutable struct FileProject
    base_dir::String
    files::Vector{Any}
end

FileProject(base_dir::AbstractString, files::AbstractVector) =
    FileProject(String(base_dir), Any[files...])

"""
    FileCutException(message)

A save could not cut the graph into files: a node has no file to be written
into, or a single-file save met a cut it may not write.
"""
struct FileCutException <: Exception
    message::String
end

Base.showerror(io::IO, e::FileCutException) = print(io, e.message)

# ── What a file type contributes ──────────────────────────────────────────────

"""
    get_file_domain(::Type{<:FileDocument}) -> Type

The document type a file's content is made of: `JsonDocument` for a `JsonFile`.
Every file type defines it in one line. A node of that type is written in the
file; any other document is a cut.
"""
function get_file_domain end

"""
    is_file_domain_node(file, node) -> Bool

Whether `node` is one the file writes itself. The default asks
[`get_file_domain`](@ref); a file type whose domain is not one type overrides it.
"""
is_file_domain_node(file, node) = node isa get_file_domain(typeof(file))

"""
    is_written_in_file(file, node, name::Symbol) -> Bool

Whether the file writes the field `name` of `node`, and so whether the save
walks it. The default is `true`: a file writes the document it holds, whole.

A format whose notation writes a reduced form of a node says so here, and the
rest of that node is the document's own business. A `GestureLog` read from a
file holds the live entries it records, and nothing writes that: without this
the save would reach it, find no file of its domain, and call it an orphan.
"""
is_written_in_file(file, node, name::Symbol) = true

"""
    make_reference_leaf(file, marker::AbstractString) -> Document

The file's own spelling of a reference: a `JsonString` whose value is the
marker, a `pred:ref` element, a directive, a fence, a call. `marker` is the
marker body without its `<<` `>>`; the leaf writes them. Every file type defines
one.
"""
function make_reference_leaf end

"""
    find_reference_marker(node) -> Union{Nothing, String}

The marker body a reference leaf carries, or `nothing` for any other node. The
inverse of [`make_reference_leaf`](@ref); a load splices where this answers.
"""
find_reference_marker(::Any) = nothing

"The marker text of `body`, with its brackets."
make_marker_text(body::AbstractString) = _MARKER_OPEN * String(body) * _MARKER_CLOSE

# ── Ownership ────────────────────────────────────────────────────────────────

# `owner[node] = (file, path)` for every document node some file writes. A file
# walks its content through nodes of its own domain and stops at anything else:
# a node of another domain is that domain's to own, a file document is a cut, a
# node already owned stays with its first owner.
function _assign_owners(project::FileProject)
    owner = IdDict{Any,Tuple{Any,Reference}}()
    for file in project.files
        content = get_file_content(file)
        if is_own_content(file)
            # The file node is the root of its own tree, so it is what the file
            # writes rather than a cut: claim it here, and walk what it holds.
            haskey(owner, content) || (owner[content] = (file, EmptyReference()))
            for (steps, child) in _child_slots(content)
                is_written_in_file(file, content, _slot_field(steps)) || continue
                _own_walk!(owner, file, child, extend_reference(EmptyReference(), steps...))
            end
        else
            _own_walk!(owner, file, content, EmptyReference())
        end
    end
    owner
end

function _own_walk!(owner, file, node, path::Reference)
    node isa Document || return
    is_file_document(node) && return
    is_file_domain_node(file, node) || return
    haskey(owner, node) && return
    owner[node] = (file, path)
    for (steps, child) in _child_slots(node)
        is_written_in_file(file, node, _slot_field(steps)) || continue
        _own_walk!(owner, file, child, extend_reference(path, steps...))
    end
end

# The field a slot's steps start at.
_slot_field(steps::Tuple) = Symbol(first(steps).name)

# The document children of a node, each with the steps that reach it: a field
# holding a document is one step, an element of a collection field is two. A view
# state field, the selection and the mouse target, is state, not content, and is
# skipped.
function _child_slots(node::Document)
    slots = Tuple{Tuple,Any}[]
    for name in fieldnames(typeof(node))
        is_view_state_field(name) && continue
        raw = getfield(node, name)
        value = raw isa AbstractCell ? raw[] : raw
        if is_element_collection(value) || value isa AbstractVector
            for (index, element) in enumerate(value)
                element isa Document &&
                    push!(slots, ((FieldReferenceStep(string(name)), ElementReferenceStep(index)), element))
            end
        elseif value isa Document
            push!(slots, ((FieldReferenceStep(string(name)),), value))
        end
    end
    slots
end

# ── The cut ──────────────────────────────────────────────────────────────────

# The five rules, for the copy of `file`. `strict` is the single-file save: every
# cut is an error, because there is no context to refer into.
function _cut_copy(owner, file, node, path::Reference, visited::IdDict, strict::Bool)
    node isa Document || return node
    if is_file_document(node)
        return _cut_leaf(file, path, strict, "file(" * repr(get_filename(node)) * ")",
                         "holds the file document " * repr(get_filename(node)))
    end
    entry = get(owner, node, nothing)
    entry === nothing &&
        throw(FileCutException(_orphan_message(file, path, node, strict)))
    owner_file, owner_path = entry
    owner_file === file ||
        return _cut_leaf(file, path, strict, _reference_marker(owner_file, owner_path),
                         "holds a " * string(nameof(typeof(node))) * " that " *
                         repr(get_filename(owner_file)) * " writes")
    haskey(visited, node) &&
        return _cut_leaf(file, path, strict, _reference_marker(file, owner_path),
                         "holds the same " * string(nameof(typeof(node))) * " twice, at " *
                         print_path_text(owner_path) * " and at " * print_path_text(path))
    visited[node] = true
    _rebuild(owner, file, node, path, visited, strict)
end

# A reference leaf in the file's notation, or — in the strict mode — the error
# that says why the file cannot be saved alone.
function _cut_leaf(file, path, strict::Bool, marker::AbstractString, why::AbstractString)
    strict && throw(FileCutException(
        "save_file!: " * repr(get_filename(file)) * " " * why * " at " * print_path_text(path) *
        "; it needs a reference, and a file saved alone cannot write one — " *
        "save it in a FileProject"))
    make_reference_leaf(file, marker)
end

function _orphan_message(file, path, node, strict::Bool)
    what = string(nameof(typeof(node)))
    strict && return "save_file!: " * repr(get_filename(file)) * " holds a " * what *
                     " at " * print_path_text(path) * " that is not of its domain; it needs a " *
                     "reference, and a file saved alone cannot write one — save it in a FileProject"
    "save_project!: " * repr(get_filename(file)) * " reaches a " * what * " at " *
    print_path_text(path) * " that no file of its domain writes — put it in a file of its " *
    "domain, or under a node one of them reaches"
end

# Rebuild a node the way `copy_document` does, with every child cut. A cell keeps
# its kind; a collection field is rebuilt as the same kind of collection.
function _rebuild(owner, file, node, path::Reference, visited::IdDict, strict::Bool)
    T = typeof(node)
    args = Any[]
    for name in fieldnames(T)
        raw = getfield(node, name)
        value = raw isa AbstractCell ? raw[] : raw
        copied = name === :mouse_target ? nothing :
                 (name === :selection || !is_written_in_file(file, node, name)) ? value :
                 _cut_field(owner, file, name, value, path, visited, strict)
        push!(args, raw isa AbstractCell ? make_similar_cell(raw, copied) : copied)
    end
    Base.typename(T).wrapper(args...)
end

function _cut_field(owner, file, name::Symbol, value, path::Reference, visited::IdDict, strict::Bool)
    if is_element_collection(value)
        items = Any[_cut_copy(owner, file, element,
                              extend_reference(path, FieldReferenceStep(string(name)), ElementReferenceStep(index)),
                              visited, strict)
                    for (index, element) in enumerate(value)]
        # The list keeps the type of its elements, which its field declares.
        wrapper = Base.typename(typeof(value)).wrapper
        element_type = find_declared_element_type(value)
        return element_type === nothing ? wrapper(items) : wrapper{element_type}(items)
    elseif value isa AbstractVector
        return Any[_cut_copy(owner, file, element,
                             extend_reference(path, FieldReferenceStep(string(name)), ElementReferenceStep(index)),
                             visited, strict)
                   for (index, element) in enumerate(value)]
    elseif value isa Document
        return _cut_copy(owner, file, value, extend_reference(path, FieldReferenceStep(string(name))),
                         visited, strict)
    end
    value
end

# ── Naming a node from another file ──────────────────────────────────────────

# The reference DSL's text form: `entries[1].value`. `show` writes a field step
# with its leading dot; the DSL does not, so the first one goes.
"""
    print_path_text(path::Reference) -> String

`path` as the text of the reference DSL, without its types and without the dot
in front: `entries[2].value`. The empty path is the empty text.
[`parse_path_text`](@ref) reads it back when it holds field steps and element
indices only.
"""
print_path_text(path::Reference) =
    path isa EmptyReference ? "" : String(lstrip(string(strip_reference_types(path)), '.'))

# `file("b.xml")` for a root, `node(file("b.xml"), "children[1]")` for a node in it.
function _reference_marker(file, path::Reference)
    name = "file(" * repr(get_filename(file)) * ")"
    path isa EmptyReference ? name : "node(" * name * ", " * repr(print_path_text(path)) * ")"
end

# ── The two saves ────────────────────────────────────────────────────────────

"""
    save_project!(project::FileProject) -> Bool

Write every file of the project: cut its content, print the copy in the file's
natural notation, write it when the bytes changed. When a node has no file to be
written into, log the reason, write nothing, and return `false`.
"""
function save_project!(project::FileProject)
    owner = _assign_owners(project)
    texts = try
        Any[(file, _cut_text(owner, file, false)) for file in project.files]
    catch e
        e isa FileCutException || rethrow()
        @error e.message
        return false
    end
    _write_texts!(project.base_dir, texts)
    true
end

"""
    cut_file_text(file, base_dir = ".") -> String

The text that [`save_file!`](@ref) writes for `file` into `base_dir`: the graph
cut at the file, and printed in the notation of its file type. It writes
nothing. It throws a [`FileCutException`](@ref) where the save refuses.

Use it to compare a document with its file on disk.
"""
function cut_file_text(file, base_dir::AbstractString = ".")
    is_file_document(file) ||
        error("cut_file_text: not a file document (", typeof(file), ")")
    owner = _assign_owners(FileProject(base_dir, Any[file]))
    String(_cut_text(owner, file, true))
end

"""
    save_file!(file, base_dir) -> Bool

Write one file with no context, so no reference can be written: the content
must be a tree of the file's domain, with no foreign node, no shared subtree
and no cycle, or the save logs why and returns `false`. A marker that is a plain
leaf of the domain is a plain leaf, and saves as one.
"""
function save_file!(file, base_dir::AbstractString)
    is_file_document(file) ||
        error("save_file!: not a file document (", typeof(file), ")")
    text = try
        cut_file_text(file, base_dir)
    catch e
        e isa FileCutException || rethrow()
        @error e.message
        return false
    end
    _write_texts!(base_dir, Any[(file, text)])
    true
end

# One file's text: cut the graph, then print the copy in the file's own
# notation. Both halves can refuse — the cut at a node with no file, the
# notation at a value it cannot write — and both refuse before anything is
# written, so a save that cannot be finished leaves the directory as it was.
function _cut_text(owner, file, strict::Bool)
    content = get_file_content(file)
    visited = IdDict{Any,Bool}()
    if is_own_content(file)
        # The root is the file, so it is rebuilt rather than cut, and the copy is
        # already the file the notation prints.
        visited[content] = true
        return emit_text(_rebuild(owner, file, content, EmptyReference(), visited, strict))
    end
    emit_text(_with_content(file, _cut_copy(owner, file, content, EmptyReference(), visited, strict)))
end

function _write_texts!(base_dir::AbstractString, texts)
    mkpath(base_dir)
    for (file, text) in texts
        path = joinpath(base_dir, get_filename(file))
        parent = dirname(path)
        isempty(parent) || mkpath(parent)
        _write_if_changed(path, text)
    end
end

# A file of the same type and name whose content is `content`: what the domain's
# `emit_text` prints.
_with_content(file, content) = Base.typename(typeof(file)).wrapper(get_filename(file), content)
