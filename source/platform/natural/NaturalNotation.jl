# Fragment of `NaturalModule` — the natural notation of a document: the
# projection of a type of document to syntax, the format that writes a document,
# the `Expr` that runs it, and the fixed steps from syntax up to text, graphics
# and a string.

# ── What a domain declares ──────────────────────────────────────────────────

"""
    make_syntax_projection(type::Type; appearance::Appearance) -> Projection
    make_syntax_projection(format::FileFormat; appearance::Appearance) -> Projection

The projection of the documents of `type` to syntax: the natural notation of
the type, which [`make_natural_projection`](@ref) takes up to text, graphics or
a string. `appearance` is the `Appearance` of the editor, from which the
projection takes the scaled theme of its domain. A package that owns a type of
document adds a method for it, usually for the root of its domain:

    make_syntax_projection(::Type{<:YamlDocument}; appearance) =
        YamlToSyntax(; theme = get_scaled_theme!(appearance, YamlTheme),
                     syntax_theme = get_scaled_theme!(appearance, SyntaxTheme))

The method for a format gives the notation of the domain of the format
([`get_file_format_domain`](@ref)). A second format of a domain, whose string is
another syntax, declares a method of its own. This module has no method for a
type, so a caller that is not sure asks `hasmethod` first.
"""
function make_syntax_projection end

make_syntax_projection(format::FileFormat; appearance::Appearance) =
    make_syntax_projection(get_file_format_domain(format); appearance)

"""
    make_syntax_to_text_projection(; appearance::Appearance) -> Projection

The projection that prints a syntax tree as text: the step of the ladder from
`:syntax` to `:text`. This module declares the function with no method; the
package that defines the syntax tree adds the one method, because this module
must not name it.
"""
function make_syntax_to_text_projection end

"""
    find_natural_file_format(document) -> FileFormat or nothing

The format that writes `document` when nobody names one: the format of its
domain, such as `YamlFileFormat()` for a `YamlDocument`, or `nothing` for a
document that no format writes, such as a fault log. A domain adds a method for
its documents:

    find_natural_file_format(::YamlDocument) = YamlFileFormat()

# Example

    find_natural_file_format(parse_natural_text(:yml, "a: 1"))   # YamlFileFormat()
"""
find_natural_file_format(document) = nothing

"""
    make_document_expression(document) -> Expr

The `Expr` that runs `document`, in the shape that `Meta.parseall` gives. A
domain whose documents are code adds a method for them, as the Julia domain does.
Any other document runs as its own value, `Expr(:toplevel, QuoteNode(document))`,
so the evaluation uses that very object and never a copy of it.
"""
make_document_expression(document) = Expr(:toplevel, QuoteNode(document))

# ── Reading the seams ───────────────────────────────────────────────────────

# Whether the documents of `type`, or of the domain of `format`, have a syntax
# notation. `Union{}` is the domain of a format whose string is no document.
_has_syntax_projection(type::Type) =
    type !== Union{} && hasmethod(make_syntax_projection, Tuple{Type{type}})
_has_syntax_projection(format::FileFormat) = _has_syntax_projection(get_file_format_domain(format))

# Whether the natural text reads and writes the documents of `format`: the format
# parses a string, and its documents have a syntax notation.
_is_natural_format(format::FileFormat) =
    hasmethod(parse_document_string, Tuple{typeof(format), String}) && _has_syntax_projection(format)

# The format that `parse_natural_text` reads for `name`, or `nothing`.
function _find_natural_format(name::Symbol)
    format = find_file_format(name)
    format !== nothing && _is_natural_format(format) ? format : nothing
end

# The types that have a method of `make_syntax_projection`, read from its method
# table, each before its supertypes. For a method of a set of types, `Type{<:T}`,
# the type is `T`.
function _collect_syntax_projection_types()
    types = Type[]
    for method in methods(make_syntax_projection)
        signature = Base.unwrap_unionall(method.sig)
        length(signature.parameters) == 2 || continue
        argument = Base.unwrap_unionall(signature.parameters[2])
        (argument isa DataType && argument.name === Type.body.name) || continue
        type = argument.parameters[1]
        type isa TypeVar && (type = type.ub)
        type isa Type && type !== Any && !(type in types) && push!(types, type)
    end
    sort!(types; by = type -> (-_count_supertypes(type), string(type)))
