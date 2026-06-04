function make_syntax_document_example()
    document = SyntaxNode("(", ")", " ", SyntaxDocument[
        SyntaxLeaf("defun"),
        SyntaxLeaf("factorial"),
        SyntaxNode("(", ")", " ", SyntaxDocument[SyntaxLeaf("n")]),
        SyntaxNode("(", ")", " ", SyntaxDocument[
            SyntaxLeaf("if"),
            SyntaxNode("(", ")", " ", SyntaxDocument[
                SyntaxLeaf("<="), SyntaxLeaf("n"), SyntaxLeaf("1"),
            ]),
            SyntaxLeaf("1"),
            SyntaxNode("(", ")", " ", SyntaxDocument[
                SyntaxLeaf("*"),
                SyntaxLeaf("n"),
                SyntaxNode("(", ")", " ", SyntaxDocument[
                    SyntaxLeaf("factorial"),
                    SyntaxNode("(", ")", " ", SyntaxDocument[
                        SyntaxLeaf("-"), SyntaxLeaf("n"), SyntaxLeaf("1"),
                    ]),
                ]),
            ]),
        ]),
    ]; indentation=1)
    set_selection!(document, @reference children[2].value{1})
    document
end
