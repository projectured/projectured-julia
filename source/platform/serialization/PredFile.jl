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
# code, because the restricted subset is its reader. Only a loaded document type
# can be constructed, so a file names data and nothing else. And a cut in the
# save walk — `file("b.xml")`,
# `node(file("a.json"), "entries[1].value")` — is a call in the same
# vocabulary, so this format writes its own references.
#
# One file type covers every domain: the first token names the document type, so
# a domain gets a file notation by registering its types.
#
# A document of a text format that no file of the set writes, such as a JSON value
# or a Markdown page that a workflow holds as an element, is written in the text
# of its format, inside a string tagged with the extension of the format:
#
#     elements = [
#         json"""
#         {"port": 5000}
#         """,
#     ],
#
# The load reads the string with the parser of that format.

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
    PredText(extension, text)

A document of a text format standing where a value would be in a `.pred` file:
`text` is the document written in the format that owns `extension`, such as
`".json"`, and the file writes it as a string tagged with the extension without
its dot, such as `json"…"`. The save leaves one where it writes a node inline.
"""
struct PredText <: Document
    extension::String
    text::String
end

Base.show(io::IO, t::PredText) = print(io, "PredText(", repr(t.extension), ", ", repr(t.text), ")")

"""
    PredFile(filename, content)

A `.pred` file: any document, written as its own constructor.
"""
@document struct PredFile <: FileDocument
    filename::String
    content::Any = nothing
end

# What a `.pred` file holds is a document of any type that no text format owns.
# A node of the domain of a format, such as a JSON value or an XML element,
# belongs to a file of that format, so a `.pred` file that holds one writes a
# reference to that file, and writes it inline, in the text of its format, when
# no file of the set writes it. A reference it already carries is its own too: a
# marker naming a file outside the loaded set stays a reference, and the file
# writes it back as it found it.
get_file_domain(::Type{<:PredFile}) = Document
is_file_domain_node(::PredFile, node) = node isa PredReference || is_pred_document(node)

is_written_inline(::PredFile, node) = _find_inline_extension(node) !== nothing

# The extension of the format of `node`, when its name without the dot can tag a
# string: `".json"`, but not an extension such as `".c++"`.
function _find_inline_extension(node)
    extension = find_file_extension(node)
    extension !== nothing && Base.isidentifier(extension[2:end]) ? extension : nothing
end

# The text of `node` is what a file of its format alone would hold, so a node that
# it holds at two places is one node when the text is read again.
function make_inline_leaf(file::PredFile, node, path::Reference)
    extension = _find_inline_extension(node)
    filename = _INLINE_FILENAME * extension
    text = try
        cut_file_text(get_file_document_type(filename)(filename, node))
    catch e
        e isa FileCutException || rethrow()
        throw(FileCutException(repr(get_filename(file)) * " writes the " * string(nameof(typeof(node))) *
                               " at " * print_path_text(path) * " as the text of a " * extension *
                               " file, and " * e.message))
    end
    PredText(extension, text)
end

# The name of the file that a text of a format is, which a marker of the text into
# itself names.
const _INLINE_FILENAME = "inline"

# The document that a text of a format holds, read by the parser of the format and
# with its markers into itself joined.
function _read_inline_text(tag::Symbol, text::AbstractString)
    filename = _INLINE_FILENAME * "." * String(tag)
    has_file_document_type(filename) ||
        error("a .pred file holds a text tagged ", tag, ", and no loaded format has the extension .", tag)
    file = make_file(get_file_document_type(filename), filename, text)
    _splice!(FileProject(".", Any[file]))
    get_file_content(file)
end

"""
    is_pred_document(document) -> Bool

