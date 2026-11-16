# Fragment of `SerializationModule` — a file format, the file of a format, the seams
# that a format declares, and the searches over the formats of a session.
#
# A format is a type with no field, a subtype of `FileFormat`, that the package of
# the format declares. The package then adds a method of each seam for it: the
# extensions, the parser, the conversion of a document to a string, the domain.
# No registry holds a format and no `__init__` registers one. A search reads the
# formats from the method table of `get_file_format_extensions`, so a format is
# known as soon as its package is loaded.
#
# A file of a format is a `File{F}`: its name, its content and its state on disk.
# The text of a file is the string of its content and one line break: the read
# removes one line break at the end of the text before the parse, and the write of
# a file adds one after the string.

"""
    FileFormat

The format of a file: how a string of a file becomes a document, and a document
becomes the string again. A format is a concrete subtype with no field, and the
functions of the format take its one value as their first argument:

    struct YamlFileFormat <: FileFormat end

    get_file_format_extensions(::YamlFileFormat) = (".yaml", ".yml")
    get_file_format_domain(::YamlFileFormat) = YamlDocument
    parse_document_string(::YamlFileFormat, string::AbstractString) = parse_yaml(string)

A format declares [`get_file_format_extensions`](@ref),
[`get_file_format_domain`](@ref), [`parse_document_string`](@ref) and, when a
file of the format can refer to another file, [`make_reference_leaf`](@ref). A
format whose string is not the print of a syntax tree declares
[`make_document_string`](@ref). The other seams have a default:
[`is_editable_file_format`](@ref), [`read_file_content`](@ref),
[`is_written_in_file`](@ref), [`is_written_inline`](@ref),
[`is_file_domain_node`](@ref), [`get_file_type`](@ref) and [`make_file`](@ref).
The domain of the format declares the empty document of a new file,
[`make_document_seed`](@ref).

[`find_file_format`](@ref) finds a format by an extension, a path or a short
name, and [`collect_file_formats`](@ref) gives each format of the session.
"""
abstract type FileFormat end

"""
    make_document_seed(domain::Type) -> document

The empty document of a new file whose format has the domain `domain`, such as
`JsonInsertion()` for `JsonDocument`: the insertion of the domain where a person
types a first element, or the empty root where the root takes edits, as an empty
Markdown page. It is also the content of a [`File`](@ref) that is made with no
content. A domain declares a method for its type; a domain with none gives an
empty document. The domain `Union{}`, of a file that holds no document, gives the
empty string.

# Example

    make_document_seed(get_file_format_domain(find_file_format(".json")))   # JsonInsertion()
"""
function make_document_seed end

make_document_seed(::Type{Union{}}) = ""

"""
    File{F<:FileFormat}(filename, content = make_document_seed(get_file_format_domain(F())))

The document of a file of the format `F`: `filename`, the name of the file;
`content`, what the file holds, as the format reads it; and `disk`, its state
against the file on disk ([`FileDiskState`](@ref)). A file that is made with no
content holds the empty document of the domain of its format
([`make_document_seed`](@ref)). Its format is its type parameter:
[`get_file_format`](@ref) answers `F()`, and [`get_file_type`](@ref) of a format
answers `File{F}`, the file of each format that has no file type of its own.

A package gives the file of its format a short name, as `const JsonFile =
File{JsonFileFormat}`. The short name constructs a file, takes a method and
answers an `isa` test for each cell layout of the file.

# Example

    file = File{JsonFileFormat}("people.json", parse_json("[]"))
    file isa JsonFile                    # true
    get_file_format(file)                # JsonFileFormat()
"""
@document struct File{F<:FileFormat} <: FileDocument
    filename::String
    content::Any = make_document_seed(get_file_format_domain(F()))
    disk::FileDiskState = FileDiskState()
end

# A reader names the file of a format by the name of the format without `Format`,
# `JsonFile` for `File{JsonFileFormat}`, which is also the short name that the
# package of the format gives it. So a roster, an inspector and the error of a save
# tell a file of one format from a file of another, and a `.pred` file names the
# file of a format by that name.
get_document_schema_name(::Type{<:File{F}}) where {F<:FileFormat} =
    Symbol(chopsuffix(String(nameof(F)), "Format"))

