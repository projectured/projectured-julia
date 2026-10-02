# ── Atomic Book leaves — one meaningful instance each, for the catalog. ──
make_book_paragraph_document_example() =
    BookParagraph(TextBlock(TextString("Reactive cells propagate changes automatically.",
                                       StyleFont("Ubuntu Mono", 20), color_default)))
make_book_picture_document_example() = BookPicture("projectured.png")
make_book_insertion_document_example() = BookInsertion()

# Minimal non-empty compound (node) documents — one child each, for the catalog.
make_book_chapter_document_example() = BookChapter("Introduction", "1", [make_book_paragraph_document_example()])
make_book_list_document_example()    = BookList([make_book_paragraph_document_example()])
make_book_book_document_example()    =
    BookBook("Projectured User Guide", "The Projectured Authors",
             [BookChapter("Introduction", "1", [make_book_paragraph_document_example()])])

function make_book_document_example()
    BookBook(
        "Projectured User Guide",
        "The Projectured Authors",
        [
            BookChapter(
                "Introduction",
                "1",
                [
                    BookParagraph(
                        TextBlock(
                            TextString("Projectured is a structure editor framework built around ", StyleFont("Ubuntu Mono", 20), color_default),
                            TextString("projections", StyleFont("Ubuntu Mono", 20; weight = 700), color_default),
                            TextString(" — composable functions that map document ", StyleFont("Ubuntu Mono", 20), color_default),
                            TextString("trees to renderable syntax trees.", StyleFont("Ubuntu Mono", 20), color_default),
                        )
                    ),
                    BookParagraph(
                        TextBlock(
                            TextString("Every node type in the document domain has a ", StyleFont("Ubuntu Mono", 20), color_default),
                            TextString("corresponding projection that converts it into ", StyleFont("Ubuntu Mono", 20), color_default),
                            TextString("a SyntaxNode or SyntaxLeaf.", StyleFont("Ubuntu Mono", 20), color_default),
                        )
                    ),
                    BookList([
                        BookParagraph(TextBlock(TextString("Reactive cells propagate changes automatically.", StyleFont("Ubuntu Mono", 20), color_default))),
                        BookParagraph(TextBlock(TextString("Forward and backward reference mapping enables editing.", StyleFont("Ubuntu Mono", 20), color_default))),
                        BookParagraph(TextBlock(TextString("Projections are composable via ChainingProjection.", StyleFont("Ubuntu Mono", 20), color_default))),
                    ]),
                ],
            ),
            BookChapter(
                "Projection Pipeline",
                "2",
                [
                    BookParagraph(
                        TextBlock(
                            TextString("A projection pipeline typically consists of four stages: ", StyleFont("Ubuntu Mono", 20), color_default),
                            TextString("domain → syntax → text → graphics → screen.", StyleFont("Ubuntu Mono", 20; weight = 700), color_default),
                        )
                    ),
                    BookList([
                        BookParagraph(TextBlock(TextString("BookToSyntax — converts the book tree to a syntax tree.", StyleFont("Ubuntu Mono", 20), color_default))),
                        BookParagraph(TextBlock(TextString("SyntaxToText — lays out the syntax tree as text lines.", StyleFont("Ubuntu Mono", 20), color_default))),
                        BookParagraph(TextBlock(TextString("TextToGraphics — renders text lines into graphic primitives.", StyleFont("Ubuntu Mono", 20), color_default))),
                        BookParagraph(TextBlock(TextString("GraphicsCaching — composites the final image.", StyleFont("Ubuntu Mono", 20), color_default))),
                    ]),
                    BookParagraph(
                        TextBlock(
                            TextString("Pictures can be embedded inline using BookPicture nodes.", StyleFont("Ubuntu Mono", 20), color_default),
                        )
                    ),
                    BookPicture("projectured.png"),
                ],
            ),
            BookChapter(
                "Future Work",
                "3",
                [
                    BookParagraph(
                        TextBlock(
                            TextString("Future work includes syntax highlighting, ", StyleFont("Ubuntu Mono", 20), color_default),
                            TextString("collaborative editing, and export to HTML and PDF.", StyleFont("Ubuntu Mono", 20), color_default),
                        )
                    ),
                ],
            ),
        ],
    )
end
