"""
    FileProjectModule

Save/load a ProjecturEd document graph as a set of text files that git
can version the ordinary way. Every node that should live in its own
file is a **file document** (`<: FileDocument`) carrying a `filename`;
the driver walks the graph and each file document's content is emitted
to its named file. Cross-file references (built on the reference layer's
`FileReferenceStep`) survive save/load through a marker embedded in
each format's natural syntax.

This module carries the pieces every format hooks into:

- `abstract FileDocument <: Document` — the interface every concrete
  file document (`TextFile`, `JsonFile`, `NedFile`, …) subtypes.
- `filename(f)` / `content(f)` — the interface accessors. Both work off
  the two `@document`-generated cell fields.
- `emit_text(f)` — the format's path-to-text. Concrete types override
  it (a plain leaf like `TextFile` returns its `content` directly; a
  parsed leaf like `JsonFile` delegates to `document_to_text` from the
  visual layer, which is why this abstract lives free of any `visual/`
  dependency). Callers never pull in visual to save a plain text file.
- `load_file(T, filename, base_dir)` — the format's text-to-tree.
  Each concrete type overrides it with its parser call.
- `save_project!(root, base_dir)` — write every reachable file
  document, skipping ones whose emitted bytes match the file already
  on disk (byte-equality dirty check, no op-log required).
- `load_project(T, filename, base_dir)` — read a project rooted at
  a single file document of concrete type `T`.
- `ReferenceStub` — the placeholder for a cross-file reference before
  the target is loaded. Introduced here so the driver has a name for
  it; later stages (S3 / S4) wire the intern table and lazy content.

S2 handles a **one-file project only** — no cross-file walk, no
intern table. `save_project!` writes the root, `load_project` reads
it. Cross-file traversal, marker rewriting, shared identity, and lazy
loading are staged into S3–S5.
"""
module FileProjectModule

import ..CellModule: Cell, ReactiveCell, unwrap_cell
import ..DocumentModule: Document, search_documents
import ..ReferenceModule: ConcreteReference, EmptyReference, Reference, FileReferenceStep

export FileDocument, filename, content, emit_text, load_file,
       save_project!, load_project, ReferenceStub,
       marker_text, parse_marker_text, marker_reference_of

# ── abstract FileDocument ──────────────────────────────────────────────────

"""
    FileDocument

A document that owns a text file. Every concrete subtype declares two
`@document` fields — `filename::String` and a format-native
`content` — so `filename(f)` and `content(f)` work uniformly. Emit
and load are per-format methods (`emit_text` / `load_file`).
"""
abstract type FileDocument <: Document end

"""
    filename(f::FileDocument) -> String

The relative path (from the project's base dir) this file document
lives at on disk. Reads through the underlying reactive cell so a
freshly-set filename is seen.
"""
filename(f::FileDocument) = unwrap_cell(getfield(f, :filename))

"""
    content(f::FileDocument) -> Any

The format-native content of this file document — the parsed AST for
a leaf like `JsonFile`, a raw `String` for a `TextFile`, or a
`ReferenceStub` while the target hasn't been forced yet.
"""
content(f::FileDocument) = unwrap_cell(getfield(f, :content))

"""
    emit_text(f::FileDocument) -> String

Render a file document to the exact text that goes on disk. Concrete
types override this: a raw-string leaf (`TextFile`) returns `content`,
a parsed leaf (`JsonFile`, `XmlFile`, `JuliaFile`, `MarkdownFile`)
projects `content` through the visual layer's `document_to_text`. The
default here just errors so a missing override fails loudly.
"""
emit_text(f::FileDocument) =
    error("emit_text: no method defined for ", typeof(f),
          " — every concrete FileDocument must contribute one")

"""
    load_file(::Type{T}, filename::AbstractString, base_dir::AbstractString) -> T where T <: FileDocument

Read the file at `joinpath(base_dir, filename)` as text, parse it into
`T`'s content AST, and return a fresh `T`. Concrete types override
this with their parser call — `TextFile` reads a raw string,
`JsonFile` calls `jsonparse`, etc.
"""
load_file(::Type{T}, filename::AbstractString, base_dir::AbstractString) where {T<:FileDocument} =
    error("load_file: no method defined for ", T,
          " — every concrete FileDocument must contribute one")

# ── ReferenceStub ──────────────────────────────────────────────────────────

"""
    ReferenceStub(reference::ConcreteReference)

Placeholder for a cross-file reference before its target is resolved.
The `reference` starts with a `FileReferenceStep` and describes where
the target lives; forcing `resolved` (in S4) will consult the loader's
intern table to swap the stub for the actual node. In S2 the stub is
just a first-class node type — no forcing wiring yet, its slot in a
graph is what stays after a marker walk lands.
"""
mutable struct ReferenceStub <: Document
    reference::ConcreteReference
    resolved::ReactiveCell{Any}
end

ReferenceStub(reference::ConcreteReference) = ReferenceStub(reference, ReactiveCell{Any}(nothing))

Base.show(io::IO, s::ReferenceStub) = print(io, "ReferenceStub(", s.reference, ")")

Base.:(==)(a::ReferenceStub, b::ReferenceStub) = a.reference == b.reference

