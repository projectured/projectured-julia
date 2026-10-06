# A table selects each part the same way, in its eager form and in the form that
# scrolls its own parts: a plain press goes to the content of a part first and
# one that the content declines selects its row or its column, an Alt+press
# selects the part itself, the header row and the header column are parts too,
# and the keys move along a strip of headers and step into the cells.

using ProjecturedKernel.CellModule: Cell, set_cell_computation!, set_cell_value!
using ProjecturedPlatform.CollectionModule: ListNode

function test_widget_table_part_selection()
@testset "a table selects each part the same way" begin

det = FixedMeasure(8, 12, 4, 0)
rec = RecursiveProjection(TypeDispatchingProjection(vcat(
    LayoutToGraphics().dispatch,
    WidgetToGraphics(StyleFont("Ubuntu", 20); measure = det).dispatch)))
context() = with_exact_size(PrinterContext(); width = Cell(Int32(600)), height = Cell(Int32(300)))
mods = ModifierKeys()
alt = ModifierKeys(alt = true)
read(io, g) = (change = read_intent(rec, nothing, Intent(g, nothing), io);
               change isa Intent ? change.operation : change)
key(io, name; kw...) = read(io, KeyDown(name, ModifierKeys(; kw...); time = 0.0))
path_of(op) = strip_reference_types(op.path)

part(field, i) = ConcreteReference(FieldReferenceStep(field),
    ConcreteReference(RangeReferenceStep(i - 1, i), EmptyReference()))
whole(field) = ConcreteReference(FieldReferenceStep(field), EmptyReference())
cell(r, c) = ConcreteReference(FieldReferenceStep("cells"),
    ConcreteReference(RangeReferenceStep(r - 1, r),
        ConcreteReference(RangeReferenceStep(c - 1, c), EmptyReference())))

# What the graphics draw, as (kind, x, y, w, h, what): each text and each
# rectangle, through viewports and down a list.
function drawn(node, ox = 0, oy = 0, found = Any[]; limit = 50)
    if node isa GraphicsCanvas
        elements = node.elements
        x, y = ox + Int(node.x), oy + Int(node.y)
        if elements isa ListNode
            for link in (:next, :prev)
                n = link === :next ? elements : elements.prev
                seen = 0
                while n !== nothing && seen < limit
                    drawn(n.value, x, y, found; limit)
                    n = getproperty(n, link)
                    seen += 1
                end
            end
        else
            foreach(element -> drawn(element, x, y, found; limit), elements)
        end
    elseif node isa GraphicsViewport
        drawn(node.content, ox + Int(node.x), oy + Int(node.y), found; limit)
    elseif node isa GraphicsText
        push!(found, (:text, ox + Int(node.x), oy + Int(node.y), 0, 0, string(node.text)))
    elseif node isa GraphicsRect
        push!(found, (:rect, ox + Int(node.x), oy + Int(node.y), Int(node.w), Int(node.h), string(node.color)))
    end
    found
end
text_at(io, text) = only((t[2], t[3]) for t in drawn(io.output) if t[1] === :text && t[6] == text)
press_text(io, text, modifiers) = ((x, y) = text_at(io, text);
                                   read(io, MouseClick(:left, x + 2, y + 2, modifiers; time = 0.0)))
box(io, path) = find_reference_box(io.output, map_reference_forward(io.projection, io, path))
# The rectangles that the selection `path` adds to what the table draws.
function band_of(table, io, path)
    getfield(table, :selection)[] = nothing
    before = Set(t for t in drawn(io.output) if t[1] === :rect && t[4] > 0 && t[5] > 0)
    getfield(table, :selection)[] = path
    after = [t for t in drawn(io.output) if t[1] === :rect && t[4] > 0 && t[5] > 0]
    getfield(table, :selection)[] = nothing
    [(x = t[2], y = t[3], w = t[4], h = t[5]) for t in after if t ∉ before]
end
covers_x(band, b) = band.x <= b.x && b.x + b.width <= band.x + band.w
covers_y(band, b) = band.y <= b.y && b.y + b.height <= band.y + band.h

# A list of `count` values, built as a walk reaches them; `value_of(i)` makes the
# value of node `i`.
function make_list_of(count::Int, value_of)
    function make_node(i, before)
        node = ListNode(value_of(i))
        before === nothing || set_cell_value!(getfield(node, :prev), before)
        set_cell_computation!(getfield(node, :next), () -> i < count ? make_node(i + 1, node) : nothing)
        node
    end
    make_node(1, nothing)
end
name(r, c) = "r$(r) c$(c)"
# Row 1 has a checkbox for its header, row 2 a text field, and row 3 a label.
function make_headers(check, field)
    header(r) = r == 1 ? check : r == 2 ? field : WidgetLabel("#$(r)")
    header
end
eager(check, field) = WidgetTable(; column_headers = Any["a", "b", "c"],
                                  row_headers = Any[make_headers(check, field)(r) for r in 1:3],
                                  cells = [[name(r, c) for c in 1:3] for r in 1:3])
