# An embedded file stands in a card on a markdown page.
#
# The page stops and the file starts, and the card says where: its title is the
# file's name, and a person can fold it. The card is the projection's, so the
# page's own references do not see it — both maps add and drop its one step.

function test_markdown_embed_card()
@testset "an embedded file wears a card titled with its name" begin

_measure = (t, f) -> (length(t) * 8, 16)

function _texts(node, found = String[])
    if node isa GraphicsCanvas
        for element in node.elements
            _texts(element, found)
        end
    elseif node isa GraphicsViewport
        _texts(node.content, found)
    elseif node isa GraphicsText
        push!(found, string(node.text))
    end
    found
end

# A page of a heading, a paragraph and a text file, as a load splices one.
function _page()
    page = parse_markdown("# Notes\n\nThe file below holds the numbers.\n")
    file = TextFile("numbers.txt", "one two three\n")
    push!(page.elements, file)
    page, file
end

layout_of(page) = print_document(MarkdownRootToVerticalLayout(), nothing, page,
                                 PrinterContext()).output

@testset "the file is a card, and prose is not" begin
    page, file = _page()
    children = collect(layout_of(page).children)
    @test length(children) == 3
    @test !(children[1] isa WidgetCard)
    @test !(children[2] isa WidgetCard)
    card = children[3]
    @test card isa WidgetCard
    @test card.content === file
    @test card.title.content == "numbers.txt"
    @test card.collapsible == true
end

@testset "the card is the same card after a block is added" begin
    page, file = _page()
    layout = layout_of(page)
    before = collect(layout.children)[3]
    insert!(page.elements, 1, parse_markdown("A new first line.\n").elements[1])
    after = collect(layout.children)
    @test length(after) == 4
    @test after[4] === before
end

@testset "the maps add and drop the card's step" begin
    page, file = _page()
    iomap = print_document(MarkdownRootToVerticalLayout(), nothing, page, PrinterContext())
    p = iomap.projection
    into(i, rest) = ConcreteReference(FieldReferenceStep("elements"),
                        ConcreteReference(RangeReferenceStep(i - 1, i), rest))
    inside = ConcreteReference(FieldReferenceStep("content"), EmptyReference())
    # Into the file: the card's body step is added.
    forward = map_reference_forward(p, iomap, into(3, inside))
    @test forward.head.name == "children"
    @test forward.tail.tail.head.name == "content"
    @test forward.tail.tail.tail.head.name == "content"
    # The whole file is the whole card: no step is added.
    whole = map_reference_forward(p, iomap, into(3, EmptyReference()))
    @test whole.tail.tail isa EmptyReference
    # Into a paragraph: nothing is added.
    prose = map_reference_forward(p, iomap, into(2, inside))
    @test prose.tail.tail.head.name == "content"
    @test prose.tail.tail.tail isa EmptyReference
    # Back again, and the card's step is gone.
    back = map_reference_backward(p, iomap, forward)
    @test back.head.name == "elements"
    @test back.tail.tail.head.name == "content"
    @test back.tail.tail.tail isa EmptyReference
    # A path into the card's header names the whole file.
    header = ConcreteReference(FieldReferenceStep("children"),
                 ConcreteReference(RangeReferenceStep(2, 3),
                     ConcreteReference(FieldReferenceStep("title"), EmptyReference())))
    named = map_reference_backward(p, iomap, header)
    @test named.head.name == "elements"
    @test named.tail.head.start == 2
    @test named.tail.tail isa EmptyReference
end

@testset "the page draws the name, and a folded card hides the file" begin
    page, file = _page()
    renderer = NaturalToGraphics(measure = _measure)
    context = with_available_size(PrinterContext(); width = Cell(Int32(600)),
                                                    height = Cell(Int32(800)))
    # The page's own chain, with the renderer as what draws each block.
    chain = ChainingProjection(MarkdownRootToVerticalLayout(), VerticalLayoutToGraphicsCanvas())
    iomap = print_document(chain, renderer, page, context)
    drawn = _texts(iomap.output)
    @test any(t -> occursin("numbers.txt", t), drawn)
    @test any(t -> occursin("one two three", t), drawn)
    card = collect(iomap.step_iomaps[1][].output.children)[3]
    @test card isa WidgetCard
    card.collapsed = true
    folded = _texts(iomap.output)
    @test any(t -> occursin("numbers.txt", t), folded)
    @test !any(t -> occursin("one two three", t), folded)
end

@testset "a fold passes through the page's reader" begin
    page, file = _page()
    iomap = print_document(MarkdownRootToVerticalLayout(), nothing, page, PrinterContext())
    card = collect(iomap.output.children)[3]
    fold = ToggleCollapseOperation(card)
    @test read_intent(iomap.projection, iomap, fold) === fold
end

end
end
