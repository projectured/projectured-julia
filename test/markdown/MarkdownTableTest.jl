# A table on a markdown page is drawn as a widget table.
#
# The table of the page and the widget table share their entries: the entries
# are the paragraphs of the table, so the page draws each one as prose, and both
# maps only rename the steps between the page and an entry.

function test_markdown_page_table()
@testset "a table on a page is a widget table" begin

_measure = (t, f) -> (length(t) * 8, 16)

function _table_texts(node, found = String[])
    if node isa GraphicsCanvas
        for element in node.elements
            _table_texts(element, found)
        end
    elseif node isa GraphicsViewport
        _table_texts(node.content, found)
    elseif node isa GraphicsText
        push!(found, string(node.text))
    end
    found
end

# The table of `kernel/selection.md`, cut to three rows, between two paragraphs.
source = """
Different domains interpret selection paths differently.

| Type | `selection` meaning |
|---|---|
| `JsonArray` | `[i] + <child path>` — into element `i` (1-based) |
| `SyntaxLeaf` | `.open/.value/.close + {k}` — cursor at offset `k` in the named span |
| `TextBlock` | `{k}` — flat cursor at offset `k` in the concatenated spans |

After the table.
"""

layout_of(page) = print_document(MarkdownRootToVerticalLayout(), nothing, page,
                                 PrinterContext()).output

@testset "the table is a widget table that holds the paragraphs of the table" begin
    page = parse_markdown(source)
    table = page.elements[2]
    @test table isa MarkdownTable
    children = collect(layout_of(page).children)
    @test length(children) == 3
    widget = children[2]
    @test widget isa WidgetTable
    @test widget.column_count == 2
    @test widget.cell_policy === :wrap
    @test collect(widget.column_headers)[1] === table.header.elements[1]
    @test collect(widget.column_headers)[2] === table.header.elements[2]
    @test length(widget.rows) == 3
    @test collect(widget.rows[3])[2] === table.rows[3].elements[2]
    @test !(children[1] isa WidgetTable)
end

@testset "the widget table is the same after a block is added" begin
    page = parse_markdown(source)
    layout = layout_of(page)
    before = collect(layout.children)[2]
    insert!(page.elements, 1, parse_markdown("A new first line.\n").elements[1])
    after = collect(layout.children)
    @test length(after) == 4
    @test after[3] === before
end

@testset "the maps rename the steps to an entry and keep the rest" begin
    page = parse_markdown(source)
    iomap = print_document(MarkdownRootToVerticalLayout(), nothing, page, PrinterContext())
    p = iomap.projection
    element(i, rest) = ConcreteReference(FieldReferenceStep("elements"),
                           ConcreteReference(RangeReferenceStep(i - 1, i), rest))
    child(i, rest) = ConcreteReference(FieldReferenceStep("children"),
                         ConcreteReference(RangeReferenceStep(i - 1, i), rest))
    field(name, rest) = ConcreteReference(FieldReferenceStep(name), rest)
    index(j, rest) = ConcreteReference(RangeReferenceStep(j - 1, j), rest)
    inside = field("content", EmptyReference())
    # An entry of a body row: `rows[k].elements[j]` is `rows[k][j]`.
    body = element(2, field("rows", index(3, field("elements", index(2, inside)))))
    @test map_reference_forward(p, iomap, body) ==
          child(2, field("rows", index(3, index(2, inside))))
    @test map_reference_backward(p, iomap, map_reference_forward(p, iomap, body)) == body
    # An entry of the header: `header.elements[j]` is `column_headers[j]`.
    header = element(2, field("header", field("elements", index(1, inside))))
    @test map_reference_forward(p, iomap, header) ==
          child(2, field("column_headers", index(1, inside)))
    @test map_reference_backward(p, iomap, map_reference_forward(p, iomap, header)) == header
    # The whole table is the whole widget table, and a whole row is a whole row.
    @test map_reference_forward(p, iomap, element(2, EmptyReference())) ==
          child(2, EmptyReference())
    row = element(2, field("rows", index(1, EmptyReference())))
    @test map_reference_forward(p, iomap, row) == child(2, field("rows", index(1, EmptyReference())))
    # The widget draws no alignment, so a path to it maps to nothing.
    @test map_reference_forward(p, iomap, element(2, field("alignments", EmptyReference()))) === nothing
    # A paragraph around the table is not renamed.
    @test map_reference_forward(p, iomap, element(3, inside)) == child(3, inside)
end

@testset "the page draws every entry, and a long entry breaks inside its column" begin
    page = parse_markdown(source)
    renderer = NaturalToGraphics(measure = _measure)
    context = with_available_size(PrinterContext(); width = Cell(Int32(400)),
                                                    height = Cell(Int32(800)))
    chain = ChainingProjection(MarkdownRootToVerticalLayout(), VerticalLayoutToGraphicsCanvas())
    texts = _table_texts(print_document(chain, renderer, page, context).output)
    drawn = join(texts, " ")
    for word in ("Type", "meaning", "JsonArray", "SyntaxLeaf", "TextBlock", "concatenated")
        @test occursin(word, drawn)
    end
    # No line of the table is wider than the page.
    @test maximum(length(text) * 8 for text in texts) <= 400
end

end
end # test_markdown_page_table