"""
    get_file_format_extensions(format::FileFormat) -> Tuple of String

The extensions of the files of `format`, each with its dot and in lower case,
such as `(".yaml", ".yml")`. A new file of the format takes the first one. `""`
stands for a file name with no extension. A format whose files are chosen by
their opener and not by their name answers `()`.

Each format declares a method, also a format with no extension, because
[`collect_file_formats`](@ref) reads the formats from the methods of this
function.

# Example

    get_file_format_extensions(find_file_format(".yml"))   # (".yaml", ".yml")
"""
function get_file_format_extensions end

"""
    parse_document_string(format::FileFormat, string::AbstractString) -> document

The document that `string` holds in `format`. A reference to another file stays
the leaf that the format writes for it ([`make_reference_leaf`](@ref)). It is the
inverse of [`make_document_string`](@ref): the
string of the document parses to an equal document.

Each format that a person edits from its string declares a method.

# Example

    document = parse_document_string(find_file_format(:yaml), "a: 1")
"""
function parse_document_string end

"""
    make_document_string(format::FileFormat, document) -> String

The string that a file of `format` holds for `document`, a document of the domain
of the format. [`parse_document_string`](@ref) reads it back to an equal
document. A format whose string is the print of a syntax tree needs no method of
its own: the general method prints the document in the syntax notation of the
format. Any other format declares a method for the documents that it writes.

# Example

    format = find_file_format(:yaml)
    make_document_string(format, parse_document_string(format, "a: 1"))
"""
function make_document_string end

"""
    get_file_format_domain(format::FileFormat) -> Type

The type of the documents that a file of `format` holds, such as `YamlDocument`.
[`is_file_domain_node`](@ref) answers by it. Each format declares a method.
"""
function get_file_format_domain end

"""
    is_editable_file_format(format::FileFormat) -> Bool

Whether a person edits a file of `format`. `false` for a file that a program
writes and a person only reads, such as a result file of a simulation. `true` by
default.
"""
is_editable_file_format(::FileFormat) = true

"""
    read_file_content(format, path) -> content

The content of the file at `path`, as a file of `format` holds it: the parsed
tree of a JSON file, a `String` for a text file. The default reads the text of the
file, removes one line break at its end, and parses the string with
[`parse_document_string`](@ref). A format whose file is too large to read whole,
such as the vector file of a simulation, reads only what it needs in a method of
its own, as a picture reads nothing.

Use it to read the content of a file in a given format without opening a window on it.

# Example

    content_1 = read_file_content(find_file_format("data.json"), "data.json")

See also `get_file_content` and `read_document_file`.

For the assistant.
"""
function read_file_content end

read_file_content(format::FileFormat, path::AbstractString) =
    parse_document_string(format, _remove_final_line_break(read(path, String)))

# The string of the text of a file: the text without its one line break at the end.
_remove_final_line_break(text::AbstractString) =
    endswith(text, '\n') ? String(chop(text)) : String(text)

"""
    is_written_in_file(format::FileFormat, node, name::Symbol) -> Bool

Whether the string of a file of `format` holds the field `name` of `node`.
`true` by default: a file writes the document that it holds, whole. A format whose
string writes a reduced form of a node answers `false` for the other fields.
"""
is_written_in_file(::FileFormat, node, name::Symbol) = true

"""
    is_written_inline(format::FileFormat, node) -> Bool

Whether a file of `format` writes `node`, a document of another domain that no
file of the set writes, in its own string, as a `.pred` file writes a JSON value.
`false` by default.
"""
is_written_inline(::FileFormat, node) = false

"""
    make_reference_leaf(format::FileFormat, marker::AbstractString) -> Document

The node that a file of `format` writes where it refers to another file: a leaf of
the domain of the format that holds the marker `<<marker>>`, such as a JSON string.
`marker` is the body of the marker, without `<<` and `>>`.
[`find_reference_marker`](@ref) of the leaf answers `marker` again. A format whose
files can refer to other files declares a method.
"""
function make_reference_leaf end

