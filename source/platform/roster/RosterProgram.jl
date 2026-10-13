# Fragment of `RosterModule` — a roster as code and a language model use it: the
# verb that shows one, the words that say how its rows show and what a roster can
# show, and the edit of every item that a roster shows.

"""
    show_roster!(source; title = "Roster", columns = String[], filter = [], sort = [], group = [],
                 aggregates = [:count], first = nothing, editor = get_evaluation_editor())
        -> ReferencedDocument

Show a roster of the items of `source` in a tab of the window of `editor`, with
the columns `columns`, and answer the roster in its window, which the verbs of
the arrangement and `edit_shown_items!` take for its rows. The keywords `filter`, `sort`, `group` with `aggregates`, and `first` take
what `filter_collection!`, `sort_collection!`, `group_collection!` and
`limit_collection!` take, and make the entry that those verbs make: a person sees
the chips in the bar and changes them. A `Roster` in place of a source is shown
with its own columns and title.

The answer prints the title, how the rows show of all, the columns, and the first
20 rows that show ([`describe_roster`](@ref)), so a model can check the roster in
the round that made it.

Use it to show the members of one kind from anywhere in the window or the
session: the files with edits, the documents of each type, the errors of the log.

# Example

    show_roster!(TabDocuments(FileDocument); title = "Files with edits",
                 columns = ["name", "folder", "has_edits"], filter = ["has_edits" => ==(true)])
    show_roster!(StoreRecords(:log); title = "Errors", columns = ["level", "message"],
                 filter = ["level" => ==("Error")], first = 100)

See also `describe_roster_sources` and `describe_item_facets`, which say what a
roster can show, and `edit_shown_items!`.
"""
function show_roster!(source; title::AbstractString = "Roster", columns = String[], filter = Any[],
                      sort = Any[], group = Any[], aggregates = Any[:count], first = nothing,
                      editor = get_evaluation_editor())
    roster = source isa Roster ? source : Roster(source; columns, title)
    link_roster!(roster, editor.document)
    entry = make_arrangement_entry(extend_reference(EmptyReference(), FieldReferenceStep("rows"));
                                   filter, sort, group, aggregates, first)
    shown = entry === nothing ? roster : ArrangementDocument(roster, ArrangementEntry[entry])
    show_document!(shown; title = roster.title, editor)
    found = search_references(editor.document, node -> node === roster; maxdepth = 24)
    isempty(found) && throw(ArgumentError(string("The window shows no roster \"", roster.title, "\" after the show.")))
    ReferencedDocument(roster, strip_reference_types(found[1]))
end

# A verb of the arrangement that is given a roster arranges its rows.
get_arranged_collection_steps(::Roster) = (FieldReferenceStep("rows"),)

"""
    describe_roster(roster) -> Text

How a roster shows, as text for a person or a model: its title, how many rows show
of all and the parts of their arrangement, the columns, and a line for each of the
first 20 rows that show. `roster` is what [`show_roster!`](@ref) answers: the
roster with its path in its window. The link of the roster is the document of the
window, which holds the arrangement of its rows; a roster with no link shows every
row.
"""
function describe_roster(handle::ReferencedDocument)
    roster = get_document(handle)
    roster isa Roster || throw(ArgumentError("describe_roster takes what show_roster! answers."))
    items = roster.rows
    link = roster.link
    found = link === nothing ? nothing :
        find_arranged_collection(link, extend_reference(get_reference(handle), FieldReferenceStep("rows")))
    entry = found === nothing ? nothing : found.entry
    shown = collect_shown_items(entry, items)
    lines = String[string(roster.title, ": ", describe_arranged_collection(entry, items))]
    isempty(shown) && return Text(lines[1])
    push!(lines, join(shown[1].columns, " | "))
    for row in shown[1:min(length(shown), 20)]
        push!(lines, join((format_roster_value(_get_shown_value(value)) for value in row.values), " | "))
    end
    length(shown) > 20 && push!(lines, string("(the first 20 of ", length(shown), " rows)"))
    Text(join(lines, "\n"))
end

# The roster that `show_roster!` answers prints how it shows, so a model reads it.
Base.show(io::IO, roster::ReferencedDocument{<:Roster}) = print(io, describe_roster(roster))
Base.show(io::IO, ::MIME"text/plain", roster::ReferencedDocument{<:Roster}) = show(io, roster)

"""
    describe_roster_sources() -> Text

The kinds of sources of a roster that the loaded slices give, each with the call
that makes one and what its items are, and the names of the stores that
`StoreRecords` reads, each with what its records are.

Use it to find the source of a roster before `show_roster!`.
"""
function describe_roster_sources()
    lines = String["The kinds of sources of a roster:"]
    for type in _collect_source_types()
        push!(lines, "- " * _describe_source_type(type))
    end
    push!(lines, "The stores that StoreRecords(name) reads:")
    for name in get_roster_source_names()
        push!(lines, string("- :", name, ": ", _ROSTER_SOURCES[name].description))
    end
    Text(join(lines, "\n"))
