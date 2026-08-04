"""
    FileProjectModule

Save/load a ProjecturEd document graph as a set of text files that git
can version the ordinary way. Every node that should live in its own
file is a **file document**: a type carrying a `filename` field that
either subtypes `FileDocument` (the ergonomic case for types that
have no existing supertype) or opts in via the `is_file_document`
trait (for types that already have one, e.g. omnetpp-pred's `NedFile
<: NedDocument`). The driver walks the graph and each file
document's content is emitted to its named file. Cross-file
embedding survives save/load through a **marker** embedded in each
format's natural syntax — see "The marker language" below.

This module carries the pieces every format hooks into:

- `abstract FileDocument <: Document` — supertype for the ergonomic
  case; concrete types (`TextFile`, `JsonFile`, …) inherit and get
  the trait automatically.
- `is_file_document(x) :: Bool` — the trait predicate every driver
  check goes through. Default `false`; `true` for `FileDocument`
  subtypes; external types opt in with their own method.
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
- `ReferenceStub` — a first-class `Document` node standing in for one
  marker. `resolve!(stub)` evaluates the marker's expression (lazily,
  once) and caches the value in a reactive cell.
- `LoaderContext` — the per-load intern table + base directory the
  stubs consult.
- `register_file_document_type!(ext, T)` — every concrete
  `FileDocument` registers its extension so `file(…)` can pick the
  right type for a marker's target.

# The marker language

A marker is `<<expr>>`, where `expr` is a **restricted Julia
expression**: a call over a registered vocabulary whose arguments are
literals or nested calls. It is read with the Julia parser and run by
the small interpreter here — never `eval`, so opening a project can
never execute arbitrary code, and a marker is still analyzable data.

    <<file("child.json")>>                          the parsed file document
    <<definition(file("steps.jl"), "queue_step")>>   one definition inside it

The vocabulary is the extension seam: each function is registered by
the package that owns its machinery, with
`register_marker_function!(:name, f)`, and is called as
`f(ctx, args...)`. This module registers `file` (the project loader
itself); the Julia domain registers `definition`; omnetpp-julia's
presentation registers `realize`.

Three properties every marker keeps:

- **Verbatim source.** A stub stores the marker body exactly as
  written, and `marker_text` re-emits it, so saving a file that was
  loaded is byte-identical — the save path never re-prints an
  evaluated value.
- **Interning.** Every call's value is cached in `ctx.intern` under
  its canonical source, so two markers naming the same thing evaluate
  to the `===` object. `file(…)` also pre-registers its placeholder
  before parsing, which is what makes reference cycles terminate.
- **Laziness.** Evaluation happens on `resolve!`, not at load, and the
  result lands in a reactive cell — so a projection that reads
  `stub.resolved` re-prints by itself when the embed is forced.
"""
module FileProjectModule

import ..CellModule: Cell, ComputedCell, ReactiveCell, unwrap_cell
import ..DocumentModule: Document, search_documents

export FileDocument, is_file_document,
       filename, content, emit_text, populate_file!,
       save_project!, load_project, ReferenceStub, resolve!, is_resolved,
       resolve_stubs!, LoaderContext,
       register_file_document_type!, file_document_type,
       register_marker_function!, marker_function, evaluate_marker,
       marker_text, parse_marker_text, file_marker_text

# ── FileDocument: abstract type + is_file_document trait ──────────────────
#
# `FileDocument` is the *ergonomic* case: a domain that hasn't picked an
# abstract supertype for its file-shaped node can just subtype it and
# get `filename` / `content` / the projection dispatch for free.
#
# For a type that *already* has an abstract supertype (Julia's single
# inheritance forbids a second one — cf. omnetpp-pred's `NedFile <:
# NedDocument` and `IniFile <: IniDocument`), the **`is_file_document`
# trait** is the opt-in: return `true` from `is_file_document(::MyFile)`
# and provide the four per-type methods (`filename`, `emit_text`,
# `populate_file!`, `_make_empty_file`). Every predicate the driver
# uses (the `search_documents` walk, `save_project!` guard, resolve
# lookups) goes through the trait, so an abstract-type file document
# and a trait-only file document are interchangeable to the substrate.

