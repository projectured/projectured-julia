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
# nodes of that domain; a node that no file of its domain reaches is written
# inline by a file that can write its text, as a `.pred` file writes a JSON value,
# and anything else is an orphan and the save aborts. And how a node is named
# from another file: `node(file("b.xml"), "children[1]")`, the path in the
# reference DSL's text form, and `node(file("b.xml"), "")` for a file's root.
# `file("b.xml")` names the file document itself.

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
into, or a file that the content holds has no name to write.
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

"""
    is_written_inline(file, node) -> Bool

Whether `file` writes `node`, a document of another domain that no file of the
set writes, in its own text: a `.pred` file writes a JSON value as the text of a
JSON file, inside a string tagged with the extension. The default is `false`, and
such a node is an orphan.
"""
is_written_inline(file, node) = false

"""
    make_inline_leaf(file, node, path::Reference) -> Document

The file's own spelling of `node`, a document that it writes inline, as
[`is_written_inline`](@ref) says, at `path`. It throws a
[`FileCutException`](@ref) where the text of the node can not be written.
"""
function make_inline_leaf end

"""
    find_held_file(node) -> file document or nothing

The file document that `node` stands for when another document holds it, or
`nothing`. A save writes `file("…")` there and walks no further into `node`. The
default answers `node` for a file document. A document that shows a file and
keeps the state of that showing, such as the view of a file, answers that file,
so a holder saves it as the file and writes none of that state.
"""
find_held_file(node) = is_file_document(node) ? node : nothing

# ── Ownership ────────────────────────────────────────────────────────────────

# `owner[node] = (file, path)` for every document node some file writes. A file
# walks its content through nodes of its own domain and stops at anything else:
# a node of another domain is that domain's to own, a file document is a cut, a
# node already owned stays with its first owner.
#
# A node is written at its owner path and named by a marker at every other place,
# so the owner path must be a place that the node itself fits. An element of a
# typed list, such as a formula of a formula sheet, fits there and a marker does
# not; so a node that a file holds in such a slot is owned at that slot, wherever
# the walk met it first. A second walk owns a node at its first place when the
# file holds its typed slot nowhere.
function _assign_owners(project::FileProject)
    owner = IdDict{Any,Tuple{Any,Reference}}()
    for file in project.files
        content = get_file_content(file)
        leaf_type = _find_reference_leaf_type(file)
        fixed = IdDict{Any,Bool}()
        leaf_type === nothing || _collect_fixed_nodes!(fixed, file, leaf_type, content, IdDict{Any,Bool}())
        for kept in (fixed, IdDict{Any,Bool}())
            if is_own_content(file)
                # The file node is the root of its own tree, so it is what the file
                # writes rather than a cut: claim it here, and walk what it holds.
                haskey(owner, content) || (owner[content] = (file, EmptyReference()))
                for (steps, child) in _child_slots(content)
                    is_written_in_file(file, content, _slot_field(steps)) || continue
                    _own_walk!(owner, file, child, extend_reference(EmptyReference(), steps...),
                               kept, leaf_type, _is_fixed_slot(leaf_type, content, steps))
                end
            else
                _own_walk!(owner, file, content, EmptyReference(), kept, leaf_type, false)
            end
        end
    end
    # A node that no file of its domain writes is the file's that reaches it first
    # and writes it inline, so a node of a format stays with the file of its format.
    for file in project.files
        _own_inline_walk!(owner, file, get_file_content(file), EmptyReference(), IdDict{Any,Bool}())
    end
    owner
end

# The nodes that `file` writes inline: each node of another domain that no file
# owns and that the walk meets through the nodes of `file`, at the place where
# `file` writes it. The walk does not go into such a node, whose own text holds
# what it holds.
function _own_inline_walk!(owner, file, node, path::Reference, visited::IdDict)
    node isa Document || return
    find_held_file(node) !== nothing && node !== get_file_content(file) && return
    haskey(visited, node) && return
    visited[node] = true
    entry = get(owner, node, nothing)
    if entry === nothing
        is_written_inline(file, node) && (owner[node] = (file, path))
        return
    end
    owner_file, owner_path = entry
    owner_file === file || return
    for (steps, child) in _child_slots(node)
        is_written_in_file(file, node, _slot_field(steps)) || continue
        _own_inline_walk!(owner, file, child, extend_reference(owner_path, steps...), visited)
    end
end

# `kept` holds the nodes that wait for their typed slot; `at_fixed` says whether
# `path` is such a slot.
function _own_walk!(owner, file, node, path::Reference, kept, leaf_type, at_fixed::Bool)
    node isa Document || return
    find_held_file(node) === nothing || return
    is_file_domain_node(file, node) || return
    haskey(owner, node) && return
    !at_fixed && haskey(kept, node) && return
    owner[node] = (file, path)
    for (steps, child) in _child_slots(node)
        is_written_in_file(file, node, _slot_field(steps)) || continue
        _own_walk!(owner, file, child, extend_reference(path, steps...), kept, leaf_type,
                   _is_fixed_slot(leaf_type, node, steps))
    end
