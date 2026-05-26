function make_syntax_document_example()
    document = SyntaxNode("[", "]", ", ",
        SyntaxDocument[
            SyntaxLeaf("\"", "\"", "hello"),
            SyntaxLeaf("\"", "\"", "world"),
        ]; indentation=1)
    set_selection!(document, @reference children[1].value{1})
    document
end