end

# How far `type` is below `Any`; a `Union` counts as `Any`.
function _count_supertypes(type::Type)
    count = 0
    while type isa DataType && type !== Any
        type = supertype(type)
        count += 1
    end
    count
end

"""
    get_natural_entries(; appearance) -> Vector{Pair{Type,Any}}

A row for each type that has a method of [`make_syntax_projection`](@ref), built
now with the `Appearance` of the editor, as the type-keyed pairs a dispatching
projection is spliced from. A type comes before each of its supertypes.
"""
get_natural_entries(; appearance::Appearance) =
    Pair{Type,Any}[type => Base.invokelatest(make_syntax_projection, type; appearance)
                   for type in _collect_syntax_projection_types()]

"""
    has_natural_parser(format::Symbol) -> Bool

Whether [`parse_natural_text`](@ref) reads `format`: a file format of the session
has the extension that `format` names without its dot, it parses a string, and
its documents have a syntax notation. `:yaml` and `:yml` name one format.
"""
has_natural_parser(format::Symbol) = _find_natural_format(format) !== nothing

# ── The three functions of the assistant ────────────────────────────────────

"""
    parse_natural_text(format::Symbol, text) -> Document

Read `text` of `format` into a document. The text can be a whole file or a part
of one: one JSON value, one Julia expression, one Markdown paragraph. Errors when
no domain claimed the format; ask [`has_natural_parser`](@ref) first when that is
a normal answer.

Use it to make a document of a domain from its text: a new value for
`replace_referenced_value!`, a new element for `insert_elements!`, or a whole
document for `open_pane!`. Write the text of the domain, which you know well,
rather than the constructors of its documents.

# Example

    price_1 = parse_natural_text(:json, "12")
    item_1 = parse_natural_text(:json, \"\"\"{"name": "lamp", "price": 25}\"\"\")
    note_1 = parse_natural_text(:md, "# Notes\\n\\nThe first line.")

See also `describe_natural_formats`, `print_natural_text`.

For the assistant.
"""
function parse_natural_text end

function parse_natural_text(format::Symbol, text::AbstractString)
    file_format = _find_natural_format(format)
    file_format === nothing &&
        error("parse_natural_text: no file format of the session reads $(repr(format)) as natural text")
    parse_document_string(file_format, text)
end

"""
    describe_natural_formats() -> String

The formats that [`parse_natural_text`](@ref) reads, one line each: the format,
the extension of its files, and the kind of document that it makes, such as
`:json   .json   JsonDocument`. Only the domains that this session loaded are in
the list.

Use it to find the format of a domain before you write its text, or to see which
documents can be written as text at all.

# Example

    println(describe_natural_formats())

See also `parse_natural_text`, `print_natural_text`.

For the assistant.
"""
function describe_natural_formats end

function describe_natural_formats()
    lines = String[]
    for format in collect_file_formats()
        extensions = get_file_format_extensions(format)
        (isempty(extensions) || isempty(first(extensions)) || !_is_natural_format(format)) && continue
        extension = first(extensions)
        name = Symbol(SubString(extension, 2))
        push!(lines, rpad(repr(name), 8) * rpad(extension, 10) *
                     String(nameof(get_file_format_domain(format))))
    end
    join(sort(lines), "\n")
end

"""
    make_prose_document(text) -> Document

The document of a run of prose, `text` in Markdown: the document that the
Markdown parser reads from it when a format of the session reads `:md`, and else,
or when the parse fails, a text block of `text` as it is written.
"""
function make_prose_document(text::AbstractString)
    has_natural_parser(:md) || return make_text_block(String(text))
    try
        parse_natural_text(:md, String(text))
    catch
        make_text_block(String(text))
    end
end

# ── The ladder ──────────────────────────────────────────────────────────────

