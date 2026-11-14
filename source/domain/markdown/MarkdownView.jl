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
@document struct MarkdownTextView <: MarkdownView
    viewed::MarkdownText
end

"""
    MarkdownParagraphView(viewed::MarkdownParagraph)

A view of the paragraph `viewed`. `content` holds the view of each inline node of
the paragraph, in their order, and follows them by identity (`make_child_views`).
"""
@document struct MarkdownParagraphView <: MarkdownView
    viewed::MarkdownParagraph
    content::CellVector
end

MarkdownParagraphView(viewed::MarkdownParagraph) =
    MarkdownParagraphView(viewed, make_child_views(viewed, :content))

"""
    MarkdownHeadingView(viewed::MarkdownHeading)

A view of the heading `viewed`. `content` holds the view of each inline node of the
heading, in their order, and follows them by identity (`make_child_views`).
"""
@document struct MarkdownHeadingView <: MarkdownView
    viewed::MarkdownHeading
    content::CellVector
end

MarkdownHeadingView(viewed::MarkdownHeading) =
    MarkdownHeadingView(viewed, make_child_views(viewed, :content))

"""
    MarkdownRootView(viewed::MarkdownRoot)

A view of the Markdown document `viewed`. `elements` holds the view of each block
of the document, in their order, and follows them by identity
(`make_child_views`); a block of another domain has the view of that domain, with
the state of that view, such as the fold of a JSON array.

# Example

    root = MarkdownRoot([MarkdownParagraph([MarkdownText("The values:")]),
                         JsonArray([JsonString("a")])])
    view = MarkdownRootView(root)
    view.elements[1]       # a MarkdownParagraphView
    view.elements[2]       # a JsonArrayView, which a second place can show
"""
@document struct MarkdownRootView <: MarkdownView
    viewed::MarkdownRoot
    elements::CellVector
end

MarkdownRootView(viewed::MarkdownRoot) =
    MarkdownRootView(viewed, make_child_views(viewed, :elements))

# The views that a parent view makes for its children, and that a viewing step prints.
make_content_view(content::MarkdownText) = MarkdownTextView(content)
make_content_view(content::MarkdownParagraph) = MarkdownParagraphView(content)
make_content_view(content::MarkdownHeading) = MarkdownHeadingView(content)
make_content_view(content::MarkdownRoot) = MarkdownRootView(content)
