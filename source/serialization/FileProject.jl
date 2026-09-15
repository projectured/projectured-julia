# Fragment of `SerializationModule` — the contract a file document keeps, and
# the marker language a reference is written in.
#
# A document graph is saved as text files that git can version the ordinary
# way. Every node that lives in a file of its own is a **file document**: a
# type with a `filename` and a `content`, either a subtype of `FileDocument` or
# a type that opts in with the `is_file_document` trait. A file reference is a
# fact about storage, so it never sits in the document as a node: the save in
# `FileCut.jl` writes one where it cuts, in the file's own notation, and the
# load in `FileSplice.jl` puts the node it names back in its place.
#
# What every format contributes, in one line each:
#
# - `get_file_domain(::Type{T})` — the document type the file's content is
#   made of; a node of it is written in the file, any other document is a cut.
# - `parse_file_content(::Type{T}, text)` — the parser of the format.
# - `make_reference_leaf(file, marker)` — the file's spelling of a reference.
# - `find_reference_marker(node)` — the marker a leaf carries, or `nothing`.
# - `emit_text(file)` — the file's text, through the format's natural notation.
#
# # The marker language
#
# A marker is `<<expr>>`, where `expr` is a **restricted Julia expression**: a
# call over a registered vocabulary whose arguments are literals or nested
# calls. It is read with the Julia parser and run by the small interpreter in
# `FileSplice.jl` — never `eval`, so opening a project can never execute
# arbitrary code, and a marker is still analyzable data.
#
#     <<file("child.json")>>                            the file's content
#     <<node(file("child.json"), "entries[2].value")>>  one node inside it
#     <<definition(file("steps.jl"), "queue_step")>>    one definition inside it
#     <<section(file("page.md"), "Title")>>             what a heading heads
#     <<UdpHeader(source_port = 5000)>>                 a document, constructed
#
# `file` and `node` are the splice's own. Every other verb is registered by the
# package that owns its machinery, with `register_marker_function!(:name, f)`,
# and is called as `f(project, args...)`. A capitalised name constructs the type
# it names, of the types `register_pred_type!` offered. A `.pred` file is one
# such call, at file scale: see `PredFile.jl`.

"""
    FileDocument

A document that owns a text file. Every direct subtype declares two
`@document` fields — `filename::String` and a format-native `content`
— so `get_filename(f)` and `get_file_content(f)` work uniformly.

The abstract type is one of *two* ways to opt in; the other is the
`is_file_document` trait (see below), for types that already have an
incompatible supertype in their own domain.
"""
abstract type FileDocument <: Document end

"""
    is_file_document(x) -> Bool

The predicate every check of the save and the load goes through: a file
document is a cut in the graph and a file on disk.

Defaults to `false`. Every `FileDocument` inherits `true`. A type that already
has a supertype of its own opts in with a method:

    is_file_document(::MyDomainFile) = true

and contributes the same lines a `FileDocument` does: `get_file_domain`,
`parse_file_content`, `make_reference_leaf`, `find_reference_marker` and
`emit_text`.
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
get_filename(f) = unwrap_cell(getfield(f, :filename))

"""
    content(f) -> Any

The format-native content of this file document — the parsed tree for a
`JsonFile`, a raw `String` for a `TextFile`.

Default reads through the `content` field, which every file document has:
the save copies it, and the load fills it.
"""
get_file_content(f) = unwrap_cell(getfield(f, :content))

"""
    emit_text(f) -> String

Render a file document to the exact text that goes on disk. Concrete
types override this: a raw-string leaf (`TextFile`) returns `content`,
a parsed leaf (`JsonFile`, `XmlFile`, `JuliaFile`, `MarkdownFile`)
projects `content` through the visual layer's `print_natural_text`. The
default here just errors so a missing override fails loudly.
"""
emit_text(f) =
    error("emit_text: no method defined for ", typeof(f),
          " — every file document must contribute one (via `<: FileDocument` or the `is_file_document` trait)")

# ── Registry: extension → concrete FileDocument type ──────────────────────

const _FILE_DOCUMENT_TYPES = Dict{String, Type}()

"""
    register_file_document_type!(extension::AbstractString, T::Type)

Wire an extension (e.g. `".json"`) to the concrete type that owns it.
The load consults this registry when it opens a file by name. `T` may be
a `FileDocument` subtype or a trait-based opt-in; the registry doesn't
restrict.

Registering `""` is fine — the empty extension is the fallback
(`TextFile` claims it so any path with no extension loads as plain
text).
"""
function register_file_document_type!(extension::AbstractString, T::Type)
    _FILE_DOCUMENT_TYPES[String(extension)] = T
    T
end

"""
    get_file_document_type(path::AbstractString) -> Type