Whether a `.pred` file holds `document` itself: a document that the domain of no
registered text format owns. A JSON value or an XML element belongs to a file of
its format, and a `.pred` file writes a reference to that file.
"""
is_pred_document(document) = document isa Document && !_is_format_node(document)

# Whether `node` is in the domain of a registered format other than `.pred`. The
# domain passes an inference barrier: inference merges the domain `Union{}` of a
# text file with another domain `D` into a subtype of `D`, and folds the `isa` to
# the answer for `D` (Julia 1.11 to 1.13), so with no other format a `.pred` file
# would take every document for a node of a text file.
_is_format_node(node) =
    any(values(_FILE_DOCUMENT_TYPES)) do T
        domain = Base.inferencebarrier(get_file_domain(T))
        domain !== Document && node isa domain
    end

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
A positional collection writes the list of its elements as its one argument.

A document that also holds what it did not read — a `PaneTree`'s drag in
progress, an `Assistant`'s API key and conversation — says here what its file
half is, and reads it back in [`make_pred_document`](@ref). The two are
inverses, and a value the notation cannot write is refused at save whichever
of them produced it.
"""
function pred_arguments(document)
    # A collection that is itself held in a vector, such as a row of a table, is
    # the call that takes the list of what its cells hold.
    is_element_collection(document) && return (Any[element for element in document],), ()
    keywords = Pair{Symbol,Any}[]
    for name in fieldnames(typeof(document))
        is_view_state_field(typeof(document), name) && continue
        raw = getfield(document, name)
        value = raw isa AbstractCell ? raw[] : raw
        # A collection of cells is written as the list of what the cells hold.
        is_element_collection(value) && (value = Any[element for element in value])
        push!(keywords, name => value)
    end
    (), keywords
end

"""
    make_pred_document(::Type{T}, positional, keywords) -> T

The document a call in a file builds. The default is the constructor itself.
A type with no keyword constructor, such as a `@document` whose fields have no
defaults, is built from its fields in their declared order. The inverse of
[`pred_arguments`](@ref): a type whose file form is a reduced one builds the rest
of itself here, and a type that a file must not build raises an error here.
"""
function make_pred_document(T::Type, positional, keywords)
    isempty(keywords) && return T(positional...)
    isempty(positional) || return T(positional...; keywords...)
    names = Tuple(first(keyword) for keyword in keywords)
    hasmethod(T, Tuple{}, names) && return T(; keywords...)
    values = Dict{Symbol,Any}(keywords)
    fields = Symbol[name for name in fieldnames(T) if !is_view_state_field(T, name)]
    for name in fields
        haskey(values, name) ||
            error("a .pred file builds ", nameof(T), " from its fields, and it gives no ", name)
    end
    T((values[name] for name in fields)...)
end

# ── The reader ───────────────────────────────────────────────────────────────

"""
    parse_pred_text(text) -> Document

Build the document that a saved text describes.

Use it to load what was written to a file: the text is the document written as
the call that builds it, and this runs that call. A call naming a loaded
document type builds one; any other call is a reference, which the load splices once the
whole set is parsed.

# Example

    document = parse_pred_text(read("study.pred", String))

See also `print_pred_text`, which writes the text this reads.
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
_evaluate_pred(name::Symbol) = _evaluate_marker_name(name)
# `:holds` is a symbol literal. The marker grammar admits one only when its name
# is an identifier, so the value it reads is the one the writer printed.
_evaluate_pred(quoted::QuoteNode) = quoted.value

function _evaluate_pred(e::Expr)
    e.head === :vect && return Any[_evaluate_pred(a) for a in e.args]
    _is_marker_text(e) && return _read_inline_text(_get_marker_text_tag(e), e.args[3])
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
    T === nothing && error("a .pred file names ", verb,
                           ", and no loaded type that a file may build has that name")
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

Write a document as the text that builds it again.

Use it to save a document to a file, to compare two documents by what they
would be saved as, or to read the data of a part that has no text of its own
domain, such as a widget, a chart or a graph. The text is the document's own
constructor call, and reading it back gives a document that prints the same text.

# Example

    write("notes.pred", print_pred_text(notes))
    println(print_pred_text(find_selected_part()))

See also `parse_pred_text`, which reads it back, and `print_natural_text`, which
prints a part of a domain that has a text of its own.

`document` as its own constructor, in one canonical form: every declared field
in declaration order, and one way to write each value. The write gate compares
bytes, so two saves of one document must print the same text.

Throws a [`FileCutException`](@ref) naming the field when a value is outside the
notation: a string, a number, a character, a bool, a symbol, `nothing`, a vector
of those, a document, a value of a type that [`is_pred_constructible`](@ref)
says a file may build, such a type by its bare name, and a reference are all of
it.
"""
function print_pred_text end

function print_pred_text(document)
    io = IOBuffer()
    _print_pred_value(io, document, "", 0)
    String(take!(io))
end

print_pred_text(document::ReferencedDocument) = print_pred_text(get_document(document))

const _PRED_INDENT = "    "

_print_pred_value(io::IO, reference::PredReference, where, indent) = print(io, reference.marker)