"""
    is_file_domain_node(format::FileFormat, node) -> Bool

Whether a file of `format` writes `node` itself, and not as a reference to another
file. The default answers whether `node` is a document of the domain of the format
([`get_file_format_domain`](@ref)). A format that writes nodes of more than one
type answers for them in a method of its own, as the math format does for a plain
number.
"""
is_file_domain_node(format::FileFormat, node) = node isa get_file_format_domain(format)

"""
    get_file_type(format::FileFormat) -> Type

The type of the document of a file of `format`: the type that holds the name of
the file, its content and its state on disk. The default is
[`File{F}`](@ref File) for the format `F`. A format whose file holds more, such as
the source file of a language server, declares a method for its own type.
`get_file_type(get_file_format(file))(filename, content)` makes a file of the
same format with another content.
"""
function get_file_type end

get_file_type(format::FileFormat) = File{typeof(format)}

"""
    make_file(format::FileFormat, filename::AbstractString, text::AbstractString) -> file document

The file named `filename` whose text is `text`, in `format`. The default removes
one line break at the end of `text`, and makes a file of [`get_file_type`](@ref)
with the content that [`parse_document_string`](@ref) reads from the string. A
format whose file is its own content declares a method that builds the file.
"""
make_file(format::FileFormat, filename::AbstractString, text::AbstractString) =
    get_file_type(format)(String(filename), parse_document_string(format, _remove_final_line_break(text)))

"""
    get_file_format(file) -> FileFormat

The format of `file`, a file document, read from its type and not from the
extension of its name: `F()` for a [`File{F}`](@ref File). A file type of its own
declares a method.
"""
function get_file_format end

get_file_format(::File{F}) where {F} = F()

"""
    collect_file_formats() -> Vector{FileFormat}

Each format of the session: the value of each concrete type with no field that
has a method of [`get_file_format_extensions`](@ref), in the order of the names
of the types. A format is in the list when its package is loaded, with no
registration.

The list is the one of the newest world, so it can hold a format that a package
loaded after the caller started. A caller that keeps an older world, such as the
loop of a window, calls a method of each format of the list through
`Base.invokelatest`.
"""
function collect_file_formats()
    types = DataType[]
    for method in methods(get_file_format_extensions)
        signature = Base.unwrap_unionall(method.sig)
        length(signature.parameters) == 2 || continue
        type = signature.parameters[2]
        (type isa DataType && type <: FileFormat && Base.issingletontype(type)) || continue
        type in types || push!(types, type)
    end
    sort!(types; by = type -> (String(nameof(type)), string(fullname(parentmodule(type)))))
    FileFormat[type.instance for type in types]
end

"""
    find_file_format(name::AbstractString) -> FileFormat or nothing
    find_file_format(name::Symbol) -> FileFormat or nothing

The format that `name` names, or `nothing` when no format of the session has it.
A string is an extension, such as `".yml"`, when a format declares it as it is;
any other string is a path, and its extension names the format, so a path with no
extension names the format of `""`. A symbol is a short name, the extension
without its dot, such as `:yml`. Case does not count.

An extension that two formats of the session declare is an error that names both,
because a file can not say which one it means.

# Example

    find_file_format("notes/a.yml") === find_file_format(:yaml)   # true
"""
function find_file_format end

function find_file_format(name::AbstractString)
    lowered = lowercase(name)
    found = _find_extension_format(lowered)
    found === nothing ? _find_extension_format(lowercase(splitext(name)[2])) : found
end

find_file_format(name::Symbol) =
    (short = lowercase(String(name)); _find_extension_format(isempty(short) ? "" : "." * short))

# The one format of the session that declares `extension`, or `nothing`. The
# extensions of each format come through `invokelatest`, so a format of a package
# loaded after a window opened stops no lookup of the window.
function _find_extension_format(extension::AbstractString)
    found = filter(format -> any(e -> lowercase(e) == extension,
                                 Base.invokelatest(get_file_format_extensions, format)),
                   collect_file_formats())
    length(found) <= 1 && return isempty(found) ? nothing : only(found)
    error("the extension ", repr(extension), " is declared by more than one file format: ",
          join((string(parentmodule(typeof(f)), ".", nameof(typeof(f))) for f in found), " and "),
          ", so a file can not say which one it means")
end
