# Wrap a text document in a find bar view: the text, highlighted or filtered by
# a pattern, under a collapsible card that holds a form of the fields of the
# pattern. Ctrl+F shows the bar and puts the caret in the pattern, and Escape
# hides it and puts the caret back in the text. The pattern "dolor" makes the
# highlight visible at once. Pairs with `make_find_bar_projection`. The gallery
# wraps a text example with it for `text_highlighting` and `text_filtering`.
function make_find_bar_document(document; filter::Bool = false)
    text = filter ? FilteredText(; text = document, pattern = "dolor") :
                    HighlightedText(; text = document, pattern = "dolor")
    title = filter ? "Filter" : "Find"
    rows = Any[(WidgetLabel(title), ObjectField(text, "pattern")),
               (WidgetLabel("Regular expression"), ObjectField(text, "regex")),
               (WidgetLabel("Ignore case"), ObjectField(text, "case_insensitive"))]
    filter && push!(rows, (WidgetLabel("Invert"), ObjectField(text, "invert")))
    bar = WidgetCard(; title = WidgetLabel(title), collapsible = true, content = FormLayout(rows))
    FindBarView(; bar, content = text)
end

# A text with a find bar above it: Ctrl+F puts the caret in the pattern, a key
# there highlights again, and the button beside the bar puts it over the text.
make_find_bar_document_example() = make_find_bar_document(_make_lorem_lines_block())

# A text with a filter bar above it: only the lines that match stay, or with
# Invert the lines that do not.
make_filter_bar_document_example() = make_find_bar_document(_make_lorem_lines_block(); filter = true)
