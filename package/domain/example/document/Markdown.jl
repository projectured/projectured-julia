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