listed(check, field) = WidgetTable(; column_headers = Any["a", "b", "c"],
                                   row_headers = make_list_of(3, make_headers(check, field)),
                                   cells = make_list_of(3, r -> make_widget_table_row(Any[name(r, c) for c in 1:3])),
                                   corner = WidgetLabel("corner"), column_policy = Fixed(60),
                                   row_policy = Fixed(24))

for (form, make) in (("eager", eager), ("list", listed))
    @testset "$(form): a plain press goes to the part first, and an Alt+press selects the part" begin
        check, field = WidgetCheckbox("x"), WidgetText("abc")
        table = make(check, field)
        io = print_document(rec, nothing, table, context())
        @test (io isa WidgetTableListIoMap) == (form == "list")
        # A header that declines a press selects its row or its column.
        @test path_of(press_text(io, "#3", mods)) == part("rows", 3)
        @test path_of(press_text(io, "b", mods)) == part("columns", 2)
        # A header that takes a press gets it: the checkbox toggles its own document.
        b = box(io, part("row_headers", 1))
        toggle = read(io, MouseClick(:left, b.x + 4, b.y + 4, mods; time = 0.0))
        @test toggle isa ReplaceReferencedValueOperation && toggle.document === check
        # A press in a text field of a row header puts the selection in it, and
        # then a key goes to it through the table.
        caret = press_text(io, "abc", mods)
        @test get_reference_steps(path_of(caret))[1:3] ==
              [FieldReferenceStep("row_headers"), RangeReferenceStep(1, 2), FieldReferenceStep("content")]
        set_selection!(table, caret.path)
        typed = read(io, KeyPress('X', "X", mods; time = 0.0))
        @test typed isa ReplaceStringRangeOperation
        @test get_reference_steps(strip_reference_types(typed.reference))[1:2] ==
              [FieldReferenceStep("row_headers"), RangeReferenceStep(1, 2)]
        getfield(table, :selection)[] = nothing
        # An Alt+press selects the header itself, of a row as of a column, and the cell.
        @test path_of(press_text(io, "#3", alt)) == part("row_headers", 3)
        @test path_of(press_text(io, "b", alt)) == part("column_headers", 2)
        @test path_of(press_text(io, name(2, 3), alt)) == cell(2, 3)
        @test path_of(press_text(io, name(2, 3), mods)) == part("rows", 2)
        if form == "list"
            # The corner takes a press first, and a declined one selects the
            # table; an Alt+press selects the corner, which shows its band.
            @test path_of(press_text(io, "corner", mods)) == EmptyReference()
            @test path_of(press_text(io, "corner", alt)) == whole("corner")
            corner_box = box(io, whole("corner"))
            band = band_of(table, io, whole("corner"))
            @test !isempty(band) && all(r -> covers_x(r, corner_box) && covers_y(r, corner_box), band)
        end
    end

    @testset "$(form): the header row and the header column are parts with a band" begin
        table = make(WidgetCheckbox("x"), WidgetText("abc"))
        io = print_document(rec, nothing, table, context())
        first_cell = box(io, cell(1, 1))
        row_header = box(io, part("row_headers", 1))
        column_header = box(io, part("column_headers", 1))
        # The header row: over each column header, above the cells, right of the
        # header column.
        band = band_of(table, io, whole("column_headers"))
        @test !isempty(band)
        @test all(r -> r.y + r.h <= first_cell.y && r.x >= row_header.x + row_header.width, band)
        for c in 1:3
            header = box(io, part("column_headers", c))
            @test any(r -> covers_x(r, header) && covers_y(r, header), band)
        end
        # The header column: beside each row header, left of the cells, under
        # the header row.
        band = band_of(table, io, whole("row_headers"))
        @test !isempty(band)
        @test all(r -> r.x + r.w <= first_cell.x && r.y >= column_header.y + column_header.height, band)
        for r in 1:3
            header = box(io, part("row_headers", r))
            @test any(b -> covers_x(b, header) && covers_y(b, header), band)
        end
    end

    @testset "$(form): the keys move along the headers and select in each direction" begin
        table = make(WidgetCheckbox("x"), WidgetText("abc"))
        io = print_document(rec, nothing, table, context())
        getfield(table, :selection)[] = part("column_headers", 2)
        @test path_of(key(io, :left)) == part("column_headers", 1)
        @test path_of(key(io, :right)) == part("column_headers", 3)
        @test path_of(key(io, :down)) == cell(1, 2)
        @test path_of(key(io, :space; ctrl = true)) == part("columns", 2)
        @test path_of(key(io, :space; shift = true)) == whole("column_headers")
        getfield(table, :selection)[] = part("row_headers", 2)
        @test path_of(key(io, :up)) == part("row_headers", 1)
        @test path_of(key(io, :down)) == part("row_headers", 3)
        @test path_of(key(io, :right)) == cell(2, 1)
        @test path_of(key(io, :space; shift = true)) == part("rows", 2)
        @test path_of(key(io, :space; ctrl = true)) == whole("row_headers")
        # From a cell, as before: Shift+Space its row and Ctrl+Space its column.
        getfield(table, :selection)[] = cell(2, 3)
        @test path_of(key(io, :space; shift = true)) == part("rows", 2)
        @test path_of(key(io, :space; ctrl = true)) == part("columns", 3)
    end
end

end
end