Look up the concrete file-document type for `path` by its extension
(case-insensitive). Errors if no format has claimed the extension —
better a loud miss at load time than a silently-wrong parse.
"""
function get_file_document_type(path::AbstractString)
    ext = lowercase(splitext(path)[2])
    haskey(_FILE_DOCUMENT_TYPES, ext) && return _FILE_DOCUMENT_TYPES[ext]
    error("get_file_document_type: no file document registered for extension ",
          repr(ext), " — call register_file_document_type!(", repr(ext), ", …)")
end

# ── The marker language ────────────────────────────────────────────────────
#
# `<<expr>>` where `expr` is a call over the registered vocabulary whose
# arguments are literals or nested calls. Julia parses it; the
# interpreter in `FileSplice.jl` runs it. See the head of this file.

const _MARKER_FUNCTIONS = Dict{Symbol, Any}()

"""
    register_marker_function!(name::Symbol, f) -> f

Add `name` to the marker vocabulary. `f` is called as
`f(project::FileProject, args...)` with the marker's evaluated
arguments, and returns the value the marker stands for. Register from
a module's `__init__` (the registry is runtime state, not baked into
the precompiled image).
"""
function register_marker_function!(name::Symbol, f)
    previous = get(_MARKER_FUNCTIONS, name, nothing)
    # First registration wins, as it does for the natural-syntax table. Two
    # formats that both want one verb must share it through a generic (see
    # `get_document_section`), because a silent overwrite makes the winner depend on
    # which `__init__` ran last, and the loser fails only at load time.
    if previous !== nothing && previous !== f
        @warn "register_marker_function!: the verb is already registered — keeping the first" name
        return previous
    end
    _MARKER_FUNCTIONS[name] = f
    f
end

"""
    get_marker_function(name::Symbol) -> f or nothing

The vocabulary entry for `name`, or `nothing` when the name is not
registered.
"""
get_marker_function(name::Symbol) = get(_MARKER_FUNCTIONS, name, nothing)

marker_function_names() = sort!(String[String(k) for k in keys(_MARKER_FUNCTIONS)])

const _MARKER_OPEN  = "<<"
const _MARKER_CLOSE = ">>"

"""
    parse_marker_text(text::AbstractString) -> Union{Nothing, String}

