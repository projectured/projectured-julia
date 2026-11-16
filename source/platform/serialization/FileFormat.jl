# Fragment of `SerializationModule` — a file format, the seams that a format
# declares, and the searches over the formats of a session.
#
# A format is a type with no field, a subtype of `FileFormat`, that the package of
# the format declares. The package then adds a method of each seam for it: the
# extensions, the parser, the conversion of a document to a string, the domain.
# No registry holds a format and no `__init__` registers one. A search reads the
# formats from the method table of `get_file_format_extensions`, so a format is
# known as soon as its package is loaded.

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
[`is_file_domain_node`](@ref) and [`make_file`](@ref). A format that has a file
type declares [`get_file_type`](@ref).

[`find_file_format`](@ref) finds a format by an extension, a path or a short
name, and [`collect_file_formats`](@ref) gives each format of the session.
"""
abstract type FileFormat end

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
    read_file_content(format::FileFormat, path::AbstractString) -> content

The content of the file at `path`, as a file of `format` holds it. The default
reads the string of the file and parses it with
[`parse_document_string`](@ref). A format whose file is too large to read whole,
such as the vector file of a simulation, reads only what it needs in a method of
its own.
"""
read_file_content(format::FileFormat, path::AbstractString) =
    parse_document_string(format, read(path, String))

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
make_reference_leaf(format::FileFormat, marker::AbstractString)

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
the file, its content and its state on disk. A format that has a file type
declares a method. `get_file_type(get_file_format(file))(filename, content)` makes
a file of the same format with another content.
"""
function get_file_type end

"""
    make_file(format::FileFormat, filename::AbstractString, string::AbstractString) -> file document

The file named `filename` whose string is `string`, in `format`. The default makes
a file of [`get_file_type`](@ref) with the content that
[`parse_document_string`](@ref) reads. A format whose file is its own content
declares a method that builds the file.
"""
make_file(format::FileFormat, filename::AbstractString, string::AbstractString) =
    get_file_type(format)(String(filename), parse_document_string(format, string))

"""
    get_file_format(file) -> FileFormat

The format of `file`, a file document, read from its type and not from the
extension of its name. A file type declares a method.
"""
function get_file_format end

"""
    collect_file_formats() -> Vector{FileFormat}

Each format of the session: the value of each concrete type with no field that
has a method of [`get_file_format_extensions`](@ref), in the order of the names
of the types. A format is in the list when its package is loaded, with no
registration.
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

# The one format of the session that declares `extension`, or `nothing`.
function _find_extension_format(extension::AbstractString)
    found = filter(format -> any(e -> lowercase(e) == extension, get_file_format_extensions(format)),
                   collect_file_formats())
    length(found) <= 1 && return isempty(found) ? nothing : only(found)
    error("the extension ", repr(extension), " is declared by more than one file format: ",
          join((string(parentmodule(typeof(f)), ".", nameof(typeof(f))) for f in found), " and "),
          ", so a file can not say which one it means")
end
