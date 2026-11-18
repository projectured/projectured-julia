# Fragment of `JsonModule`.
#
# The views of JSON. A view keeps the state of one view of a JSON document: the
# caret, and the fold of an array or of an object. A view of a leaf holds its
# content; its caret is a path into the leaf, such as `.value{3}`, which the view
# reads through its content. A view of an array also holds the views of its
# elements, at `elements`, as the array holds its elements, so a path such as
# `.elements[2].value{3}` is a path of the view and of its array. A view of an
# object holds the views of its entries, at `entries`, and the view of an entry
# holds the view of its value, at `value`, so `.entries[1].value.value{3}` is a
# path of the view and of its object.
#
# A key that acts at the caret is a row of the key table of a view. The view at
# the end of the caret reads a key first, and its row answers for the node of that
# view, with a path from the view. The step of a view makes the write of it in the
# content (`make_content_edit`).

"""
    JsonView

The supertype of the views of the JSON documents. Its key table replaces a node
that the caret names with a node of another kind, as the table of `JsonDocument`
does for a document.
"""
abstract type JsonView <: ContentView end

"""
    JsonNullView(viewed::JsonNull)

A view of a JSON null. Its caret is the whole null or a place in its text.
"""
@content_view JsonNull struct JsonNullView <: JsonView end

"""
    JsonBoolView(viewed::JsonBool)

A view of a JSON boolean. Its caret is the whole boolean or a place in its text.
"""
@content_view JsonBool struct JsonBoolView <: JsonView end

"""
    JsonNumberView(viewed::JsonNumber)

A view of a JSON number. Its caret is a path of the number, such as `.value{1}`.
"""
@content_view JsonNumber struct JsonNumberView <: JsonView end

"""
    JsonStringView(viewed::JsonString)

A view of the JSON string `viewed`. Its caret is a path of the string, such as
`.value{3}`, or a place on a quote, which has no place in the string; it ends at
the view, so another view of the same string keeps a caret of its own. A viewing
step of `JsonToSyntax` prints it as the `SyntaxLeafView` of the leaf of the string.
"""
@content_view JsonString struct JsonStringView <: JsonView end

"""
    JsonArrayView(viewed::JsonArray)

A view of the JSON array `viewed`. `elements` holds the view of the list of the
elements (`CellVectorView`), which gives the view of each element at the index of
the element.
`collapsed` is the fold of this view, which another view of the array does not
share. A viewing step of `JsonToSyntax` prints it as the `SyntaxNodeView` of the
node of the array, whose children are the views of the nodes of the elements and
whose fold is the fold of this view.
"""
@content_view JsonArray struct JsonArrayView <: JsonView
    collapsed::Bool = false
end

"""
    JsonObjectEntryView(viewed::JsonObjectEntry)

A view of the entry `viewed` of a JSON object. `value` holds the view of the value
of the entry: the view of the document that the entry holds now. The key is a text
of the entry, so a caret in the key is a path of the entry, such as `.key{2}`, and
it ends at this view. A viewing step of `JsonToSyntax` prints it as the
`SyntaxNodeView` of the node of the entry, whose second child is the view of the
node of the value.
"""
@content_view JsonObjectEntry struct JsonObjectEntryView <: JsonView end

"""
    JsonObjectView(viewed::JsonObject)

A view of the JSON object `viewed`. `entries` holds the view of the list of the
entries (`CellVectorView`), which gives the view of each entry at the index of
the entry. `collapsed` is the fold of this view, which another view of the object
does not share. A viewing step of `JsonToSyntax` prints it as the `SyntaxNodeView`
of the node of the object, whose children are the views of the nodes of the
entries and whose fold is the fold of this view.
"""
@content_view JsonObject struct JsonObjectView <: JsonView
    collapsed::Bool = false
end

"""
    JsonInsertionView(viewed::JsonInsertion)

A view of the place where a person types a new JSON value. Its caret is a place in
the typed text, such as `.value{2}`, or the whole place. Return makes the document
that the typed text names, Escape puts the empty place back, and Tab takes the
completion of the typed text, and Insert makes it the place of every domain, with the same text.
A viewing step of `JsonToSyntax` prints it as the `SyntaxDelimitationView` of the
wrapper of the place.
"""
@content_view JsonInsertion struct JsonInsertionView <: JsonView end

"""
    JsonNothingView(viewed::JsonNothing)

A view of the empty place of JSON, which holds no value. Its caret is the whole
place or a place on its label. Insert makes the place for a new value of it, and a
key of a kind of value makes that value. A viewing step of `JsonToSyntax` prints
it as the `SyntaxLeafView` of the leaf of the label.
"""
@content_view JsonNothing struct JsonNothingView <: JsonView end

