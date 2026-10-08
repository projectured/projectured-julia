# A small Lisp function in a scroll pane, whose body and whose `cond` put their
# parts on lines of their own, so each folds as a region of lines.
function make_syntax_folding_document_example()
    leaf(text) = SyntaxLeaf(text)
    call(parts...) = SyntaxNode(SyntaxDocument[parts...]; open = "(", close = ")", sep = " ")
    clauses = SyntaxNode(SyntaxDocument[
        leaf("cond"),
        call(call(leaf("<="), leaf("n"), leaf("1")), leaf("1")),
        call(leaf("t"), call(leaf("*"), leaf("n"), call(leaf("factorial"), call(leaf("-"), leaf("n"), leaf("1"))))),
    ]; open = "(", close = ")", sep = " ", indentation = 1)
    body = SyntaxNode(SyntaxDocument[
        leaf("defun"), leaf("factorial"), call(leaf("n")), clauses,
    ]; open = "(", close = ")", sep = " ", indentation = 1)
    WidgetScrollPane(body; size = Point2D(420, 220))
end