# ── Marker syntax (whole-file only in S3) ──────────────────────────────────

"""
    marker_text(reference::ConcreteReference) -> String

Format a cross-file `ConcreteReference` as the marker text embedded in a
natural file (`"<<REF>>"`). S3 handles the **whole-file** case only:
a reference whose only step is a `FileReferenceStep` renders as
`<<file("path")>>`. Longer chains (identity, field steps into a
loaded file) land in later stages together with the intern table
they need to resolve.
"""
function marker_text(reference::ConcreteReference)
    step = reference.head
    step isa FileReferenceStep ||
        error("marker_text: reference must start with a FileReferenceStep, got ", typeof(step))
    reference.tail isa EmptyReference ||
        error("marker_text: S3 only supports whole-file markers; got a chain of length > 1")
    "<<file(" * repr(step.path) * ")>>"
end

marker_text(stub::ReferenceStub) = marker_text(stub.reference)

# `<<file("path")>>` matcher — deliberately strict so a JSON string that
# happens to start with `<<file(` but isn't a valid marker fails cleanly
# rather than being taken for one and losing its content on save.
const _MARKER_RE = r"^<<file\(\"((?:[^\"\\]|\\.)*)\"\)>>$"

"""
    parse_marker_text(text::AbstractString) -> Union{Nothing, ConcreteReference}

Recognise a marker string. Returns the ref chain the marker names, or
`nothing` if `text` is not marker-shaped. S3 recognises only the
whole-file form; a non-match is not an error — the caller (a per-format
marker walk) uses `nothing` to leave the text as an ordinary value.
"""
function parse_marker_text(text::AbstractString)
    m = match(_MARKER_RE, text)
    m === nothing && return nothing
    # Un-escape the JSON-ish backslash escapes we allow in the path.
    raw = m.captures[1]
    path = _unescape_marker_path(raw)
    ConcreteReference(FileReferenceStep(path), EmptyReference())
end

function _unescape_marker_path(s::AbstractString)
    buf = IOBuffer()
    i = firstindex(s)
    while i <= lastindex(s)
        c = s[i]
        if c == '\\' && i < lastindex(s)
            n = s[i + 1]
            n == '"'      && (write(buf, '"');  i = nextind(s, i, 2); continue)
            n == '\\'     && (write(buf, '\\'); i = nextind(s, i, 2); continue)
            # Fall through for any other escape (leave it literal — v1 keeps
            # only the escapes the format needs to embed inside a JSON string).
        end
        write(buf, c)
        i = nextind(s, i)
    end
    String(take!(buf))
end

# ── Driver: save + load ────────────────────────────────────────────────────

"""
    save_project!(root::FileDocument, base_dir::AbstractString) -> root

Write `root`'s emitted text to `joinpath(base_dir, filename(root))`.

The write is **content-equality-gated**: if a file already exists at
that path and its bytes match `emit_text(root)`, nothing is written
(so `mtime` and git's clean status are preserved). If the file is
missing (never existed, or was deleted since load), it is recreated.

S2 handles a single root file only. Cross-file traversal (walking
child file documents reachable through the graph and writing each in
turn) is added in S3.
"""
function save_project!(root::FileDocument, base_dir::AbstractString)
    mkpath(base_dir)
    written = String[]
    seen    = IdDict{FileDocument, Bool}()
    for file in _reachable_files(root)
        haskey(seen, file) && continue
        seen[file] = true
        _save_one_file!(file, base_dir)
        push!(written, filename(file))
    end
    root
end

# Enumerate every FileDocument reachable from `root` via structural
# descent — including `root` itself. Uses `search_documents`, which
# runs a `:once_per_object` DFS and dedups shared subtrees. Reference
# stubs are *not* file documents (they're markers pointing at one), so
# a stub does not add its target to the walk.
function _reachable_files(root::FileDocument)
    FileDocument[m for m in search_documents(root, x -> x isa FileDocument)]
end

function _save_one_file!(file::FileDocument, base_dir::AbstractString)
    path = joinpath(base_dir, filename(file))
    parent = dirname(path)
    isempty(parent) || mkpath(parent)
    text = emit_text(file)
    _write_if_changed(path, text)
    file
end

# The byte-equality guard the plan calls out: skip the write when the
# emitted text matches what's already on disk. Reads as bytes, not as
# a decoded string, so a caller cannot trip the check with an encoding
# difference the read wouldn't survive.
function _write_if_changed(path::AbstractString, text::AbstractString)
    bytes = Vector{UInt8}(codeunits(text))
    if isfile(path)
        existing = read(path)
        existing == bytes && return path
    end
    open(io -> write(io, bytes), path, "w")
    path
end

"""
    load_project(::Type{T}, filename::AbstractString, base_dir::AbstractString) -> T

Load a project rooted at a single file document of concrete type `T`.
Delegates to `load_file(T, filename, base_dir)` — the per-type parser
call — and returns whatever it returns.

S2 handles one file only. In S3 the loader consults an intern table
and resolves cross-file marker stubs lazily.
"""
load_project(::Type{T}, filename::AbstractString, base_dir::AbstractString) where {T<:FileDocument} =
    load_file(T, filename, base_dir)

end # module
