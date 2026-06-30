function make_book_document_example()
    BookBook(
        [
            BookChapter(
                [
                    BookParagraph(
                        TextText(
                            TextString("Projectured is a structure editor framework built around ", font_ubuntu_monospace_regular_20, color_default),
                            TextString("projections", font_ubuntu_monospace_bold_20, color_default),
                            TextString(" — composable functions that map document ", font_ubuntu_monospace_regular_20, color_default),
                            TextString("trees to renderable syntax trees.", font_ubuntu_monospace_regular_20, color_default),
                        )
                    ),
                    BookParagraph(
                        TextText(
                            TextString("Every node type in the document domain has a ", font_ubuntu_monospace_regular_20, color_default),
                            TextString("corresponding projection that converts it into ", font_ubuntu_monospace_regular_20, color_default),
                            TextString("a SyntaxNode or SyntaxLeaf.", font_ubuntu_monospace_regular_20, color_default),
                        )
                    ),
                    BookList([
                        BookParagraph(TextText(TextString("Reactive cells propagate changes automatically.", font_ubuntu_monospace_regular_20, color_default))),
                        BookParagraph(TextText(TextString("Forward and backward reference mapping enables editing.", font_ubuntu_monospace_regular_20, color_default))),
                        BookParagraph(TextText(TextString("Projections are composable via SequentialProjection.", font_ubuntu_monospace_regular_20, color_default))),
                    ]),
                ];
                title="Introduction",
                numbering="1",
            ),
            BookChapter(
                [
                    BookParagraph(
                        TextText(
                            TextString("A projection pipeline typically consists of four stages: ", font_ubuntu_monospace_regular_20, color_default),
                            TextString("domain → syntax → text → graphics → screen.", font_ubuntu_monospace_bold_20, color_default),
                        )
                    ),
                    BookList([
                        BookParagraph(TextText(TextString("BookToSyntax — converts the book tree to a syntax tree.", font_ubuntu_monospace_regular_20, color_default))),
                        BookParagraph(TextText(TextString("SyntaxToText — lays out the syntax tree as text lines.", font_ubuntu_monospace_regular_20, color_default))),
                        BookParagraph(TextText(TextString("TextToGraphics — renders text lines into graphic primitives.", font_ubuntu_monospace_regular_20, color_default))),
                        BookParagraph(TextText(TextString("GraphicsCaching — composites the final image.", font_ubuntu_monospace_regular_20, color_default))),
                    ]),
                    BookParagraph(
                        TextText(
                            TextString("Pictures can be embedded inline using BookPicture nodes.", font_ubuntu_monospace_regular_20, color_default),
                        )
                    ),
                    BookPicture("projectured.png"),
                ];
                title="Projection Pipeline",
                numbering="2",
            ),
            BookChapter(
                [
                    BookParagraph(
                        TextText(
                            TextString("Future work includes syntax highlighting, ", font_ubuntu_monospace_regular_20, color_default),
                            TextString("collaborative editing, and export to HTML and PDF.", font_ubuntu_monospace_regular_20, color_default),
                        )
                    ),
                ];
                title="Future Work",
                numbering="3",
            ),
        ];
        title="Projectured User Guide",
        author="The Projectured Authors",
    )
end