"""
    FileDocument

A document that owns a text file. Every direct subtype declares two
`@document` fields — `filename::String` and a format-native `content`
— so `filename(f)` and `content(f)` work uniformly.

The abstract type is one of *two* ways to opt in to the FileProject
substrate; the other is the `is_file_document` trait (see below), for
types that already have an incompatible supertype in their own domain.
"""
abstract type FileDocument <: Document end

"""
    is_file_document(x) -> Bool

Predicate the FileProject driver uses everywhere: the
`search_documents` walk (`save_project!` reachability), the
`_reachable_files` iterator, and every "is this thing a file we should
try to write" check.

Defaults to `false`. Every `FileDocument` inherits `true` automatically.
An external type (e.g. omnetpp-pred's `NedFile`, which is
`<: NedDocument` and so can't also `<: FileDocument`) opts in with its
own method:

    is_file_document(::MyDomainFile) = true

Plus the four per-type methods (`filename`, `emit_text`,
`populate_file!`, `_make_empty_file`).
"""
is_file_document(::Any)          = false
is_file_document(::FileDocument) = true

"""
    filename(f) -> String

The relative path (from the project's base dir) this file document
lives at on disk. Default reads through the `filename` field's
underlying reactive cell — works for any type that has one (both
`FileDocument` subtypes and trait-based opt-ins).
"""
filename(f) = unwrap_cell(getfield(f, :filename))

"""
    content(f) -> Any

The format-native content of this file document — the parsed AST for
a leaf like `JsonFile`, a raw `String` for a `TextFile`, or a
`ReferenceStub` while the target hasn't been forced yet.

Default reads through the `content` field. Types where the "content"
is spread across multiple fields (e.g. omnetpp-pred's `NedFile` with
its `children` + `version`) don't have a single `content` field and
skip this method — their `emit_text` calls `document_to_text` on the
whole node directly.
"""
content(f) = unwrap_cell(getfield(f, :content))

"""
    emit_text(f) -> String

Render a file document to the exact text that goes on disk. Concrete
types override this: a raw-string leaf (`TextFile`) returns `content`,
a parsed leaf (`JsonFile`, `XmlFile`, `JuliaFile`, `MarkdownFile`)
projects `content` through the visual layer's `document_to_text`. The
default here just errors so a missing override fails loudly.
"""
emit_text(f) =
    error("emit_text: no method defined for ", typeof(f),
          " — every file document must contribute one (via `<: FileDocument` or the `is_file_document` trait)")

"""
    populate_file!(f, filename::AbstractString, ctx::LoaderContext)

Per-format hook. Read `joinpath(ctx.base_dir, filename)` as text,
parse it into the format-native content, wire any cross-file marker
into `ReferenceStub`s carrying `ctx` so they can resolve later, and
set `f`'s content field to the parsed value. Concrete types override
this with their parser call — `TextFile` reads a raw string,
`JsonFile` calls `jsonparse`, etc.

`f` is pre-created empty by `_load_into_context` and already
registered in `ctx.intern` before `populate_file!` runs, so a cycle
(A refers into B refers back into A) terminates: the second
`resolve!` hitting `A` finds the pre-registered placeholder.
"""
populate_file!(f, filename::AbstractString, ctx) =
    error("populate_file!: no method defined for ", typeof(f),
          " — every file document must contribute one (via `<: FileDocument` or the `is_file_document` trait)")

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
every relative marker path resolves against — paths are always
written relative to the project root, never to the file the marker
sits in, which is what makes one canonical intern key per target.

