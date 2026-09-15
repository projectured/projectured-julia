# Fragment of `SerializationModule` — `PredFile`, the `.pred` file on disk.
#
# A `.pred` file holds one document, written as its own constructor:
#
#     TestRun(
#         name = "aloha",
#         options = ["a", "b"],
#         parameters = (lambda = 1.3, capacity = 8),
#     )
#
# That is the marker language at file scale, so the format is the interpreter
# beside it and nothing more. Three properties follow. The file cannot execute
# code, because the restricted subset is its reader. Only a type a package
# offered with `register_pred_type!` can be constructed, so a file cannot name
# what the session did not offer. And a cut in the save walk — `file("b.xml")`,
# `node(file("a.json"), "entries[1].value")` — is a call in the same
# vocabulary, so this format writes its own references.
#
# One file type covers every domain: the first token names the document type, so
# a domain gets a file notation by registering its types.

"""
    PredReference(marker)

A reference standing where a value would be in a `.pred` file: the call as it is
written, `file("b.xml")` or `node(file("a.json"), "entries[1].value")`. The
parser leaves one at every call that does not name a type, the load splices the
node it names into its place, and the save writes one where it cuts.
"""
mutable struct PredReference <: Document
    marker::String
end

Base.show(io::IO, r::PredReference) = print(io, "PredReference(", repr(r.marker), ")")

"""
    PredFile(filename, content)

A `.pred` file: any registered document, written as its own constructor.
`register_pred_type!` says which types a file may hold.
"""
@document struct PredFile <: FileDocument
    filename::String
    content::Any = nothing
end

# What a `.pred` file holds is a document of any registered type, so its domain
# is that registry rather than one type. A reference it already carries is its
# own too: a marker naming a file outside the loaded set stays a reference, and
# the file writes it back as it found it.
get_file_domain(::Type{<:PredFile}) = Document
is_file_domain_node(::PredFile, node) = is_pred_type(typeof(node)) || node isa PredReference

# A `.pred` file writes the call `pred_arguments` gives and nothing else, so
# that is what it walks. A field the call leaves out — the live half a document
# built for itself — is not written, not cut, and not an orphan. A field the
# call writes as a rendering — a formula's code, written as its text — holds
# no node the walk could reach, so it is not walked and not cut either.
is_written_in_file(file::PredFile, node, name::Symbol) =
    !(node isa Document) ||
    any(pair -> first(pair) === name && _holds_document(last(pair)), last(pred_arguments(node)))

_holds_document(value) =
    value isa Document || (value isa AbstractVector && any(element -> element isa Document, value))

# The reference this format spells: the call itself, printed where the value
# would be.
make_reference_leaf(::PredFile, marker::AbstractString) = PredReference(String(marker))
find_reference_marker(reference::PredReference) = reference.marker

parse_file_content(::Type{<:PredFile}, text::AbstractString) = parse_pred_text(text)

function emit_text(f::PredFile)
    try
        print_pred_text(get_file_content(f)) * "\n"
    catch e
        e isa FileCutException || rethrow()
        throw(FileCutException("save: " * repr(get_filename(f)) * " " * e.message))
    end
end

# ── What a document's file form is ───────────────────────────────────────────

"""
    pred_arguments(document) -> (positional, keywords)

The arguments of the call a `.pred` file writes for `document`. The default
writes every declared field as a keyword, in declaration order: a document made
of data is its fields.

A document that also holds what it did not read — a workbench built for a
model, the module a source ran in — says here what its file half is, and reads
it back in [`make_pred_document`](@ref). The two are inverses, and a value the
notation cannot write is refused at save whichever of them produced it.
"""
function pred_arguments(document)
    keywords = Pair{Symbol,Any}[]
    for name in fieldnames(typeof(document))
        name === :selection && continue
        raw = getfield(document, name)
        push!(keywords, name => (raw isa AbstractCell ? raw[] : raw))
    end
    (), keywords
end

"""
    make_pred_document(::Type{T}, positional, keywords) -> T

The document a call in a file builds. The default is the constructor itself.
The inverse of [`pred_arguments`](@ref): a type whose file form is a reduced one
builds the rest of itself here.
"""
make_pred_document(T::Type, positional, keywords) =
    isempty(keywords) ? T(positional...) :
    isempty(positional) ? T(; keywords...) : T(positional...; keywords...)

# ── The reader ───────────────────────────────────────────────────────────────

"""
    parse_pred_text(text) -> Document

The document `text` constructs. A call naming a registered type builds one; any
other call is a reference, which the load splices once the whole set is parsed.
"""
function parse_pred_text(text::AbstractString)
    expression = _parse_marker_expression(strip(text))
    expression === nothing &&
        error("a .pred file holds one marker expression — a document written as its ",
              "constructor — and this is not one: ",
              repr(first(split(strip(String(text)), '\n'))))
    _evaluate_pred(expression)
end

_evaluate_pred(literal) = literal === :nothing ? nothing : literal
# `:holds` is a symbol literal. The marker grammar admits one only when its name
# is an identifier, so the value it reads is the one the writer printed.
_evaluate_pred(quoted::QuoteNode) = quoted.value

