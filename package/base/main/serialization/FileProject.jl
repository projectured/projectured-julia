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
- `populate_file!(f, filename, ctx)` — the format's text-to-tree
  hook: reads a file, parses, wires cross-file markers to
  `ReferenceStub`s sharing `ctx`, and sets `f`'s content. Each
  concrete type overrides it. The driver pre-registers `f` in
  `ctx.intern` before calling `populate_file!`, which is what
  breaks cycles.
- `save_project!(root, base_dir)` — write every reachable file
  document, skipping ones whose emitted bytes match the file already
  on disk (byte-equality dirty check, no op-log required).
- `load_project(T, filename, base_dir)` — read a project rooted at
  a single file document of concrete type `T`. Creates one
  `LoaderContext` that all stubs from the load share.
- `ReferenceStub` — a first-class `Document` node standing in for a
  cross-file reference. `resolve!(stub)` fetches (or lazily loads)
  the target through the intern table so two markers to the same
  target share the same `===` object.
- `LoaderContext` — the per-load intern table + base directory the
  stubs consult.
- `register_file_document_type!(ext, T)` — every concrete
  `FileDocument` registers its extension so `resolve!` can pick the
  right type for a marker's target.
"""
module FileProjectModule

import ..CellModule: Cell, ReactiveCell, unwrap_cell
import ..DocumentModule: Document, search_documents
import ..ReferenceModule: ConcreteReference, EmptyReference, Reference, FileReferenceStep

export FileDocument, filename, content, emit_text, populate_file!,
       save_project!, load_project, ReferenceStub, resolve!, is_resolved,
       LoaderContext,
       register_file_document_type!, file_document_type,
       marker_text, parse_marker_text

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
    populate_file!(f::FileDocument, filename::AbstractString, ctx::LoaderContext)

Per-format hook. Read `joinpath(ctx.base_dir, filename)` as text,
parse it into the format-native content, wire any cross-file marker
into `ReferenceStub`s carrying `ctx` so they can resolve later, and
set `f`'s content field to the parsed value. Concrete types override
this with their parser call — `TextFile` reads a raw string,
`JsonFile` calls `jsonparse`, etc.

The FileDocument `f` is pre-created empty by `_load_into_context` and
already registered in `ctx.intern` before `populate_file!` runs, so a
cycle (A refers into B refers back into A) terminates: the second
`resolve!` hitting `A` finds the pre-registered placeholder.
"""
populate_file!(f::FileDocument, filename::AbstractString, ctx) =
    error("populate_file!: no method defined for ", typeof(f),
          " — every concrete FileDocument must contribute one")

# ── LoaderContext ─────────────────────────────────────────────────────────
#
# The shared state of one project-load session. All `ReferenceStub`s
# produced by a single `load_project(...)` call share one context: the
# intern table dedups two markers pointing at the same target, and
# `_load_into_context` uses it to break cycles (pre-register a
# placeholder before parsing so a mutual reference back to `A` while
# loading `B` finds the placeholder rather than looping).

"""
    LoaderContext(base_dir::AbstractString)

The bookkeeping one `load_project` call carries. `base_dir` is where
every relative marker path resolves against; `intern` maps a fully
qualified `ConcreteReference` to whatever it resolved to (a
`FileDocument` for a whole-file reference; later stages extend this
to fragment references into a loaded document).
"""
mutable struct LoaderContext
    base_dir::String
    # Keyed by `marker_text(ref)` (a String) rather than by the
    # `ConcreteReference` itself, because `hash(::ConcreteReference)`
    # is not `==`-consistent — dict lookups by a *fresh* ref that
    # equals a stored one would miss. The marker text is unique per
    # reference in the S3/S4 vocabulary, so it's a safe surrogate.
    intern::Dict{String, Any}
end

LoaderContext(base_dir::AbstractString) =
    LoaderContext(String(base_dir), Dict{String, Any}())

# ── Registry: extension → concrete FileDocument type ──────────────────────

const _FILE_DOCUMENT_TYPES = Dict{String, Type}()

"""
    register_file_document_type!(extension::AbstractString, T::Type{<:FileDocument})

Wire an extension (e.g. `".json"`) to the concrete `FileDocument`
subtype that owns it. The loader consults this registry when it
resolves a marker whose path ends in that extension. Registering
`""` is fine — the empty extension is the fallback (`TextFile` claims
it so any path with no extension loads as plain text).
"""
function register_file_document_type!(extension::AbstractString, T::Type{<:FileDocument})
    _FILE_DOCUMENT_TYPES[String(extension)] = T
    T
end

"""
    file_document_type(path::AbstractString) -> Type{<:FileDocument}

Look up the concrete `FileDocument` type for `path` by its extension
(case-insensitive). Errors if no format has claimed the extension —
better a loud miss at resolve time than a silently-wrong parse.
"""
function file_document_type(path::AbstractString)
    ext = lowercase(splitext(path)[2])
    haskey(_FILE_DOCUMENT_TYPES, ext) && return _FILE_DOCUMENT_TYPES[ext]
    error("file_document_type: no FileDocument registered for extension ",
          repr(ext), " — call register_file_document_type!(", repr(ext), ", …)")
end

# ── ReferenceStub ──────────────────────────────────────────────────────────