end

# The type of the reference leaf of `file`, or `nothing` for a file that writes no
# reference, such as a file whose format has no place for one.
function _find_reference_leaf_type(file)
    try
        typeof(make_reference_leaf(file, "file(\"x\")"))
    catch
        nothing
    end
end

# Whether the slot of `node` at `steps` holds an element of a list whose declared
# element type the reference leaf type `leaf_type` is not.
function _is_fixed_slot(leaf_type, node, steps::Tuple)
    leaf_type === nothing && return false
    length(steps) == 2 || return false
    raw = getfield(node, _slot_field(steps))
    value = raw isa AbstractCell ? raw[] : raw
    element_type = find_declared_element_type(value)
    element_type === nothing && return false
    !(leaf_type <: element_type)
end

# Every node of the file's domain that `node` reaches and that a typed slot holds.
function _collect_fixed_nodes!(fixed, file, leaf_type, node, visited)
    node isa Document || return
    find_held_file(node) === nothing || return
    haskey(visited, node) && return
    visited[node] = true
    for (steps, child) in _child_slots(node)
        is_written_in_file(file, node, _slot_field(steps)) || continue
        _is_fixed_slot(leaf_type, node, steps) && (fixed[child] = true)
        _collect_fixed_nodes!(fixed, file, leaf_type, child, visited)
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
        is_view_state_field(typeof(node), name) && continue
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

# One cut of `file`: the owners of the set, the nodes that the copy wrote, and how
# a marker names a file. A save alone (`strict`) names a file by its path relative
# to `base_dir`; a project save names a file by the name that the file gives.
struct _FileCut
    owner::IdDict{Any,Tuple{Any,Reference}}
    file::Any
    visited::IdDict{Any,Bool}
    strict::Bool
    base_dir::String
end

# The rules, for the copy of the file of `cut`. A file document that the content
# holds is a reference leaf in both saves, and the save writes nothing of that
# file. A node of the file is written at its owner path, and every other place
# names it by a marker into the file itself.
function _cut_copy(cut::_FileCut, node, path::Reference)
    node isa Union{Tuple,NamedTuple} && return _cut_tuple(cut, node, path)
    node isa Document || return node
    held = find_held_file(node)
    held === nothing || return _make_held_file_leaf(cut, held, path)
    entry = get(cut.owner, node, nothing)
    entry === nothing &&
        throw(FileCutException(_orphan_message(cut.file, path, node, cut.strict)))
    owner_file, owner_path = entry
    owner_file === cut.file ||
        return make_reference_leaf(cut.file, _make_reference_marker(cut, owner_file, owner_path))
    (haskey(cut.visited, node) || !_is_same_path(path, owner_path)) &&
        return make_reference_leaf(cut.file, _make_reference_marker(cut, cut.file, owner_path))
    cut.visited[node] = true
    is_file_domain_node(cut.file, node) || return make_inline_leaf(cut.file, node, path)
    _rebuild(cut, node, path)
end

# A tuple and a named tuple keep each value as the writer writes it, but a held
# file, at any depth, which becomes its reference leaf. A node in a tuple has no
# path that a marker can name, so the cut owns no other node there.
_cut_tuple(cut::_FileCut, value::Union{Tuple,NamedTuple}, path::Reference) =
    map(value) do element
        element isa Union{Tuple,NamedTuple} && return _cut_tuple(cut, element, path)
        held = element isa Document ? find_held_file(element) : nothing
        held === nothing ? element : _make_held_file_leaf(cut, held, path)
    end

_is_same_path(a::Reference, b::Reference) =
    collect(get_reference_steps(a)) == collect(get_reference_steps(b))

# The reference leaf of a held file, `file("…")`. A held file with no name has no
# path to write, so the save refuses and says where the content holds it.
function _make_held_file_leaf(cut::_FileCut, held, path::Reference)
    isempty(get_filename(held)) && throw(FileCutException(
        (cut.strict ? "save_file!: " : "save_project!: ") * repr(get_filename(cut.file)) *
        " holds a " * string(nameof(typeof(held))) * " with no name at " * print_path_text(path) *
        "; save that file first with \"Save as\", so that this file can name it"))
    make_reference_leaf(cut.file, "file(" * repr(_compute_marker_file_name(cut, held)) * ")")
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
# its kind; a collection field is rebuilt as the same kind of collection. A field
# of the state of a view is no content, so it keeps its value, as the selection
# does, and its documents are not cut.
function _rebuild(cut::_FileCut, node, path::Reference)
    T = typeof(node)
    args = Any[]
    for name in fieldnames(T)
        raw = getfield(node, name)
        value = raw isa AbstractCell ? raw[] : raw
        copied = name === :mouse_target ? nothing :
                 (is_view_state_field(T, name) || !is_written_in_file(cut.file, node, name)) ? value :
                 _cut_field(cut, name, value, path)
        push!(args, raw isa AbstractCell ? make_similar_cell(raw, copied) : copied)
    end
    Base.typename(T).wrapper(args...)
