# Atomic Markdown leaves — one meaningful instance each, for the catalog.
function make_markdown_text_document_example()
    MarkdownText("Hello, world")
end

make_markdown_code_document_example()            = MarkdownCode("Cell")
make_markdown_thematic_break_document_example()  = MarkdownThematicBreak()
make_markdown_insertion_document_example()       = MarkdownInsertion()

# Minimal non-empty compound (node) documents — one child each, for the catalog.
make_markdown_heading_document_example()   = MarkdownHeading(1, [MarkdownText("x")])
make_markdown_paragraph_document_example() = MarkdownParagraph([MarkdownText("x")])
make_markdown_list_document_example()      = MarkdownList(false, [MarkdownListItem([MarkdownParagraph([MarkdownText("x")])])])
make_markdown_emphasis_document_example()  = MarkdownEmphasis([MarkdownText("x")])
make_markdown_link_document_example()      = MarkdownLink([MarkdownText("x")], "url")

function make_markdown_document_example()
    MarkdownRoot([
        MarkdownHeading(1, [MarkdownText("ProjecturEd")]),
        MarkdownParagraph([
            MarkdownText("A "),
            MarkdownStrong([MarkdownText("projectional")]),
            MarkdownText(" editor: documents are "),
            MarkdownEmphasis([MarkdownText("structured data")]),
            MarkdownText(" shown through bidirectional projections."),
        ]),
        MarkdownHeading(2, [MarkdownText("Features")]),
        MarkdownList(false, [
            MarkdownListItem([MarkdownParagraph([MarkdownText("Composable projections")])]),
            MarkdownListItem([MarkdownParagraph([
                MarkdownText("Reactive "),
                MarkdownCode("Cell"),
                MarkdownText(" recomputation"),
            ])]),
            MarkdownListItem([MarkdownParagraph([
                MarkdownText("See the "),
                MarkdownLink([MarkdownText("guides")], "documentation/concepts.md"),
            ])]),
        ]),
        MarkdownHeading(2, [MarkdownText("Example")]),
        MarkdownCodeBlock("julia", "doc = markdownparse(\"# Hi\")\nrender(doc)"),
        MarkdownQuote([MarkdownParagraph([
            MarkdownText("Editing acts on the projection and maps back to the domain."),
        ])]),
        MarkdownThematicBreak(),
        MarkdownParagraph([
            MarkdownImage("logo", "logo.png"),
            MarkdownText(" the end."),
        ]),
    ])
end