"""
    ReferenceStub(reference::ConcreteReference [, context::LoaderContext])

Placeholder for a cross-file reference before its target is resolved.
`reference` starts with a `FileReferenceStep` and describes where the
target lives; `context`, when present, is the `LoaderContext` this
stub was born under — `resolve!(stub)` consults `context.intern` to
share targets with sibling stubs and to break cycles.

A stub with `context === nothing` is *unhosted* — a marker that was
constructed in memory outside a load session (e.g. by a user
composing a graph). Calling `resolve!` on it errors; the stub still
serves as a first-class marker for save-time projection.
"""
mutable struct ReferenceStub <: Document
    reference::ConcreteReference
    context::Union{Nothing, LoaderContext}
    resolved::ReactiveCell{Any}
end

ReferenceStub(reference::ConcreteReference) =
    ReferenceStub(reference, nothing, ReactiveCell{Any}(nothing))
ReferenceStub(reference::ConcreteReference, context::LoaderContext) =
    ReferenceStub(reference, context, ReactiveCell{Any}(nothing))

Base.show(io::IO, s::ReferenceStub) = print(io, "ReferenceStub(", s.reference, ")")

# Two stubs are equal when their references are — the context and the
# resolved cell are load-session state, not identity.
Base.:(==)(a::ReferenceStub, b::ReferenceStub) = a.reference == b.reference

"""
    is_resolved(stub::ReferenceStub) -> Bool

`true` when `resolve!` has been called on this stub (or a previous
resolve in the same context session cached its target).
"""
is_resolved(stub::ReferenceStub) = getfield(stub, :resolved)[] !== nothing

"""
    resolve!(stub::ReferenceStub) -> Any

Load-or-fetch the referent named by `stub.reference`. On first call,
consults `stub.context.intern`; on a miss, loads the referenced file
(pre-registering it in the intern table before parsing so a cycle
back to the same file terminates), stores the result in the intern
table, and populates `stub.resolved`. Subsequent calls hit the
cached value in `stub.resolved` directly.

S4 handles the **whole-file** marker only. A fragment reference
(`file("x").identity("h")...`) is deferred to S5.
"""
function resolve!(stub::ReferenceStub)
    cached = getfield(stub, :resolved)[]
    cached === nothing || return cached
    ctx = stub.context
    ctx === nothing &&
        error("resolve!: this ReferenceStub has no LoaderContext — resolve requires a load-session context")
    ref = stub.reference
    step = ref.head
    step isa FileReferenceStep ||
        error("resolve!: reference must start with a FileReferenceStep, got ", typeof(step))
    ref.tail isa EmptyReference ||
        error("resolve!: fragment references are not yet supported (S5) — got a chain of length > 1")
    T = file_document_type(step.path)
    target = _load_into_context(T, step.path, ctx; marker_key=marker_text(ref))
    getfield(stub, :resolved)[] = target
    target
end

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

Write every **loaded** file document reachable from `root` — `root`
itself, every embedded child `FileDocument`, and every `FileDocument`
found through a `ReferenceStub` whose `resolve!` has already
populated it. Unresolved stubs are markers, not loaded content: the
files they name are left untouched on disk. This is what makes "load
project, edit only the parts I touched, save" preserve the
untouched files' `mtime` (and git clean status).

Each written file is **content-equality-gated**: if a file already
exists at its path and its bytes match `emit_text(file)`, nothing is
written. If the file is missing (never existed, or was deleted
since load), it is recreated.
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
Creates a fresh `LoaderContext(base_dir)` and threads it through the
per-type `populate_file!` hook so every `ReferenceStub` produced by
the marker walk shares the same intern table: two markers pointing
at the same file resolve to `===` objects, and cyclic reference
graphs terminate.
"""
function load_project(::Type{T}, filename::AbstractString, base_dir::AbstractString) where {T<:FileDocument}
    ctx = LoaderContext(base_dir)
    _load_into_context(T, filename, ctx)
end

"""
    _load_into_context(T, filename, ctx) -> T

The core load step: return the interned `FileDocument` for
`filename`, loading it if this is its first sighting in `ctx`.

The **placeholder pre-registration** — inserting a fresh empty
`FileDocument` into the intern table *before* parsing — is what
breaks cycles: while `populate_file!` is walking `B`'s content and
substitutes markers, a marker back to `A` becomes a `ReferenceStub`;
when someone later `resolve!`s that stub, the intern lookup finds
the placeholder for `A` already there (populated by then, since `A`
finished loading before its stubs are forced by user code).
"""
function _load_into_context(::Type{T}, filename::AbstractString, ctx::LoaderContext;
                            marker_key::Union{Nothing, String}=nothing) where {T<:FileDocument}
    key = marker_key === nothing ?
          marker_text(ConcreteReference(FileReferenceStep(String(filename)), EmptyReference())) :
          marker_key
    haskey(ctx.intern, key) && return ctx.intern[key]::T
    file = _make_empty_file(T, filename)
    ctx.intern[key] = file
    populate_file!(file, filename, ctx)
    file
end

# Default: `T(filename)` using the @document keyword constructor with
# the declared default for `content`. A type whose default doesn't fit
# a placeholder shape overrides this.
_make_empty_file(::Type{T}, filename::AbstractString) where {T<:FileDocument} =
    T(String(filename))

end # module
