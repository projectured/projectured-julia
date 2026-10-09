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
# and is called as `f(project, args...)`. A capitalised name constructs the
# loaded document type it names. A `.pred` file is one such call, at file scale:
# see `PredFile.jl`.

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
    get_file_content(file) -> Any

The value of the `content` field of `file`: what the file holds, as its format
reads it — the parsed tree for a `JsonFile`, a raw `String` for a `TextFile`. An
application that keeps a history of each file keeps the history in this field,
so the answer is then the history and not the tree. To reach the document a
person edits, through the history too, use [`get_edited_document`](@ref). Given a
layer that shows a file, such as the scroll pane of a file tab, it answers the
content of that file.

Default reads through the `content` field: the save copies it, and the load
fills it. A file whose whole node is its content answers with the node itself and
says so with [`is_own_content`](@ref).
"""
function get_file_content(f)
    is_file_document(f) && return unwrap_cell(getfield(f, :content))
    # A layer a person sees through, such as the scroll pane of a file tab, answers
    # the content of the file it shows.
    field = get_edited_field(f)
    field === nothing ? unwrap_cell(getfield(f, :content)) : get_file_content(getproperty(f, field))
end
get_file_content(file::ReferencedDocument) = get_file_content(get_document(file))

"""
    is_own_content(file) -> Bool

Whether the file node is itself the root of its content. A `JsonFile` holds its
tree in a `content` field and answers `false`; a file whose node is the tree
answers `true`, so the save rebuilds that node instead of cutting it, and the
load takes what the parser built rather than wrapping it.

Default `false`. A file that answers `true` defines `get_file_content(f) = f`
and builds itself from its text with [`make_file`](@ref).
"""
is_own_content(::Any) = false

# A person edits the document a file holds, or the file itself when it is its own
# content.
get_edited_field(file::FileDocument) = is_own_content(file) ? nothing : :content

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

"""
    has_file_document_type(path::AbstractString) -> Bool

Whether a format claimed the extension of `path`, so that
[`get_file_document_type`](@ref) answers instead of raising an error.
"""
has_file_document_type(path::AbstractString) =
    haskey(_FILE_DOCUMENT_TYPES, lowercase(splitext(path)[2]))

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

# ── The types a file may name ────────────────────────────────────────────────
#
# A file names a document by the name of its schema, the name written after
# `struct`, and the reader builds the type that the schema's module binds to
# that name, because that is the type a programmer calls. Every loaded subtype
# of `Document` may be named, so no package lists its types, and a type that is
# data but not a document may be named when its package says so with
# `is_pred_constructible`. The names are read from the loaded modules when a
# name is not known yet, because a package that is loaded later brings types of
# its own.

"""
    is_pred_constructible(::Type) -> Bool

Whether a file may name a type and have one built. `true` for a `Document`, and
`false` for anything else unless the package that owns the type adds a method,
as a wire format that is data does. A type that must not be built from a file
says so in its method of [`make_pred_document`](@ref).
"""
is_pred_constructible(::Type{T}) where {T} = T <: Document

# The name of each loaded document type, to its constructor, or to every
# constructor when two loaded types have one name.
const _PRED_NAMES = Dict{String,Any}()
const _PRED_NAMES_LOCK = ReentrantLock()

"""
    get_pred_type(name) -> Type or nothing

