# Fragment of `JsonModule`.
#
# The views of JSON. A view of a JSON string holds its content and the state of one
# view: the caret, a path into the string such as `.value{3}`, which the view reads
# through its content.

"""
    JsonStringView(content::JsonString)

A view of the JSON string `content`. Its caret is a path of the string, such as
`.value{3}`, or a place on a quote, which has no place in the string; it ends at
the view, so another view of the same string keeps a caret of its own. A viewing
step of `JsonToSyntax` prints it as the `SyntaxLeafView` of the leaf of the string.
"""
@document struct JsonStringView <: ContentView
    content::JsonString
end

# The view of a string, which a parent view makes for it and a viewing step prints.
make_content_view(content::JsonString) = JsonStringView(content)