Recognise a marker. Returns the marker's **body source** verbatim, or
`nothing` when `text` is not marker-shaped — which is not an error:
the caller (a format's `find_reference_marker`) uses `nothing` to leave
the leaf as it is. Surrounding whitespace is ignored, so a fenced
block's body works as-is.

Recognition is syntactic only: the body must parse as a restricted
call expression. Whether its function is in the vocabulary is settled
when the marker is evaluated, so a marker naming a function some not-yet-loaded
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

# A type name, by the convention every `@document` follows: an identifier that
# starts with a capital. It is the whole difference between `file("a.md")` and
# `MarkdownFile("a.md")` — one names a vocabulary function, the other a type.
_is_type_name(name::Symbol) =
    (text = String(name); Base.isidentifier(text) && isuppercase(first(text)))

# The types a file may construct, by name. The serialization layer knows nothing
# about which modules a project may name, so a package offers what its files may
# hold and nothing else can be built.
const _PRED_TYPES = Dict{String,Type}()

"""
    register_pred_type!(T) -> T

Offer `T` to a file: a marker naming it constructs one, and a `.pred` file may
hold one. Nothing is offered by default, so a file can never name a type the
session did not put on this list.

Runtime state, so register it from `__init__`.
"""
function register_pred_type!(T::Type)
    _PRED_TYPES[String(nameof(T))] = T
    T
end

"The type `name` names, or `nothing` when nothing offered it."
get_pred_type(name::AbstractString) = get(_PRED_TYPES, String(name), nothing)

# Whether `T` is offered to a file by name. A `@document` type is parametric in
# the kind of each of its cells, so what a package registers is the name and
# every layout of it answers to that name.
function is_pred_type(T::Type)
    registered = get(_PRED_TYPES, String(nameof(T)), nothing)
    registered === nothing && return false
    registered === T || T <: registered
end

is_pred_type(::Any) = false

# Parse a marker body, returning the expression when it is in the
# restricted subset and `nothing` otherwise. `raise=false` turns a
# syntax error into an `Expr(:error, …)`, which fails the shape check
# like any other non-call.
function _parse_marker_expression(body::AbstractString)
    expr = Meta.parse(String(body); raise=false, depwarn=false)
    _is_marker_call(expr) ? expr : nothing
end

# The subset: a call whose head is a plain name and whose arguments are
# literals, keyword arguments, or recursively such calls. No assignment, no
# control flow, no bare names — a marker is data that happens to read as Julia.
#
# Keywords are in the subset because a document is CONSTRUCTED by naming its
# fields: `UdpHeader(source_port = 5000)` is the same statement as
# `{"$doctype": "UdpHeader", "source_port": 5000}`, and a page should be able
# to write whichever reads better. A keyword's value is an argument like any
# other, so it is restricted the same way.
_is_marker_call(::Any) = false
function _is_marker_call(e::Expr)
    e.head === :call || return false
    isempty(e.args) && return false
    # An identifier, so an operator is not a marker: `1 + 1` parses as a call to
    # `+` with two literal arguments, and it is arithmetic rather than data.
    (e.args[1] isa Symbol && Base.isidentifier(String(e.args[1]))) || return false
    all(_is_marker_argument, @view e.args[2:end])
end

_is_marker_argument(x) = _is_marker_call(x) || _is_marker_literal(x)

function _is_marker_argument(e::Expr)
    e.head === :parameters && return all(_is_marker_argument, e.args)   # f(; a = 1)
    e.head === :kw && return Base.length(e.args) == 2 && e.args[1] isa Symbol &&
                             _is_marker_argument(e.args[2])
    # A vector of values, `options = ["a", "b"]`: a field of a document holds a
    # list as readily as it holds one value, and a list of literals is data by
    # the same argument every literal is.
    e.head === :vect && return all(_is_marker_argument, e.args)
    return _is_marker_call(e)
end

# `nothing` is written as the word it is, and the parser hands back the name
# rather than the value. It is the one bare name the subset takes: a field that
# holds nothing has to be writable, and there is no other way to spell it.
_is_marker_literal(x) = x isa AbstractString || x isa Number || x isa Char ||
                        x isa Bool || x === nothing || x === :nothing

# The expression printed in one canonical form, for an error message: so
# `file("a.json")` and `file( "a.json" )` read the same.
function _canonical_marker(e::Expr)
    io = IOBuffer()
    _print_canonical(io, e)
    String(take!(io))
end

function _print_canonical(io::IO, e::Expr)
    if e.head === :vect
        print(io, "[")
        for (i, a) in enumerate(e.args)
            i > 1 && print(io, ", ")
            _print_canonical(io, a)
        end
        return print(io, "]")
    end
    # A keyword prints as `name = value`, and the ones written after a `;` print
    # the same way as the ones written inline — two spellings of one call read
    # the same.
    e.head === :kw && return (print(io, e.args[1], " = "); _print_canonical(io, e.args[2]))
    if e.head === :parameters
        for (i, a) in enumerate(e.args)
            i > 1 && print(io, ", ")
            _print_canonical(io, a)
        end
        return
    end
    print(io, e.args[1], "(")
    first = true
    for a in @view e.args[2:end]
        first || print(io, ", ")
        first = false
        _print_canonical(io, a)
    end
    print(io, ")")
end

_print_canonical(io::IO, x::AbstractString) = print(io, repr(String(x)))
# The one name in the subset prints as the word, not as the symbol it parsed to.
_print_canonical(io::IO, x::Symbol) = print(io, x)
_print_canonical(io::IO, x) = print(io, repr(x))

# ── The `section` vocabulary function ──────────────────────────────────────

"""
    section(document, title)  [marker vocabulary]

The part of `document` headed `title`, in that document's own format. Addressing
a section by the words of its heading is what lets it survive being moved, and
what makes a renamed heading fail loudly instead of embedding the wrong part of
a page.

Open generic: a format adds a method for its own root type — markdown gathers
the blocks that follow a heading, RST returns the section node, which already
owns its blocks. One verb serves every format, because the marker registry holds
one function per name and two formats registering `:section` would leave the
winner to load order.
"""
function get_document_section end

get_document_section(document, title::AbstractString) =
    error("section(…): no section vocabulary for a ", typeof(document),
          " — the format registers one by adding a `get_document_section` method")

# A marker naming a file gets the file; the section lives in its content.
get_document_section(file::FileDocument, title::AbstractString) =
    get_document_section(get_file_content(file), title)

function marker_section(::Any, document, title)
    title isa AbstractString ||
        error("section(…): expected a title string, got ", typeof(title), " (", repr(title), ")")
    get_document_section(document, String(title))
end

# One module, one `__init__`: the registrations of every fragment run from here.
function __init__()
    register_marker_function!(:section, marker_section)
    register_file_document_type!("",      TextFile)
    register_file_document_type!(".txt",  TextFile)
    register_file_document_type!(".pred", PredFile)
end

# The write gate: skip the write when the emitted text matches what's
# already on disk. Reads as bytes, not as
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