The loaded type that a file names with `name`, or `nothing` when no loaded type
that [`is_pred_constructible`](@ref) has that name. A name that two such types
have is an error that names both, because a file can not say which one it
means.
"""
function get_pred_type(name::AbstractString)
    key = String(name)
    found = lock(_PRED_NAMES_LOCK) do
        haskey(_PRED_NAMES, key) || _collect_pred_names!()
        get(_PRED_NAMES, key, nothing)
    end
    found isa Vector || return found
    error("the name ", key, " names more than one loaded type that a file may build: ",
          join((string(parentmodule(T), ".", nameof(T)) for T in found), " and "),
          ", so a file can not say which one it means")
end

# Read the names of the loaded document types again, from every loaded module
# and from `Main`, which holds the types a person defines at the prompt.
function _collect_pred_names!()
    empty!(_PRED_NAMES)
    seen = Set{Module}()
    for m in Base.loaded_modules_array()
        _collect_pred_names!(m, seen)
    end
    _collect_pred_names!(Main, seen)
    nothing
end

function _collect_pred_names!(m::Module, seen::Set{Module})
    m in seen && return nothing
    push!(seen, m)
    for name in names(m; all = true)
        isdefined(m, name) || continue
        value = getfield(m, name)
        if value isa Module
            value !== m && parentmodule(value) === m && _collect_pred_names!(value, seen)
        elseif (value isa DataType || value isa UnionAll) && value !== Union{} &&
               is_pred_constructible(value)
            constructor = _get_schema_type(value)
            _add_pred_name!(String(nameof(value)), constructor)
            _add_pred_name!(String(get_document_schema_name(value)), constructor)
        end
    end
    nothing
end

function _add_pred_name!(key::String, constructor)
    found = get(_PRED_NAMES, key, nothing)
    if found === nothing
        _PRED_NAMES[key] = constructor
    elseif found isa Vector
        any(T -> T === constructor, found) || push!(found, constructor)
    elseif found !== constructor
        _PRED_NAMES[key] = Any[found, constructor]
    end
    nothing
end

# The type a module binds to the schema name of `T`, or `T` when the name is not
# bound to a type there. A layout of a `@document` schema is a type of its own,
# and a concrete layout has no keyword constructor.
function _get_schema_type(T::Type)
    home = parentmodule(T)
    schema = get_document_schema_name(T)
    isdefined(home, schema) || return T
    bound = getfield(home, schema)
    bound isa Type ? bound : T
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
# literals, keyword arguments, or recursively such calls. No assignment, no
# control flow, and no bare name but `nothing` and the name of a type that a file
# may build — a marker is data that happens to read as Julia.
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
    # A mapping of names to values, `parameters = (lambda = 1.3, capacity = 8)`,
    # and a group of values, `("mm1k.sink", "lifeTime")`. Both are Julia's own
    # tuple, so both are literals and not calls: the first is what a field holds
    # when it holds a set of named numbers, and the second is what a mapping
    # becomes when its keys are paths rather than names.
    e.head === :tuple && return all(_is_marker_argument, e.args) &&
        (all(_is_marker_tuple_field, e.args) || !any(_is_marker_tuple_field, e.args))
    (e.head === :(=) || e.head === :kw) && return Base.length(e.args) == 2 &&
        e.args[1] isa Symbol && _is_marker_argument(e.args[2])
    return _is_marker_call(e)
end

# Whether a tuple's element names a field, which is what tells one kind of tuple
# from the other.
_is_marker_tuple_field(x) = x isa Expr &&
    (x.head === :(=) || x.head === :kw || x.head === :parameters)

# The elements of a tuple expression, in the order written. Both spellings of a
# named tuple reach here: `(a = 1, b = 2)` and `(; a = 1, b = 2)`.
function _marker_tuple_fields(e::Expr)
    fields = Any[]
    for argument in e.args
        if argument isa Expr && argument.head === :parameters
            append!(fields, argument.args)
        else
            push!(fields, argument)
        end
    end
    fields
end

# `nothing` is written as the word it is, and the parser hands back the name
# rather than the value. It is the one bare name the subset takes: a field that
# holds nothing has to be writable, and there is no other way to spell it.
_is_marker_literal(x) = x isa AbstractString || x isa Number || x isa Char ||
                        x isa Bool || x === nothing || x === :nothing ||
                        _is_marker_symbol(x) || _is_marker_type_name(x)

# `PrimitiveNumber` bare is a type as a value, as a field that limits what a
# document can become holds it. Only a name that starts with a capital passes, and
# the reader looks it up among the types that a file may build, so it runs nothing.
_is_marker_type_name(x) = x isa Symbol && _is_type_name(x)

# The value of a bare name of a marker: `nothing`, or the type that a file may
# build with that name.
function _evaluate_marker_name(name::Symbol)
    name === :nothing && return nothing
    T = get_pred_type(String(name))
    T === nothing && error("a marker names ", name,
                           ", and no loaded type that a file may build has that name")
    T
end

# `:holds` is a symbol literal, and so is a quoted operator such as `:+` or
# `:(=)`, which a Julia document holds. `Symbol("a b")` is a call, and a call
# names a type or a verb, never a value.
_is_marker_symbol(x) = x isa QuoteNode && x.value isa Symbol

# The expression printed in one canonical form, for an error message: so
# `file("a.json")` and `file( "a.json" )` read the same.
function _canonical_marker(e::Expr)
    io = IOBuffer()
    _print_canonical(io, e)
    String(take!(io))
end

_print_canonical(io::IO, quoted::QuoteNode) = print(io, repr(quoted.value))

function _print_canonical(io::IO, e::Expr)
    if e.head === :tuple
        fields = _marker_tuple_fields(e)
        isempty(fields) && return print(io, "()")
        named = _is_marker_tuple_field(first(fields))
        print(io, "(")
        for (i, a) in enumerate(fields)
            i > 1 && print(io, ", ")
            named ? (print(io, a.args[1], " = "); _print_canonical(io, a.args[2])) :
                    _print_canonical(io, a)
        end
        return print(io, Base.length(fields) == 1 ? ",)" : ")")
    end
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