end

# The public types of the sources that a loaded slice gives, in the order of their
# names: each type with a method of `collect_roster_parts`.
function _collect_source_types()
    types = Type[]
    for method in methods(collect_roster_parts)
        type = Base.unwrap_unionall(method.sig).parameters[2]
        (type isa DataType && !startswith(String(nameof(type)), "_")) || continue
        type in types || push!(types, type)
    end
    sort!(types; by = type -> String(nameof(type)))
end

# The call that makes a source of `type`, and the first sentence that its
# docstring says of it.
function _describe_source_type(type::Type)
    paragraphs = split(strip(string(Base.Docs.doc(type))), r"\n\s*\n")
    call = strip(paragraphs[1])
    length(paragraphs) > 1 || return call
    words = replace(strip(paragraphs[2]), r"\s+" => " ")
    sentence = String(split(words, ". ")[1])
    string(call, ": ", sentence, endswith(sentence, ".") ? "" : ".")
end

"""
    describe_item_facets(type) -> Text
    describe_item_facets(source) -> Text

The keys of a roster of the items of `type`, or of the items of `source`: each
facet with what it says ([`collect_item_facets`](@ref)), and the fields of the
type, which a path names. A source gives the type of its items
([`get_roster_item_type`](@ref)).

Use it to choose the columns, the conditions and the keys of a roster.
"""
function describe_item_facets(type::Type)
    lines = String[string("The keys of a roster of ", nameof(type), ":")]
    for (name, words) in collect_item_facets(type)
        push!(lines, string("- ", name, ": ", words))
    end
    fields = String[String(name) for name in _get_own_field_names(type) if !is_view_state_field(name)]
    push!(lines, isempty(fields) ? "and the path of each field of an item, with dots between its names." :
                 string("and the path of each field of an item: ", join(fields, ", "), "."))
    Text(join(lines, "\n"))
end

describe_item_facets(source) = describe_item_facets(get_roster_item_type(source))

"""
    edit_shown_items!(collection, change::Pair; editor = get_evaluation_editor()) -> Text

Give the value of `change` to the key of `change` in the item of each row that
the roster at `collection` shows, as one edit, which one undo takes back, and
answer what it changed. A key is a path of fields of the item, such as
`"capacity"` or `"limits.queue"`, or a facet whose slice gives its edit
(`make_item_facet_operation`). `collection` is what `show_roster!` answers, or a
`Reference` to the rows of a roster. A roster that shows groups shows no one item
in a row, and the call is an `ArgumentError`.

Use it to change one value in every item that a roster shows, such as the same
parameter in all the modules that a filter keeps.

# Example

    rows = show_roster!(CollectionItems(runs); columns = ["id", "status"], filter = ["status" => ==("done")])
    edit_shown_items!(rows, "status" => "checked")
"""
function edit_shown_items!(collection, change::Pair; editor = get_evaluation_editor())
    reference = collection isa ReferencedDocument ?
        extend_reference(get_reference(collection), get_arranged_collection_steps(get_document(collection))...) :
        collection
    found = find_arranged_collection(editor.document, reference)
    found === nothing && throw(ArgumentError(string("No roster is at ", reference, ".")))
    shown = collect_shown_items(found.entry, found.items)
    all(row -> row isa RosterRow, shown) ||
        throw(ArgumentError("The roster shows groups, and a group holds no one item to edit."))
    key = String(first(change))
    value = last(change)
    operations = Any[_make_item_edit(row, key, value) for row in shown]
    isempty(operations) && return Text("The roster shows no row, so nothing changed.")
    words = string("Set ", key, " in ", length(operations), length(operations) == 1 ? " item" : " items")
    operation = find_rooted_operation(editor, found.path, relative -> CompoundOperation(operations);
                                      description = words)
    operation === nothing && throw(ArgumentError("No reader of the window carries an edit of the roster."))
    evaluate_operation(editor, operation)
    Text(string(words, " to ", repr(value), "."))
end

# The edit that gives `value` to the key `key` of the item of `row`: the edit that
# the slice of a facet gives, or the write of the last field of a path.
function _make_item_edit(row::RosterRow, key::String, value)
    names = String.(split(key, '.'))
    head = names[1]
    (target, path) = head == "within" ? (row.within, names[2:end]) : (row.item, names)
    isempty(path) && throw(ArgumentError(string("The key \"", key, "\" names an item, not a field of it.")))
    if _has_item_facet(typeof(target), path[1])
        length(path) == 1 || throw(ArgumentError(string("The key \"", key, "\" goes inside a facet, which takes no edit.")))
        operation = make_item_facet_operation(target, Val(Symbol(path[1])), value)
        operation === nothing && throw(ArgumentError(string("The facet \"", path[1], "\" takes no edit.")))
        return operation
    end
    holder = _follow_names(target, path[1:(end - 1)], 1)
    holder isa Document || throw(ArgumentError(string("The key \"", key, "\" reaches no field of a document.")))
    ReplaceReferencedValueOperation(holder, path[end], value)
end