end

function _cut_field(cut::_FileCut, name::Symbol, value, path::Reference)
    if is_element_collection(value)
        items = Any[_cut_copy(cut, element,
                              extend_reference(path, FieldReferenceStep(string(name)), ElementReferenceStep(index)))
                    for (index, element) in enumerate(value)]
        # The list keeps the type of its elements, which its field declares.
        wrapper = Base.typename(typeof(value)).wrapper
        element_type = find_declared_element_type(value)
        return element_type === nothing ? wrapper(items) : wrapper{element_type}(items)
    elseif value isa AbstractVector
        return Any[_cut_copy(cut, element,
                             extend_reference(path, FieldReferenceStep(string(name)), ElementReferenceStep(index)))
                   for (index, element) in enumerate(value)]
    elseif value isa Document || value isa Union{Tuple,NamedTuple}
        return _cut_copy(cut, value, extend_reference(path, FieldReferenceStep(string(name))))
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

# `node(file("b.xml"), "children[1]")` for a node in a file, and
# `node(file("b.xml"), "")` for its root.
_make_reference_marker(cut::_FileCut, file, path::Reference) =
    "node(file(" * repr(_compute_marker_file_name(cut, file)) * "), " * repr(print_path_text(path)) * ")"

# The name of `file` in a marker. A save alone writes its path relative to the base
# folder, with `..` for a file outside it, so the text does not depend on the
# machine, and `load_file(base_dir, name)` reads the name against the same folder.
# A file on another drive has no relative path, and keeps its absolute path. A
# project save writes the name that the file gives.
function _compute_marker_file_name(cut::_FileCut, file)
    name = get_filename(file)
    cut.strict || return name
    base = abspath(cut.base_dir)
    path = abspath(base, name)
    relpath(path, base)
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
        Any[(file, _cut_text(owner, file, false, project.base_dir)) for file in project.files]
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
cut at the file, and printed in the notation of its file type. A marker names a
file by its path relative to `base_dir`. It writes nothing. It throws a
[`FileCutException`](@ref) where the save refuses.

Use it to compare a document with its file on disk.
"""
function cut_file_text(file, base_dir::AbstractString = ".")
    is_file_document(file) ||
        error("cut_file_text: not a file document (", typeof(file), ")")
    owner = _assign_owners(FileProject(base_dir, Any[file]))
    String(_cut_text(owner, file, true, base_dir))
end

"""
    save_file!(file, base_dir) -> Bool

Write one file with no other file around it. A file document that the content
holds is written as `file("…")`, with its path relative to `base_dir` and `..`
for a file outside it, and the save writes nothing of that file. Any other node
must be of the file's domain, or one that the file writes in its own text, as a
`.pred` file writes a JSON value; else the save logs why and returns `false`, as
it does for a held file with no name. A node that the content holds at two
places, and a cycle, are written once, and each other place holds a marker into
the file itself, named by its path relative to `base_dir`, which
[`load_file`](@ref) splices back. The node is written at the first place, or at
the place of a typed list that a marker does not fit, such as the formulas of a
formula sheet. A marker that is a plain leaf of the domain is a plain leaf, and
saves as one.
"""
save_file!(file, base_dir::AbstractString) = save_file_text!(file, base_dir) !== nothing

"""
    save_file_text!(file, base_dir) -> String or nothing

Write one file as [`save_file!`](@ref) does, and answer the text that the file
holds now, or `nothing` when the save refused and wrote nothing.
"""
function save_file_text!(file, base_dir::AbstractString)
    is_file_document(file) ||
        error("save_file!: not a file document (", typeof(file), ")")
    text = try
        cut_file_text(file, base_dir)
    catch e
        e isa FileCutException || rethrow()
        @error e.message
        return nothing
    end
    _write_texts!(base_dir, Any[(file, text)])
    String(text)
end

# One file's text: cut the graph, then print the copy in the file's own
# notation. Both halves can refuse — the cut at a node with no file, the
# notation at a value it cannot write — and both refuse before anything is
# written, so a save that cannot be finished leaves the directory as it was.
function _cut_text(owner, file, strict::Bool, base_dir::AbstractString)
    cut = _FileCut(owner, file, IdDict{Any,Bool}(), strict, String(base_dir))
    content = get_file_content(file)
    if is_own_content(file)
        # The root is the file, so it is rebuilt rather than cut, and the copy is
        # already the file the notation prints.
        cut.visited[content] = true
        return emit_text(_rebuild(cut, content, EmptyReference()))
    end
    emit_text(_with_content(file, _cut_copy(cut, content, EmptyReference())))
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