# Whether the caret of `view` names the node of `view`, and goes into no view of a
# child: the caret is on the whole node, on a text that the print made for the node,
# such as a bracket, or in a text of the node, such as the digits of a number.
function _names_own_node(view::JsonView)
    caret = get_selection(view)
    caret isa Reference || return false
    path = normalize_named_node_reference(caret)
    path isa ConcreteReference || return true
    !(try_evaluate_reference(view, Reference(path.head), nothing) isa ContentView)
end

# A node that a replace may retype: the node that the caret of its view names. An
# entry of an object stays a key and a value.
_is_replaceable_node(view::JsonView) = !(view.viewed isa JsonObjectEntry) && _names_own_node(view)

# A replace of the node of a view with `replacement`. The path is the empty path,
# the path of the view of the row, and the caret that `replacement` brings goes to
# the view of the new node.
_replace_node(replacement) = make_replace_document_operation(EmptyReference(), replacement)

@gestures JsonView begin
    when(_is_replaceable_node(doc))
    KeyPress('n') => "Replace with null"   => _replace_node(@selected JsonNull())
    KeyPress('f') => "Replace with false"  => _replace_node(make_insertion_document(JsonBool))
    KeyPress('t') => "Replace with true"   => _replace_node(@selected JsonBool(true))
    KeyPress('"') => "Replace with a string" => _replace_node(make_insertion_document(JsonString))
    KeyPress('[') => "Replace with an array" => _replace_node(make_insertion_document(JsonArray))
    KeyPress(':') => "Replace with an object entry" => _replace_node(make_insertion_document(JsonObjectEntry))
    KeyPress('{') => "Replace with an object" => _replace_node(make_insertion_document(JsonObject))
    when(KeyPress(c), isdigit(c)) => "Replace with a number" =>
        _replace_node(@selected JsonNumber(parse(Int, string(c))) value{1})
end

# A comma appends to the list `field` of the content of `view` a new document of
# the type `T`, and the caret goes to the view of the new document. A comma on the
# bracket that closes the node of `view` goes to the node around it.
_append_through_view(view::JsonView, field::Symbol, T::Type) =
    is_on_closing_delimiter(get_selection(view); from = 1) ? nothing :
    append_insertion_operation(view.viewed, field, T)

@gestures JsonArrayView begin
    KeyPress(',') => "Insert a new element" => _append_through_view(doc, :elements, JsonInsertion)
end

@gestures JsonObjectView begin
    KeyPress(',') => "Insert a new entry" => _append_through_view(doc, :entries, JsonObjectEntry)
    nothing       => "Sort the entries by key" =>
        ReplaceReferencedValueOperation(doc.viewed, "entries", sort(doc.viewed.entries; by = _json_entry_sort_key))
end

# The caret of the view of an entry moves from the field `from` of the entry to its
# field `to`: the move of the content, read against the caret of the view.
function _move_in_entry(view::JsonObjectEntryView; from::Symbol, to::Symbol)
    caret = get_selection(view)
    caret isa Reference || return nothing
    move_to_field(view.viewed, get_content_path(view, caret); from, to)
end

@gestures JsonObjectEntryView begin
    KeyPress('\t') => "Move from key to value" => _move_in_entry(doc; from = :key, to = :value)
    # The way back has no key of its own, as in the table of the object.
    nothing        => "Move from value to key" => _move_in_entry(doc; from = :value, to = :key)
end

# Return in the place for a new value: the document that the typed text names, in
# the place of the node of the view; `nothing` when the text names none.
function _commit_through_view(view::JsonInsertionView)
    insertion = view.viewed
    document = _commit_json_insertion(insertion, something(insertion.value, ""))
    document === nothing ? nothing : _replace_node(document)
end

@gestures JsonInsertionView begin
    KeyPress('\n')   => "Commit insertion" => _commit_through_view(doc)
    KeyDown(:escape) => "Cancel insertion" => _replace_node(get_nothing_document(JsonInsertion)())
    KeyPress('\t')   => "Accept completion" =>
        make_completion_operation(doc.viewed, get_selection(doc); completion = _complete_json_insertion)
    # Each place of JSON takes a document of any domain, so the place of JSON can
    # become the place of every domain.
    KeyDown(:insert) => "Widen the insertion to every domain" => make_insertion_widen_operation(doc.viewed)
end

@gestures JsonNothingView begin
    KeyDown(:insert) => "Insert a new json document" => insert_document_operation(JsonInsertion)
end