`intern` maps the **canonical source of a marker call** to the value
that call evaluated to: `file("a.json")` to its `JsonFile`,
`realize(file("a.json"))` to the document that realises. Keying by
canonical source (rather than by the value's identity) is what makes
two markers written the same way share one object, and what lets
`file` pre-register a placeholder to break cycles.
"""
mutable struct LoaderContext
    base_dir::String
    intern::Dict{String, Any}
end

LoaderContext(base_dir::AbstractString) =
    LoaderContext(String(base_dir), Dict{String, Any}())

# ── Registry: extension → concrete FileDocument type ──────────────────────

const _FILE_DOCUMENT_TYPES = Dict{String, Type}()

"""
    register_file_document_type!(extension::AbstractString, T::Type)

Wire an extension (e.g. `".json"`) to the concrete type that owns it.
The loader consults this registry when it resolves a marker whose
path ends in that extension. `T` may be a `FileDocument` subtype or a
trait-based opt-in; the registry doesn't restrict.

Registering `""` is fine — the empty extension is the fallback
(`TextFile` claims it so any path with no extension loads as plain
text).
"""
function register_file_document_type!(extension::AbstractString, T::Type)
    _FILE_DOCUMENT_TYPES[String(extension)] = T
    T
end

"""
    file_document_type(path::AbstractString) -> Type

Look up the concrete file-document type for `path` by its extension
(case-insensitive). Errors if no format has claimed the extension —
better a loud miss at resolve time than a silently-wrong parse.
"""
function file_document_type(path::AbstractString)
    ext = lowercase(splitext(path)[2])
    haskey(_FILE_DOCUMENT_TYPES, ext) && return _FILE_DOCUMENT_TYPES[ext]
    error("file_document_type: no file document registered for extension ",
          repr(ext), " — call register_file_document_type!(", repr(ext), ", …)")
end

# ── ReferenceStub ──────────────────────────────────────────────────────────

"""
    ReferenceStub(source::AbstractString [, context::LoaderContext])

One marker, standing in the document tree for whatever its expression
evaluates to. `source` is the marker body **verbatim** — the text
between `<<` and `>>`, exactly as it was written — so the save path
can re-emit it without ever re-printing the value. `context`, when
present, is the `LoaderContext` this stub was born under;
`resolve!(stub)` evaluates through it, sharing interned values with
sibling stubs and terminating cycles.

A stub with `context === nothing` is *unhosted* — a marker composed in
memory outside a load session. Calling `resolve!` on it errors; the
stub still serves as a first-class marker for save-time projection.

`stub.resolved` reads the evaluated value through its reactive cell
(`nothing` until forced), so a projection that prints an embed
re-prints by itself once `resolve!` runs.
"""
mutable struct ReferenceStub <: Document
    source::String
    context::Union{Nothing, LoaderContext}
    resolved::ReactiveCell{Any}
end

ReferenceStub(source::AbstractString) =
    ReferenceStub(String(source), nothing, ReactiveCell{Any}(nothing))
ReferenceStub(source::AbstractString, context::LoaderContext) =
    ReferenceStub(String(source), context, ReactiveCell{Any}(nothing))

# `stub.resolved` reads *through* the reactive cell (the raw cell stays
# reachable with `getfield`), which is both what a reference path into
# the embed evaluates and what makes a printer depend on the forcing.
Base.getproperty(stub::ReferenceStub, name::Symbol) =
    name === :resolved ? getfield(stub, :resolved)[] : getfield(stub, name)

Base.show(io::IO, s::ReferenceStub) = print(io, "ReferenceStub(", marker_text(s), ")")

# Two stubs are equal when their marker source is — the context and the
# resolved cell are load-session state, not identity.
Base.:(==)(a::ReferenceStub, b::ReferenceStub) = getfield(a, :source) == getfield(b, :source)

"""
    is_resolved(stub::ReferenceStub) -> Bool

`true` when `resolve!` has been called on this stub (or a previous
resolve in the same context session cached its value).
"""
is_resolved(stub::ReferenceStub) = getfield(stub, :resolved)[] !== nothing

"""
    resolve!(stub::ReferenceStub) -> Any

Evaluate this stub's marker expression and cache the value. On a
first call the expression runs through [`evaluate_marker`](@ref) —
which consults `context.intern`, so a value some sibling marker
already produced is shared rather than rebuilt. Subsequent calls read
the cached value.
"""
function resolve!(stub::ReferenceStub)
    cached = getfield(stub, :resolved)[]
    cached === nothing || return cached
    ctx = stub.context
    ctx === nothing &&
        error("resolve!: this ReferenceStub has no LoaderContext — resolve requires a load-session context")
    value = evaluate_marker(getfield(stub, :source), ctx)
    getfield(stub, :resolved)[] = value
    value
end

"""
    resolve_stubs!(root) -> root

Force every marker reachable from `root`, transitively: resolve the
stubs in `root`, then the stubs inside whatever they evaluated to, and
so on. Shared and cyclic targets terminate through the intern table
and the visited set.

Loading stays lazy by default (`load_project` resolves nothing); this
is the "open the whole project now" button, used when a caller wants
the complete graph in memory — e.g. before rendering a page whose
embeds must all be visible.
"""
function resolve_stubs!(root)
    pending = Any[root]
    seen    = IdDict{Any, Bool}()
    while !isempty(pending)
        node = pop!(pending)
        (node === nothing || haskey(seen, node)) && continue
        seen[node] = true
        for stub in search_documents(node, x -> x isa ReferenceStub)
            push!(pending, resolve!(stub))
        end
    end
    root
end

# ── The marker language ────────────────────────────────────────────────────
#
# `<<expr>>` where `expr` is a call over the registered vocabulary whose
# arguments are literals or nested calls. Julia parses it; the
# interpreter below runs it. See the module docstring.

const _MARKER_FUNCTIONS = Dict{Symbol, Any}()

"""
    register_marker_function!(name::Symbol, f) -> f

Add `name` to the marker vocabulary. `f` is called as
`f(ctx::LoaderContext, args...)` with the marker's evaluated
arguments, and returns the value the marker stands for. Register from
a module's `__init__` (the registry is runtime state, not baked into
the precompiled image).
"""
function register_marker_function!(name::Symbol, f)
    _MARKER_FUNCTIONS[name] = f
    f
end

"""
    marker_function(name::Symbol) -> f or nothing

