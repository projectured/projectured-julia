function make_syntax_document_example()
    SyntaxNode(SyntaxDocument[
        SyntaxLeaf("defun"),
        SyntaxLeaf("factorial"),
        SyntaxNode(SyntaxDocument[SyntaxLeaf("n")]; open="(", close=")", sep=" "),
        SyntaxNode(SyntaxDocument[
            SyntaxLeaf("if"),
            SyntaxNode(SyntaxDocument[
                SyntaxLeaf("<="), SyntaxLeaf("n"), SyntaxLeaf("1"),
            ]; open="(", close=")", sep=" "),
            SyntaxLeaf("1"),
            SyntaxNode(SyntaxDocument[
                SyntaxLeaf("*"),
                SyntaxLeaf("n"),
                SyntaxNode(SyntaxDocument[
                    SyntaxLeaf("factorial"),
                    SyntaxNode(SyntaxDocument[
                        SyntaxLeaf("-"), SyntaxLeaf("n"), SyntaxLeaf("1"),
                    ]; open="(", close=")", sep=" "),
                ]; open="(", close=")", sep=" "),
            ]; open="(", close=")", sep=" "),
        ]; open="(", close=")", sep=" "),
    ]; open="(", close=")", sep=" ", indentation=1)
end

# A bare leaf, standing alone rather than nested inside the tree above: an
# open/close-delimited value, the smallest thing `SyntaxLeaf`'s own printer
# renders.
make_syntax_leaf_document_example() = SyntaxLeaf("value"; open="\"", close="\"")
