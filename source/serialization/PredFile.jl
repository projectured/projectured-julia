# Fragment of `SerializationModule` — `PredFile`, the `.pred` file on disk.
#
# A `.pred` file holds one document, written as its own constructor:
#
#     TestRun(name = "aloha", options = ["a", "b"], count = 2)
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

function _evaluate_pred(e::Expr)
    e.head === :vect && return Any[_evaluate_pred(a) for a in e.args]
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
    isempty(keywords) && return T(positional...)
    isempty(positional) && return T(; keywords...)
    T(positional...; keywords...)
end

# ── The writer ───────────────────────────────────────────────────────────────

"""
    print_pred_text(document) -> String

`document` as its own constructor, in one canonical form: every declared field
in declaration order, and one way to write each value. The write gate compares
bytes, so two saves of one document must print the same text.

Throws a [`FileCutException`](@ref) naming the field when a value is outside the
notation: a string, a number, a character, a bool, `nothing`, a vector of those,
a registered document, and a reference are all of it.
"""
function print_pred_text(document)
    io = IOBuffer()
    _print_pred_value(io, document, "")
    String(take!(io))
end

_print_pred_value(io::IO, reference::PredReference, where) = print(io, reference.marker)
_print_pred_value(io::IO, x::AbstractString, where) = print(io, repr(String(x)))
_print_pred_value(io::IO, ::Nothing, where) = print(io, "nothing")
_print_pred_value(io::IO, x::Union{Bool,Integer,AbstractFloat,Char}, where) = print(io, repr(x))

function _print_pred_value(io::IO, v::AbstractVector, where)
    print(io, "[")
    for (index, element) in enumerate(v)
        index > 1 && print(io, ", ")
        _print_pred_value(io, element, where)
    end
    print(io, "]")
end

function _print_pred_value(io::IO, document::Document, where)
    is_pred_type(typeof(document)) || _refuse_pred_value(document, where)
    print(io, nameof(typeof(document)), "(")
    first = true
    for name in fieldnames(typeof(document))
        name === :selection && continue
        first || print(io, ", ")
        first = false
        print(io, name, " = ")
        raw = getfield(document, name)
        _print_pred_value(io, raw isa AbstractCell ? raw[] : raw,
                          isempty(where) ? String(name) : where * "." * String(name))
    end
    print(io, ")")
end

_print_pred_value(io::IO, value, where) = _refuse_pred_value(value, where)

function _refuse_pred_value(value, where)
    at = isempty(where) ? "" : " at " * where
    throw(FileCutException(
        "cannot write a " * string(typeof(value)) * at *
        " — the .pred notation holds a string, a number, a character, a bool, " *
        "nothing, a vector of those, a registered document, and a reference" *
        (value isa Document ? "; call register_pred_type!(" * string(nameof(typeof(value))) *
                              ") to offer this type" : "")))
end
