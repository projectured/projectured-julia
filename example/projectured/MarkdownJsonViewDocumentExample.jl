# One Markdown document that holds a JSON array, in one view at two places. The
# first place shows the view of the document, and the JSON array shows inside it.
# The second place shows the view of the array alone. It is the same view at both
# places, so the places share its caret and its fold, and the caret goes through
# the first place. The document and the array hold no caret and no fold.
function make_markdown_json_view_document_example()
    array = JsonArray([JsonString("a JSON part"), JsonNumber(2)])
    document = MarkdownRoot([MarkdownHeading(1, [MarkdownText("Settings")]),
                             MarkdownParagraph([MarkdownText("The values of the array:")]),
                             array])
    view = MarkdownRootView(document)
    layout = VerticalLayout([view, view.elements[3]]; gap = 20)
    replace_selection!(layout, concat_references(@reference(layout, children[1]),
                                                 @reference(view, elements[3].elements[1].value{2})))
    layout
end
