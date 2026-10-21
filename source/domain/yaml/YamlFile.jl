# Fragment of `YamlModule` — `YamlFile`, the `.yaml` (and `.yml`) file on disk.
#
# A cross-file reference is written in YAML as a string scalar whose whole
# value is the marker, the same way JSON uses a string. The file writes one
# where the save cuts, and the load splices the node it names into its place;
# neither direction mutates the tree before it walks it. What this file
# contributes is the four lines every format owes: its domain, its parser, how
# it spells a reference leaf, and how it recognises one.
"""
    YamlFile(filename, content)

A file document whose `content` is a `YamlDocument`.
"""
@document struct YamlFile <: FileDocument
    filename::String
    content::Document = YamlNothing()
end

# What the file writes itself, and how it spells a reference to what it does
# not: a string whose whole value is the marker.
get_file_domain(::Type{<:YamlFile}) = YamlDocument
make_reference_leaf(::YamlFile, marker::AbstractString) = YamlString(make_marker_text(marker))
find_reference_marker(leaf::YamlString) = parse_marker_text(leaf.value)
parse_file_content(::Type{<:YamlFile}, text::AbstractString) = parse_yaml(text)

# Emit runs the `YamlToSyntax → SyntaxToText → TextToString` chain.
emit_text(f::YamlFile) = print_natural_text(get_file_content(f))

# The file says what the pointer is on, for a part that says nothing of its own:
# the path of the part from the root of the file, its type, and its length, its
# value or its count. With no pointer on the file, it says the selected part.
function _make_yaml_part_note(file::YamlFile)
    found = find_pointed_part(file)
    found === nothing && return nothing
    part = found.part
    part isa YamlDocument || return nothing
    facts = Pair{String,Any}["Path" => _format_yaml_path(found.documents), "Type" => _get_yaml_type_name(part)]
    _push_yaml_size_fact!(facts, part)
    TooltipNote(; title = basename(file.filename), facts)
end

# The path of the last of `documents` from the root of the file: the key of each
# entry after a dot, or in brackets when it is not a plain name, and the place of
# each element of a sequence from 1, as the editor counts.
function _format_yaml_path(documents)
    text = ""
    for index in 2:length(documents)
        document = documents[index]
        # The owner of a part is the nearest YamlDocument above it: the list of the
        # elements of an array is a document of its own between the two.
        owner = findlast(above -> above isa YamlDocument, documents[1:(index - 1)])
        parent = owner === nothing ? nothing : documents[owner]
        if document isa YamlMappingEntry
            key = document.key
            text = occursin(r"^[A-Za-z_][A-Za-z0-9_]*$", key) ? (isempty(text) ? key : string(text, ".", key)) :
                                                              string(text, "[", repr(key), "]")
        elseif parent isa YamlSequence
            place = findfirst(element -> element === document, collect(parent.elements))
            place === nothing || (text = string(text, "[", place, "]"))
        end
    end
    isempty(text) ? "the root" : text
end

_get_yaml_type_name(entry::YamlMappingEntry) = _get_yaml_type_name(entry.value)
_get_yaml_type_name(::YamlString) = "String"
_get_yaml_type_name(::YamlNumber) = "Number"
_get_yaml_type_name(::YamlBool) = "Boolean"
_get_yaml_type_name(::YamlNull) = "Null"
_get_yaml_type_name(::YamlMapping) = "Mapping"
_get_yaml_type_name(::YamlSequence) = "Sequence"
_get_yaml_type_name(document) = string(nameof(typeof(document)))

# The fact of the size or the value of a part: the length of a string, the value
# of a number, the entries of a mapping, the elements of a sequence.
_push_yaml_size_fact!(facts, entry::YamlMappingEntry) = _push_yaml_size_fact!(facts, entry.value)
_push_yaml_size_fact!(facts, text::YamlString) = push!(facts, "Length" => string(length(text.value)))
_push_yaml_size_fact!(facts, number::YamlNumber) =
    number.value === nothing ? facts : push!(facts, "Value" => repr(number.value))
_push_yaml_size_fact!(facts, mapping::YamlMapping) = push!(facts, "Entries" => string(length(mapping.entries)))
_push_yaml_size_fact!(facts, sequence::YamlSequence) = push!(facts, "Elements" => string(length(sequence.elements)))
_push_yaml_size_fact!(facts, document) = facts

# The table of the file: a dwell answers the note of the part under the pointer.
const _YAML_FILE_BINDINGS = GestureBinding[
    make_tooltip_binding(_make_yaml_part_note; description = "Show the path of the part")]

@gestures YamlFile begin
    splice(_YAML_FILE_BINDINGS)
end