The vocabulary entry for `name`, or `nothing` when the name is not
registered.
"""
marker_function(name::Symbol) = get(_MARKER_FUNCTIONS, name, nothing)

marker_function_names() = sort!(String[String(k) for k in keys(_MARKER_FUNCTIONS)])

"""
    marker_text(stub::ReferenceStub) -> String

The stub's marker as it appears in a file: its verbatim source
wrapped back in `<<`/`>>`.
"""
marker_text(stub::ReferenceStub) = "<<" * getfield(stub, :source) * ">>"

"""
    file_marker_text(path::AbstractString) -> String

The whole-file marker naming `path` — `<<file("path")>>`. What a
format's projection emits for a `FileDocument` embedded directly in
its tree (as opposed to through a stub).
"""
file_marker_text(path::AbstractString) = "<<file(" * repr(String(path)) * ")>>"

const _MARKER_OPEN  = "<<"
const _MARKER_CLOSE = ">>"

"""
    parse_marker_text(text::AbstractString) -> Union{Nothing, String}

Recognise a marker. Returns the marker's **body source** verbatim, or
`nothing` when `text` is not marker-shaped — which is not an error:
the caller (a per-format marker walk) uses `nothing` to leave the
text as an ordinary value. Surrounding whitespace is ignored, so a
fenced block's body works as-is.

Recognition is syntactic only: the body must parse as a restricted
call expression. Whether its function is in the vocabulary is settled
at `resolve!` time, so a marker naming a function some not-yet-loaded
package registers still round-trips.
"""
function parse_marker_text(text::AbstractString)
    t = strip(text)
    (startswith(t, _MARKER_OPEN) && endswith(t, _MARKER_CLOSE)) || return nothing
    stop = prevind(t, prevind(t, lastindex(t)))
    start = firstindex(t) + ncodeunits(_MARKER_OPEN)
    start > stop && return nothing
    body = SubString(t, start, stop)
    _parse_marker_expression(body) === nothing ? nothing : String(body)
end

"""
    evaluate_marker(source::AbstractString, ctx::LoaderContext) -> Any

