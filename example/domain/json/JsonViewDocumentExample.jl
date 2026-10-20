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
