# Fragment of `JsonModule`.
#
# The views of JSON. A view keeps the state of one view of a JSON document: the
# caret, and the fold of an array. A view of a leaf holds its content; its caret is
# a path into the leaf, such as `.value{3}`, which the view reads through its
# content. A view of an array also holds the views of its elements, at `elements`,
# as the array holds its elements, so a path such as `.elements[2].value{3}` is a
# path of the view and of its array.

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

# The view that the caret of `view` names, when it is a view of a node that a
# replace may retype: not the view itself, whose content has no place of its own
# before the places of the plan, and not an entry of an object, which stays a key
# and a value.
function _find_replaceable_view(view::JsonView)
    caret = view.selection
    caret === nothing && return nothing
    path = normalize_named_node_reference(caret)
    path isa ConcreteReference || return nothing
    named = try_evaluate_reference(view, path, nothing)
    (named isa JsonView && !(getproperty(named, :viewed) isa JsonObjectEntry)) ? named : nothing
end

# A replace of the node that the caret names, as an edit of the content: the new
# node goes into the content, and the caret that it brings goes to its view.
function _replace_through_view(view::JsonView, replacement)
    _find_replaceable_view(view) === nothing && return nothing
    make_content_edit(replace_selected_document(view, replacement))
end

@gestures JsonView begin
    when(_find_replaceable_view(doc) !== nothing)
    KeyPress('n') => "Replace with null"   => _replace_through_view(doc, @selected JsonNull())
    KeyPress('f') => "Replace with false"  => _replace_through_view(doc, make_insertion_document(JsonBool))
    KeyPress('t') => "Replace with true"   => _replace_through_view(doc, @selected JsonBool(true))
    KeyPress('"') => "Replace with a string" => _replace_through_view(doc, make_insertion_document(JsonString))
    KeyPress('[') => "Replace with an array" => _replace_through_view(doc, make_insertion_document(JsonArray))
    KeyPress('{') => "Replace with an object" => _replace_through_view(doc, make_insertion_document(JsonObject))
    when(KeyPress(c), isdigit(c)) => "Replace with a number" =>
        _replace_through_view(doc, @selected JsonNumber(parse(Int, string(c))) value{1})
end

# The innermost view of an array around the caret `caret` of `view`, with its path
# from `view`: the caret goes down through the views of the elements that are
# arrays, and an array whose own closing bracket holds the caret leaves the key to
# the array around it.
function _find_innermost_array(view::JsonArrayView, caret)
    caret isa Reference || return nothing
    plain = strip_reference_types(caret)
    if plain isa ConcreteReference && plain.head isa FieldReferenceStep && plain.head.name == "elements"
        indexed = plain.tail
        if indexed isa ConcreteReference && indexed.head isa RangeReferenceStep
            element = try_evaluate_reference(view,
                ConcreteReference(plain.head, ConcreteReference(indexed.head, EmptyReference())), nothing)
            if element isa JsonArrayView
                inner = _find_innermost_array(element, indexed.tail)
                inner === nothing || return (inner[1],
                    ConcreteReference(plain.head, ConcreteReference(indexed.head, inner[2])))
            end
        end
    end
    is_on_closing_delimiter(caret) ? nothing : (view, EmptyReference())
end

# A comma appends a new element to the innermost array around the caret, as an edit
# of its content, and the caret goes to the view of the new element.
function _append_element_through_view(view::JsonArrayView)
    found = _find_innermost_array(view, view.selection)
    found === nothing && return nothing
    array_view, path = found
    edit = make_content_edit(append_insertion_operation(array_view.viewed, :elements, JsonInsertion))
    path isa EmptyReference ? edit : reroot_operation(edit, Tuple(get_reference_steps(path)))
end

@gestures JsonArrayView begin
    KeyPress(',') => "Insert a new element" => _append_element_through_view(doc)
end