function _evaluate_pred(e::Expr)
    e.head === :vect && return Any[_evaluate_pred(a) for a in e.args]
    if e.head === :tuple
        fields = _marker_tuple_fields(e)
        isempty(fields) && return ()
        if _is_marker_tuple_field(first(fields))
            return NamedTuple{Tuple(Symbol[f.args[1] for f in fields])}(
                Tuple(Any[_evaluate_pred(f.args[2]) for f in fields]))
        end
        return Tuple(Any[_evaluate_pred(f) for f in fields])
    end
    verb = e.args[1]::Symbol
    # A call over the vocabulary rather than a type names a node somewhere else.
    # It is left as a reference: which file it names is settled by the set the
    # load was given, and that is the splice's business, not the parser's.
    _is_type_name(verb) || return PredReference(_canonical_marker(e))
    T = get_pred_type(String(verb))
    T === nothing && error("a .pred file may not construct a ", verb,
                           " — a package calls register_pred_type!(", verb,
                           ") to offer a type a file may name")
    positional = Any[]
    keywords = Pair{Symbol,Any}[]
    for argument in @view e.args[2:end]
        if argument isa Expr && argument.head === :parameters
            for kw in argument.args
                push!(keywords, kw.args[1] => _evaluate_pred(kw.args[2]))
            end
        elseif argument isa Expr && argument.head === :kw
            push!(keywords, argument.args[1] => _evaluate_pred(argument.args[2]))
        else
            push!(positional, _evaluate_pred(argument))
        end
    end
    make_pred_document(T, positional, keywords)
end

# ── The writer ───────────────────────────────────────────────────────────────

"""
    print_pred_text(document) -> String

`document` as its own constructor, in one canonical form: every declared field
in declaration order, and one way to write each value. The write gate compares
bytes, so two saves of one document must print the same text.

Throws a [`FileCutException`](@ref) naming the field when a value is outside the
notation: a string, a number, a character, a bool, a symbol, `nothing`, a vector
of those, a registered document, and a reference are all of it.
"""
function print_pred_text(document)
    io = IOBuffer()
    _print_pred_value(io, document, "", 0)
    String(take!(io))
end

const _PRED_INDENT = "    "

_print_pred_value(io::IO, reference::PredReference, where, indent) = print(io, reference.marker)
_print_pred_value(io::IO, x::AbstractString, where, indent) = print(io, repr(String(x)))
_print_pred_value(io::IO, ::Nothing, where, indent) = print(io, "nothing")
# A symbol prints as `:name`. One whose name is not an identifier would print as
# a call, which the reader takes for a type, so it is refused instead.
function _print_pred_value(io::IO, x::Symbol, where, indent)
    Base.isidentifier(String(x)) || _refuse_pred_value(x, where)
    print(io, ":", x)
end
_print_pred_value(io::IO, x::Union{Bool,Integer,AbstractFloat,Char}, where, indent) =
    print(io, repr(x))

function _print_pred_value(io::IO, v::Tuple, where, indent)
    isempty(v) && return print(io, "()")
    print(io, "(")
    for (index, element) in enumerate(v)
        index > 1 && print(io, ", ")
        _print_pred_value(io, element, where, indent)
    end
    print(io, Base.length(v) == 1 ? ",)" : ")")
end

function _print_pred_value(io::IO, v::NamedTuple, where, indent)
    isempty(v) && return print(io, "(;)")
    print(io, "(")
    for (index, name) in enumerate(keys(v))
        index > 1 && print(io, ", ")
        print(io, name, " = ")
        _print_pred_value(io, v[name],
                          isempty(where) ? String(name) : where * "." * String(name), indent)
    end
    # One field needs the comma to stay a named tuple rather than a parenthesis.
    print(io, Base.length(v) == 1 ? ",)" : ")")
end

# A list of values reads on one line; a list of documents is a list of blocks,
# and one per line is the only way to read it.
function _print_pred_value(io::IO, v::AbstractVector, where, indent)
    isempty(v) && return print(io, "[]")
    if any(e -> e isa Document && !(e isa PredReference), v)
        print(io, "[\n")
        for element in v
            print(io, _PRED_INDENT^(indent + 1))
            _print_pred_value(io, element, where, indent + 1)
            print(io, ",\n")
        end
        return print(io, _PRED_INDENT^indent, "]")
    end
    print(io, "[")
    for (index, element) in enumerate(v)
        index > 1 && print(io, ", ")
        _print_pred_value(io, element, where, indent)
    end
    print(io, "]")
end

# One field to a line. A file is read in a diff as much as it is read whole, and
# a changed field should be a changed line.
function _print_pred_value(io::IO, document::Document, where, indent)
    is_pred_type(typeof(document)) || _refuse_pred_value(document, where)
    positional, keywords = pred_arguments(document)
    print(io, nameof(typeof(document)), "(")
    isempty(positional) && isempty(keywords) && return print(io, ")")
    print(io, "\n")
    for value in positional
        print(io, _PRED_INDENT^(indent + 1))
        _print_pred_value(io, value, where, indent + 1)
        print(io, ",\n")
    end
    for (name, value) in keywords
        print(io, _PRED_INDENT^(indent + 1), name, " = ")
        _print_pred_value(io, value,
                          isempty(where) ? String(name) : where * "." * String(name),
                          indent + 1)
        print(io, ",\n")
    end
    print(io, _PRED_INDENT^indent, ")")
end

_print_pred_value(io::IO, value, where, indent) = _refuse_pred_value(value, where)

function _refuse_pred_value(value, where)
    at = isempty(where) ? "" : " at " * where
    throw(FileCutException(
        "cannot write a " * string(typeof(value)) * at *
        " — the .pred notation holds a string, a number, a character, a bool, " *
        "nothing, a vector of those, a group of them, a mapping of names to " *
        "them, a registered document, and a reference" *
        (value isa Document ? "; call register_pred_type!(" * string(nameof(typeof(value))) *
                              ") to offer this type" : "")))
end
