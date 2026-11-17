# Fragment of `MarkdownModule`.
#
# The views of Markdown. A view keeps the state of one view of a Markdown document,
# which is its caret. A view of a compound holds the views of its children under the
# name of the field in which the compound holds them: `elements` for the root,
# `content` for a heading and a paragraph. So a path of the document, such as
# `.elements[2].content[1].content{3}`, is a path of its view.
#
# A child takes the view of its own type (`make_content_view`), so an element of the
# root that is no Markdown, such as a JSON array, takes the view of its domain, and
# no code here names that domain. A Markdown type that has no view prints as
# content.

"""
    MarkdownView

The supertype of the views of the Markdown documents.
"""
abstract type MarkdownView <: ContentView end

"""
    MarkdownTextView(viewed::MarkdownText)

A view of the run of text `viewed`. Its caret is a path of the run, such as
`.content{3}`, which the view reads through the run.
"""
@content_view MarkdownText struct MarkdownTextView <: MarkdownView end

"""
    MarkdownParagraphView(viewed::MarkdownParagraph)

A view of the paragraph `viewed`. `content` holds the view of the list of the
inline nodes of the paragraph (`CellVectorView`).
"""
@content_view MarkdownParagraph struct MarkdownParagraphView <: MarkdownView end

"""
    MarkdownHeadingView(viewed::MarkdownHeading)

A view of the heading `viewed`. `content` holds the view of the list of the inline
nodes of the heading (`CellVectorView`).
"""
@content_view MarkdownHeading struct MarkdownHeadingView <: MarkdownView end

"""
    MarkdownRootView(viewed::MarkdownRoot)

A view of the Markdown document `viewed`. `elements` holds the view of the list of
the blocks of the document (`CellVectorView`); a block of another domain has the
view of that domain, with the state of that view, such as the fold of a JSON array.

# Example

    root = MarkdownRoot([MarkdownParagraph([MarkdownText("The values:")]),
                         JsonArray([JsonString("a")])])
    view = MarkdownRootView(root)
    view.elements[1]       # a MarkdownParagraphView
    view.elements[2]       # a JsonArrayView, which a second place can show
"""
@content_view MarkdownRoot struct MarkdownRootView <: MarkdownView end
