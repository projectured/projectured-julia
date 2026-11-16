# Fragment of `JsonModule` — `JsonFile`, the `.json` file on disk, and
# `JsonFileFormat`, its format.
#
# A cross-file reference is written in JSON as a string whose whole value is a
# marker. The file writes one where the save cuts, and the load splices the node
# it names into its place; neither direction mutates the tree before it walks
# it. What this file contributes is the lines every format owes: its extension,
# its domain, its parser, how it spells a reference leaf, and how it recognises
# one; and the empty document of a new file of the domain.

"""
    JsonFileFormat()

The format of a `.json` file: its string is the JSON text of one
`JsonDocument`, and its file is a `JsonFile`. A reference to another file is a
JSON string whose whole value is the marker.
"""
struct JsonFileFormat <: FileFormat end

get_file_format_extensions(::JsonFileFormat) = (".json",)
get_file_format_domain(::JsonFileFormat) = JsonDocument
parse_document_string(::JsonFileFormat, string::AbstractString) = parse_json(string)
make_reference_leaf(::JsonFileFormat, marker::AbstractString) =
    JsonString(make_marker_text(marker))
find_reference_marker(leaf::JsonString) = parse_marker_text(leaf.value)
find_natural_file_format(::JsonDocument) = JsonFileFormat()
# A new file starts as the insertion of a first value.
make_document_seed(::Type{JsonDocument}) = JsonInsertion()

"""
    JsonFile(filename, content)

A file of [`JsonFileFormat`](@ref), whose `content` is a `JsonDocument`.
"""
const JsonFile = File{JsonFileFormat}

# The file says what the pointer is on, for a part that says nothing of its own:
# the path of the part from the root of the file, its type, and its length, its
# value or its count. With no pointer on the file, it says the selected part.
function _make_json_part_note(file::JsonFile)
    found = find_pointed_part(file)
    found === nothing && return nothing
    part = found.part
    part isa JsonDocument || return nothing
    facts = Pair{String,Any}["Path" => _format_json_path(found.documents), "Type" => _get_json_type_name(part)]
    _push_json_size_fact!(facts, part)
    TooltipNote(; title = basename(file.filename), facts)
end

# The path of the last of `documents` from the root of the file: the key of each
# entry after a dot, or in brackets when it is not a plain name, and the place of
# each element of an array from 1, as the editor counts.
function _format_json_path(documents)
    text = ""
    for index in 2:length(documents)
        document = documents[index]
        # The owner of a part is the nearest JsonDocument above it: the list of the
        # elements of an array is a document of its own between the two.
        owner = findlast(above -> above isa JsonDocument, documents[1:(index - 1)])
        parent = owner === nothing ? nothing : documents[owner]
        if document isa JsonObjectEntry
            key = document.key
            text = occursin(r"^[A-Za-z_][A-Za-z0-9_]*$", key) ? (isempty(text) ? key : string(text, ".", key)) :
                                                              string(text, "[", repr(key), "]")
        elseif parent isa JsonArray
            place = findfirst(element -> element === document, collect(parent.elements))
            place === nothing || (text = string(text, "[", place, "]"))
        end
    end
    isempty(text) ? "the root" : text
end

_get_json_type_name(entry::JsonObjectEntry) = _get_json_type_name(entry.value)
_get_json_type_name(::JsonString) = "String"
_get_json_type_name(::JsonNumber) = "Number"
_get_json_type_name(::JsonBool) = "Boolean"
_get_json_type_name(::JsonNull) = "Null"
_get_json_type_name(::JsonObject) = "Object"
_get_json_type_name(::JsonArray) = "Array"
_get_json_type_name(document) = string(nameof(typeof(document)))

# The fact of the size or the value of a part: the length of a string, the value
# of a number, the entries of an object, the elements of an array.
_push_json_size_fact!(facts, entry::JsonObjectEntry) = _push_json_size_fact!(facts, entry.value)
_push_json_size_fact!(facts, text::JsonString) = push!(facts, "Length" => string(length(text.value)))
_push_json_size_fact!(facts, number::JsonNumber) =
    number.value === nothing ? facts : push!(facts, "Value" => repr(number.value))
_push_json_size_fact!(facts, object::JsonObject) = push!(facts, "Entries" => string(length(object.entries)))
_push_json_size_fact!(facts, array::JsonArray) = push!(facts, "Elements" => string(length(array.elements)))
_push_json_size_fact!(facts, document) = facts

# The table of the file: a dwell answers the note of the part under the pointer.
const _JSON_FILE_BINDINGS = GestureBinding[
    make_tooltip_binding(_make_json_part_note; description = "Show the path of the part")]

get_document_gesture_bindings_own(::Type{<:JsonFile}) = _JSON_FILE_BINDINGS
