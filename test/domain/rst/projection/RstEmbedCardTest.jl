# An embedded file stands in a card on an RST page, at the root and inside a
# section, as it does on a markdown page. A section puts its title first, so
# the card's block sits one further along than it does in the section.

function test_rst_embed_card()
@testset "an embedded file wears a card on an RST page" begin

function _page()
    root = parse_rst("Title\n=====\n\nSome prose.\n")
    section = root.elements[1]
    file = TextFile("numbers.txt", "one two three\n")
    push!(section.elements, file)
    top = TextFile("top.txt", "a line\n")
    push!(root.elements, top)
    root, section, file, top
end

into(field, i, rest) = ConcreteReference(FieldReferenceStep(field),
                           ConcreteReference(RangeReferenceStep(i - 1, i), rest))
inside = ConcreteReference(FieldReferenceStep("content"), EmptyReference())

@testset "the root cards its file and keeps its section" begin
    root, section, file, top = _page()
    iomap = print_document(RstRootToVerticalLayout(), nothing, root, PrinterContext())
    children = collect(iomap.output.children)
    @test children[1] === section
    @test children[2] isa WidgetCard
    @test children[2].content === top
    @test children[2].title.content == "top.txt"
    forward = map_reference_forward(iomap.projection, iomap, into("elements", 2, inside))
    @test forward.tail.tail.head.name == "content"
    @test forward.tail.tail.tail.head.name == "content"
    back = map_reference_backward(iomap.projection, iomap, forward)
    @test back.head.name == "elements" && back.tail.head.start == 1
    @test back.tail.tail.head.name == "content" && back.tail.tail.tail isa EmptyReference
    # The section is not a card: nothing is added on its way.
    through = map_reference_forward(iomap.projection, iomap, into("elements", 1, inside))
    @test through.tail.tail.tail isa EmptyReference
end

@testset "a section cards its file one slot along" begin
    root, section, file, top = _page()
    iomap = print_document(RstSectionToVerticalLayout(), nothing, section, PrinterContext())
    children = collect(iomap.output.children)
    @test length(children) == 3              # the title, the paragraph, the file
    @test !(children[2] isa WidgetCard)
    @test children[3] isa WidgetCard
    @test children[3].content === file
    forward = map_reference_forward(iomap.projection, iomap, into("elements", 2, inside))
    @test forward.tail.head.start == 2       # the third child
    @test forward.tail.tail.head.name == "content"
    back = map_reference_backward(iomap.projection, iomap, forward)
    @test back.tail.head.start == 1
    @test back.tail.tail.head.name == "content" && back.tail.tail.tail isa EmptyReference
    # The card's header names the whole file.
    header = ConcreteReference(FieldReferenceStep("children"),
                 ConcreteReference(RangeReferenceStep(2, 3),
                     ConcreteReference(FieldReferenceStep("title"), EmptyReference())))
    named = map_reference_backward(iomap.projection, iomap, header)
    @test named.tail.head.start == 1 && named.tail.tail isa EmptyReference
    fold = ToggleCollapseOperation(children[3])
    @test read_intent(iomap.projection, iomap, fold) === fold
end

end
end