Run one marker body against the vocabulary, in `ctx`. Errors when the
body is not a restricted call expression or names a function no
package registered — a marker never silently evaluates to nothing.
"""
function evaluate_marker(source::AbstractString, ctx::LoaderContext)
    expr = _parse_marker_expression(source)
    expr === nothing &&
        error("evaluate_marker: not a marker expression: ", repr(String(source)),
              " — a marker body is a call over the vocabulary (", join(marker_function_names(), ", "), ")")
    _evaluate_marker_expression(expr, ctx)
end

function _evaluate_marker_expression(e::Expr, ctx::LoaderContext)
    key = _canonical_marker(e)
    haskey(ctx.intern, key) && return ctx.intern[key]
    name = e.args[1]::Symbol
    f = marker_function(name)
    f === nothing &&
        error("marker: unknown function ", name, " in ", key,
              " — the vocabulary is (", join(marker_function_names(), ", "), ")")
    args = Any[a isa Expr ? _evaluate_marker_expression(a, ctx) : a for a in e.args[2:end]]
    value = f(ctx, args...)
    ctx.intern[key] = value
    value
end

# Parse a marker body, returning the expression when it is in the
# restricted subset and `nothing` otherwise. `raise=false` turns a
# syntax error into an `Expr(:error, …)`, which fails the shape check
# like any other non-call.
function _parse_marker_expression(body::AbstractString)
    expr = Meta.parse(String(body); raise=false, depwarn=false)
    _is_marker_call(expr) ? expr : nothing
end

# The subset: a call whose head is a plain name and whose arguments are
# literals or, recursively, calls. No assignment, no control flow, no
# bare names, no keyword arguments — a marker is data that happens to
# read as Julia.
_is_marker_call(::Any) = false
function _is_marker_call(e::Expr)
    e.head === :call || return false
    isempty(e.args) && return false
    e.args[1] isa Symbol || return false
    all(a -> _is_marker_call(a) || _is_marker_literal(a), @view e.args[2:end])
end

_is_marker_literal(x) = x isa AbstractString || x isa Number || x isa Char || x === nothing

# The intern key: the expression printed in one canonical form, so
# `file("a.json")` and `file( "a.json" )` name the same value.
function _canonical_marker(e::Expr)
    io = IOBuffer()
    _print_canonical(io, e)
    String(take!(io))
end

function _print_canonical(io::IO, e::Expr)
    print(io, e.args[1], "(")
    for (i, a) in enumerate(@view e.args[2:end])
        i > 1 && print(io, ", ")
        _print_canonical(io, a)
    end
    print(io, ")")
end

_print_canonical(io::IO, x::AbstractString) = print(io, repr(String(x)))
_print_canonical(io::IO, x) = print(io, repr(x))

# ── The `file` vocabulary function ─────────────────────────────────────────

"""
    file(path)  [marker vocabulary]

The parsed file document at `path`, relative to the project's base
directory. Interned per load session, so every marker naming one file
gets the `===` document, and cycle-safe: the placeholder is registered
before the file is parsed.
"""
function marker_file(ctx::LoaderContext, path)
    path isa AbstractString ||
        error("file(…): expected a path string, got ", typeof(path), " (", repr(path), ")")
    p = String(path)
    _load_into_context(file_document_type(p), p, ctx; marker_key=_file_marker_key(p))
end

# Normalised so `a.json` and `./a.json` intern as one target.
_file_marker_key(path::AbstractString) = "file(" * repr(normpath(String(path))) * ")"

function __init__()
    register_marker_function!(:file, marker_file)
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
function save_project!(root, base_dir::AbstractString)
    is_file_document(root) ||
        error("save_project!: root is not a file document (", typeof(root),
              ") — subtype FileDocument or add `is_file_document(::", typeof(root), ") = true`")
    mkpath(base_dir)
    seen = IdDict{Any, Bool}()
    for file in _reachable_files(root)
        haskey(seen, file) && continue
        seen[file] = true
        _save_one_file!(file, base_dir)
    end
    root
end

# Enumerate every file document reachable from `root` via structural
# descent — including `root` itself. Uses `search_documents`, which
# runs a `:once_per_object` DFS and dedups shared subtrees. Reference
# stubs are *not* file documents (they're markers pointing at one), so
# a stub does not add its target to the walk.
_reachable_files(root) = search_documents(root, is_file_document)

function _save_one_file!(file, base_dir::AbstractString)
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
function load_project(::Type{T}, filename::AbstractString, base_dir::AbstractString) where {T}
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
                            marker_key::Union{Nothing, String}=nothing) where {T}
    key = marker_key === nothing ? _file_marker_key(filename) : marker_key
    haskey(ctx.intern, key) && return ctx.intern[key]::T
    file = _make_empty_file(T, filename)
    ctx.intern[key] = file
    populate_file!(file, filename, ctx)
    file
end

# Default: `T(filename)` using the @document keyword constructor with
# the declared default for `content`. A type whose default doesn't fit
# a placeholder shape overrides this.
_make_empty_file(::Type{T}, filename::AbstractString) where {T} =
    T(String(filename))

end # module
