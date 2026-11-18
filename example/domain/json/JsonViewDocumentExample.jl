# One JSON string in two views at three places of a vertical layout. The first and
# the third place show view A, so they share its caret; the second place shows
# view B, with a caret of its own. The string holds no caret.
function make_json_string_view_document_example()
    json_string = JsonString("one string, two views")
    view_a = JsonStringView(json_string)
    view_b = JsonStringView(json_string)
    layout = VerticalLayout([view_a, view_b, view_a]; gap = 20)
    # The caret of view B first, so it stays when the focus goes to view A.
    replace_selection!(layout, concat_references(@reference(layout, children[2]), @reference(view_b, value{4})))
    replace_selection!(layout, concat_references(@reference(layout, children[1]), @reference(view_a, value{11})))
    layout
end

# One JSON array in two views at three places. View A, at the first and the third
# place, folds its nested array; view B, at the second place, keeps it open and
# has its caret in it. The arrays hold no fold and no caret.
function make_json_array_view_document_example()
    nested = JsonArray([JsonString("a fold"), JsonString("of each view")])
    array = JsonArray([JsonString("one array"), JsonNumber(2), nested])
    view_a = JsonArrayView(array)
    view_b = JsonArrayView(array)
    view_a.elements[3].collapsed = true
    layout = VerticalLayout([view_a, view_b, view_a]; gap = 20)
    replace_selection!(layout, concat_references(@reference(layout, children[2]),
                                                 @reference(view_b, elements[3].elements[1].value{2})))
    layout
end

# One JSON array in two views at four places: each view is at a place of the whole
# view and at a place of the view of its nested array. The places of view A share
# its caret, which goes through the place of the whole view, so that place draws it
# as the live one and the place of the part draws it as a dormant one. View B folds
# the nested array, at both of its places. The arrays hold no fold and no caret.
function make_json_view_places_document_example()
    nested = JsonArray([JsonString("a part"), JsonString("at a place of its own")])
    array = JsonArray([JsonString("one array"), JsonNumber(2), nested])
    view_a = JsonArrayView(array)
    view_b = JsonArrayView(array)
    view_b.elements[3].collapsed = true
    layout = VerticalLayout([view_a, view_a.elements[3], view_b, view_b.elements[3]]; gap = 20)
    replace_selection!(layout, concat_references(@reference(layout, children[1]),
                                                 @reference(view_a, elements[3].elements[1].value{2})))
    layout
end

# One JSON object in two views at three places. View A, at the first and the third
# place, folds the object of its entry `size`; view B, at the second place, keeps it
# open and has its caret in a key of that object. The last entry holds the place
# where a person types a new value. The objects hold no fold and no caret.
function make_json_object_view_document_example()
    size = JsonObject("width" => JsonNumber(30), "height" => JsonNumber(45))
    object = JsonObject("name" => JsonString("one object"), "size" => size, "next" => JsonInsertion())
    view_a = JsonObjectView(object)
    view_b = JsonObjectView(object)
    view_a.entries[2].value.collapsed = true
    layout = VerticalLayout([view_a, view_b, view_a]; gap = 20)
    replace_selection!(layout, concat_references(@reference(layout, children[2]),
                                                 @reference(view_b, entries[2].value.entries[1].key{2})))
    layout
end

# One JSON file in two file views, side by side. Each file view shows the file
# through views: the view of the undo buffer of the file, and the views of the JSON
# document. So each place keeps a caret and a scroll of its own, and the two places
# share the undo steps of the file. View A, on the left, folds the array of the
# entry `list`. View B has its caret in the last element of that array, which is a
# document of a type that has no view: the caret is in that part, below the step
# `viewed` of the view of the list. The file, the undo buffer and the JSON document
# hold no fold and no caret.
function make_json_file_view_document_example()
    list = JsonArray([JsonNumber(1), JsonNumber(2), PrimitiveString("a part with no view")])
    object = JsonObject("name" => JsonString("one file, two places"), "list" => list)
    file = JsonFile("people.json", UndoBuffer(object))
    view_a = make_file_view(file; views = true)
    view_b = make_file_view(file; views = true)
    view_a.content.content.entries[2].value.collapsed = true
    # A file view takes all the space of its place, so each one gets a half of the
    # width.
    layout = HorizontalLayout([LayoutConstraint(view_a; width = Fill), LayoutConstraint(view_b; width = Fill)];
                              gap = 20)
    # The caret of view B first, so it stays when the focus goes to view A.
    replace_selection!(layout, concat_references(
        @reference(layout, children[2].child),
        @reference(view_b, content.content.entries[2].value.elements.viewed[3].value{2})))
    replace_selection!(layout, concat_references(
        @reference(layout, children[1].child),
        @reference(view_a, content.content.entries[1].value.value{3})))
    layout
end