# The fixed steps of the ladder from `rung` up to `target`: a syntax tree to text,
# then text to graphics or to a string. `nothing` when the ladder has no such path.
function _make_natural_steps(rung::Symbol, target::Symbol, measure, appearance::Appearance)
    rung === target && return Any[]
    steps = Any[]
    if rung === :syntax
        hasmethod(make_syntax_to_text_projection, Tuple{}) || return nothing
        push!(steps, make_syntax_to_text_projection(; appearance))
        target === :text && return steps
    elseif rung !== :text
        return nothing
    end
    target === :string && return push!(steps, TextToString())
    target === :graphics &&
        return push!(steps, TextToGraphics(; measure, theme = get_scaled_theme!(appearance, TextTheme)))
    nothing
end

# The chain from `stage`, which prints a document at `rung`, up to `target`, or
# `nothing` when the ladder has no such path. The first stage prints the
# document, so it puts what a person arranged at its places; the stages after it
# print what the first one made.
function _make_natural_chain(stage, rung::Symbol, target::Symbol, measure, appearance::Appearance)
    steps = _make_natural_steps(rung, target, measure, appearance)
    steps === nothing && return nothing
    ChainingProjection(RecursiveProjection(make_arranged_dispatch(stage)),
                       (RecursiveProjection(step) for step in steps)...)
end

"""
    make_natural_projection(document, target::Symbol; measure = nothing,
                            appearance = Appearance()) -> Projection | Nothing

The projection that takes `document` up to `target` — `:syntax`, `:text`,
`:graphics` or `:string` — or `nothing` when the ladder has no path.

A `TextDocument` starts at the text rung. Any other document starts at the
syntax rung, with the projection of its type
([`make_syntax_projection`](@ref)), and a type with none has no path. The fixed
steps above the rung follow it. A `:graphics` target needs `measure`. Each stage
takes its scaled theme from `appearance`; the default is a new `Appearance`,
which no tab edits.
"""
function make_natural_projection(document, target::Symbol; measure = nothing,
                                 appearance::Appearance = Appearance())
    document isa TextDocument &&
        return _make_natural_chain(IdentityProjection(), :text, target, measure, appearance)
    type = typeof(document)
    _has_syntax_projection(type) || return nothing
    _make_natural_chain(make_syntax_projection(type; appearance), :syntax, target, measure, appearance)
end

"""
    make_document_string(format::FileFormat, document) -> String

The string of `document` in a format whose string is the print of a syntax tree:
the document in the syntax notation of `format` ([`make_syntax_projection`](@ref)),
then as text, then as a string. A format whose string is something else declares
a method of its own.
"""
function make_document_string(format::FileFormat, document)
    _has_syntax_projection(format) ||
        error("make_document_string: the documents of $(nameof(typeof(format))) have no syntax notation")
    appearance = Appearance()
    chain = _make_natural_chain(make_syntax_projection(format; appearance), :syntax, :string,
                                nothing, appearance)
    chain === nothing && error("make_document_string: no step of the ladder prints a syntax tree as text")
    String(print_document(chain, document).output)
end

"""
    print_natural_text(document) -> String

`document` as its own text: the domain's notation, then the steps of the ladder
up to a string, run through `print_document` and flattened.

**A shorthand, not a seam.** It is `make_natural_projection(document, :string)`,
`print_document`, and a `String`. A caller that wants the io map, or a different
last rung, builds the projection itself and runs the engine.

Use it to read a document as text.

# Example

    people_1 = get_edited_document(find_pane("people.json"))
    people_text_1 = print_natural_text(people_1)

See also `parse_natural_text` and `write_document_file!`.

For the assistant.
"""
function print_natural_text end

function print_natural_text(document)
    projection = make_natural_projection(document, :string)
    if projection === nothing
        # A layer a person sees through, such as the scroll pane of a file tab,
        # prints as what it shows.
        field = get_edited_field(document)
        field === nothing || return print_natural_text(getproperty(document, field))
        error("print_natural_text: no natural text for $(typeof(document))")
    end
    String(print_document(projection, document).output)
end

print_natural_text(document::ReferencedDocument) = print_natural_text(get_document(document))