# A text of a format, one line of the text to a line of the file at the indent of
# the value, which the reader takes off again. A text that the indent would change,
# such as one whose every line starts with a space and that ends with no newline,
# is written with every quote escaped and no indent; a text that neither form
# holds, such as one with a carriage return, is refused.
function _print_pred_value(io::IO, value::PredText, where, indent)
    tag = value.extension[2:end]
    for written in (_print_indented_text(tag, value.text, _PRED_INDENT^indent),
                    tag * "\"" * sprint(Base.escape_raw_string, value.text) * "\"")
        _read_written_text(written) == value.text && return print(io, written)
    end
    throw(FileCutException("cannot write the text of a " * value.extension * " file" *
                           (isempty(where) ? "" : " at " * where) *
                           " — a tagged string of a .pred file can not hold it"))
end

function _print_indented_text(tag, text, margin)
    escaped = _escape_inline_text(text)
    lines = split(escaped, '\n')
    body = join((isempty(line) ? "" : margin * line for line in lines), "\n")
    tag * "\"\"\"\n" * body * (endswith(escaped, '\n') ? margin : "") * "\"\"\""
end

# `text` as the body of a tagged string: a quote that would be the third of a row,
# a quote of the row that ends the text, and a quote after a backslash take a
# backslash, and so does each backslash before such a quote or at the end.
function _escape_inline_text(text::AbstractString)
    io = IOBuffer()
    characters = collect(text)
    trailing = findlast(character -> character != '"', characters)
    backslashes = 0
    quotes = 0
    for (index, character) in enumerate(characters)
        if character == '\\'
            backslashes += 1
            continue
        end
        if character == '"' && (backslashes > 0 || quotes == 2 || trailing === nothing || index > trailing)
            print(io, "\\"^(2 * backslashes + 1), '"')
            quotes = 0
        else
            print(io, "\\"^backslashes, character)
            quotes = character == '"' ? quotes + 1 : 0
        end
        backslashes = 0
    end
    print(io, "\\"^(2 * backslashes))
    String(take!(io))
end

# The text that a written tagged string reads back to, or `nothing`.
function _read_written_text(written::AbstractString)
    expression = Meta.parse(written; raise = false, depwarn = false)
    _is_marker_text(expression) ? expression.args[3] : nothing
end

_print_pred_value(io::IO, x::AbstractString, where, indent) = print(io, repr(String(x)))
_print_pred_value(io::IO, ::Nothing, where, indent) = print(io, "nothing")
# A symbol prints as Julia quotes it: `:name`, or an operator as `:+` or `:(=)`,
# which the reader takes as a quoted symbol. One that does not read back as
# itself from that text, such as `Symbol("a b")`, which prints as a call that the
# reader would take for a type, is refused.
function _print_pred_value(io::IO, x::Symbol, where, indent)
    text = repr(x)
    parsed = try
        Meta.parse(text)
    catch exception
        exception isa Meta.ParseError || rethrow()
        nothing
    end
    (parsed isa QuoteNode && parsed.value === x) || _refuse_pred_value(x, where)
    print(io, text)
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

# A type that a file may build is its bare name, which the reader looks up as it
# looks up the name of a call: a field that limits what a document can become
# holds such types.
function _print_pred_value(io::IO, value::Type, where, indent)
    is_pred_constructible(value) || _refuse_pred_value(value, where)
    name = String(nameof(value))
    get_pred_type(name) === value || _refuse_pred_value(value, where)
    print(io, name)
end

# A value that is data but not a document, of a type that a file may build, is
# its call on one line: a size or a margin is one value in a diff, as a number is.
function _print_pred_value(io::IO, value, where, indent)
    is_pred_constructible(typeof(value)) || _refuse_pred_value(value, where)
    positional, keywords = pred_arguments(value)
    print(io, nameof(typeof(value)), "(")
    for (index, element) in enumerate(positional)
        index > 1 && print(io, ", ")
        _print_pred_value(io, element, where, indent)
    end
    for (index, (name, element)) in enumerate(keywords)
        (index > 1 || !isempty(positional)) && print(io, ", ")
        print(io, name, " = ")
        _print_pred_value(io, element,
                          isempty(where) ? String(name) : where * "." * String(name), indent)
    end
    print(io, ")")
end

function _refuse_pred_value(value, where)
    at = isempty(where) ? "" : " at " * where
    throw(FileCutException(
        "cannot write a " * string(typeof(value)) * at *
        " — the .pred notation holds a string, a number, a character, a bool, " *
        "nothing, a vector of those, a group of them, a mapping of names to " *
        "them, a document, a value of a type that a file may build, such a type, " *
        "a reference, and the text of a format"))
end
