"""
A workbench panel's CONTENT is replaceable — an editor reloaded from disk, a
console handed a new block, an evaluator given a new expression — and the pane
must follow.

It did not. `WidgetScrollPane`'s constructor wraps whatever it is given in
`Cell(content)`, a **constant**, so a printer that projected the content once and
handed over the result froze it: a later write to the panel's content had no
reactive edge and the pane kept rendering the document it was born with. Nothing
errored. It simply stopped updating, which is why nothing caught it — every test
here re-printed.

That is PAR-REACTIVE-OUTPUT-STRUCTURE's failure mode exactly, so these assertions
hold ONE printed pane and write to the domain behind it.
"""

function test_workbench_content_pane()
@testset "WorkbenchContentPane" begin

recursion = RecursiveProjection(IdentityProjection())
printed(p, node) = print_document(p, recursion, node, PrinterContext())

# Compared by IDENTITY, not by value: a document keeps `==` (PAR-DOCUMENT-IDENTITY),
# so two equal-looking PrimitiveStrings are not equal and only `===` says what
# this test means — "the pane is showing THIS object".
@testset "an editor's content is replaceable" begin
    before, after = PrimitiveString("before"), PrimitiveString("after")
    e = WorkbenchEditor(before; title = "t", filename = "f.txt")
    pane = printed(WorkbenchEditorToWidgetScrollPane(), e).output
    @test pane.content === before

    e.content = after
    @test pane.content === after       # the pane FOLLOWED, with no re-print
end

@testset "an evaluator's content likewise" begin
    first, second = PrimitiveString("1 + 1"), PrimitiveString("2 + 2")
    v = WorkbenchEvaluator(first)
    vp = printed(WorkbenchEvaluatorToWidgetScrollPane(), v).output
    @test vp.content === first
    v.content = second
    @test vp.content === second
end

# Reconciling by identity is what makes the above affordable: replacing the
# content re-projects once, and leaving it alone reuses the same child IoMap, so
# nothing downstream is rebuilt on every frame.
@testset "an unchanged content is not re-projected" begin
    e = WorkbenchEditor(PrimitiveString("stable"); title = "t", filename = "f.txt")
    iomap = printed(WorkbenchEditorToWidgetScrollPane(), e)
    first_inner = iomap.inner_iomap
    @test iomap.inner_iomap === first_inner            # repeated reads are cached
    e.content = PrimitiveString("moved")
    @test iomap.inner_iomap !== first_inner            # ...and a real change re-projects
end

end
end
