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
