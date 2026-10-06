# Headers with levels in a table that scrolls its own parts: a header that is a
# `CellVector` holds one label for each level, and the table draws a run of
# equal labels as one header. The test reads where each label landed, which
# rules the table drew, what a press selects, and what a path maps to.

using ProjecturedKernel.CellModule: Cell
using ProjecturedPlatform.CollectionModule: ListNode, make_index_list

function test_widget_table_header_levels()
@testset "headers with levels" begin

det = FixedMeasure(8, 12, 4, 0)
rec = RecursiveProjection(TypeDispatchingProjection(vcat(
    LayoutToGraphics().dispatch,
    WidgetToGraphics(StyleFont("Ubuntu", 20); measure = det).dispatch)))
context() = with_exact_size(PrinterContext(); width = Cell(Int32(700)), height = Cell(Int32(300)))
mods = ModifierKeys()

# Every text a canvas drew, as (x, y, text), through viewports and down a list.
function texts(node, ox = 0, oy = 0, found = Tuple{Int,Int,String}[])
    if node isa GraphicsCanvas
        elements = node.elements
        if elements isa ListNode
            n = elements; seen = 0
            while n !== nothing && seen < 50
                texts(n.value, ox + Int(node.x), oy + Int(node.y), found); n = n.next; seen += 1
            end
        else
            for element in elements
                texts(element, ox + Int(node.x), oy + Int(node.y), found)
            end
        end
    elseif node isa GraphicsViewport
        texts(node.content, ox + Int(node.x), oy + Int(node.y), found)
    elseif node isa GraphicsText
        isempty(string(node.text)) || push!(found, (ox + Int(node.x), oy + Int(node.y), string(node.text)))
    end
    found
end
labels_of(io) = [t[3] for t in texts(io.output)]
place_of(io, label) = only(t for t in texts(io.output) if t[3] == label)
press(io, x, y; modifiers = mods) = begin
    change = read_intent(rec, nothing, Intent(MouseClick(:left, x, y, modifiers; time = 0.0), nothing), io)
    change isa Intent ? change.operation : change
end
level_path(field, index, l) = ConcreteReference(FieldReferenceStep(field),
    ConcreteReference(RangeReferenceStep(index - 1, index),
        ConcreteReference(RangeReferenceStep(l - 1, l), EmptyReference())))
element_path(field, index) = ConcreteReference(FieldReferenceStep(field),
    ConcreteReference(RangeReferenceStep(index - 1, index), EmptyReference()))

regions = ["EU", "EU", "US", "US"]
countries = ["DE", "FR", "CA", "NY"]
keys = [("2024", "Q1"), ("2024", "Q2"), ("2025", "Q1"), ("2025", "Q2")]
function make_table(; corner = CellVector(Any["region", "country"]), column_headers = nothing,
                    policy = Fixed(48), row_regions = regions)
    WidgetTable(; column_headers = something(column_headers, Any[CellVector(Any[a, b]) for (a, b) in keys]),
                row_headers = make_index_list(4, 1, k -> CellVector(Any[row_regions[k], countries[k]])),
                corner, cells = make_index_list(4, 1, k -> make_widget_table_row(Any[string(10k + c) for c in 1:4])),
                columns = Any[WidgetTableColumn(; policy) for _ in 1:4], row_policy = Fixed(20))
end
table = make_table()
io = print_document(rec, nothing, table, context())

# ── Each run is one label ────────────────────────────────────────────────────

drawn = labels_of(io)
@test count(==("2024"), drawn) == 1
@test count(==("2025"), drawn) == 1
@test count(==("Q1"), drawn) == 2
@test count(==("Q2"), drawn) == 2
@test count(==("EU"), drawn) == 1
@test count(==("US"), drawn) == 1
@test all(country -> count(==(country), drawn) == 1, countries)
@test count(==("region"), drawn) == 1 && count(==("country"), drawn) == 1

# The outer level is above the inner level, and a run starts at its first column.
year_2024 = place_of(io, "2024")
year_2025 = place_of(io, "2025")
quarters = sort([t for t in texts(io.output) if t[3] in ("Q1", "Q2")])
@test year_2024[2] < quarters[1][2]
@test year_2024[1] == quarters[1][1]
@test year_2025[1] == quarters[3][1]
# The header column: a level for each dimension, beside each other.
@test place_of(io, "EU")[2] == place_of(io, "DE")[2]
@test place_of(io, "EU")[1] < place_of(io, "DE")[1]
@test place_of(io, "US")[2] == place_of(io, "CA")[2]
@test place_of(io, "region")[1] == place_of(io, "EU")[1]
@test place_of(io, "country")[1] == place_of(io, "DE")[1]

# ── The rules ────────────────────────────────────────────────────────────────

st = io.state
header_graphics = only(e for e in io.output.elements[end - 1].elements if e isa GraphicsViewport).content.elements
edges = st.edges[]
grid = st.column_header_pane.content_iomap
rule_at(x) = [r for r in header_graphics if r isa GraphicsRect && Int(r.x) == x && Int(r.w) == st.bw]
# The rule between two columns of one year starts under the year; between two
# years it runs down from the top.
@test any(r -> Int(r.y) == Int(grid.row_y[2][]), rule_at(edges[2]))
@test any(r -> Int(r.y) == 0, rule_at(edges[3]))
@test !any(r -> Int(r.y) == 0, rule_at(edges[2]))

# ── A press ──────────────────────────────────────────────────────────────────

# An Alt+press on the label of an outer level selects the label of its run. A
# plain press goes to the label, which declines it, and selects the column or the
# row under the pointer.
alt = ModifierKeys(alt = true)
op = press(io, year_2025[1] + 2, year_2025[2] + 2; modifiers = alt)
@test op isa ReplaceSelectionOperation && op.path == level_path("column_headers", 3, 1)
op = press(io, year_2025[1] + 2, year_2025[2] + 2)
@test op isa ReplaceSelectionOperation && op.path == element_path("columns", 3)
op = press(io, quarters[3][1] + 2, quarters[3][2] + 2)
@test op isa ReplaceSelectionOperation && op.path == element_path("columns", 3)
us = place_of(io, "US")
op = press(io, us[1] + 2, us[2] + 2; modifiers = alt)
@test op isa ReplaceSelectionOperation && op.path == level_path("row_headers", 3, 1)
op = press(io, us[1] + 2, us[2] + 2)
@test op isa ReplaceSelectionOperation && op.path == element_path("rows", 3)
# The empty cell of the outer level of the last row is in the run of US.
ny = place_of(io, "NY")
op = press(io, us[1] + 2, ny[2] + 2; modifiers = alt)
@test op isa ReplaceSelectionOperation && op.path == level_path("row_headers", 3, 1)
op = press(io, us[1] + 2, ny[2] + 2)
@test op isa ReplaceSelectionOperation && op.path == element_path("rows", 4)
op = press(io, ny[1] + 2, ny[2] + 2)
@test op isa ReplaceSelectionOperation && op.path == element_path("rows", 4)

# ── The band of a selected run ──────────────────────────────────────────────

getfield(table, :selection)[] = level_path("column_headers", 3, 1)
band = [r for r in header_graphics if r isa GraphicsRect && Int(r.x) == edges[3] && Int(r.w) == edges[5] - edges[3]]
@test length(band) == 1
@test Int(only(band).y) > 0

# ── A path maps forward to the run ──────────────────────────────────────────

box = find_reference_box(io.output, map_reference_forward(io.projection, io, level_path("column_headers", 4, 1)))
@test box !== nothing && box.x <= year_2025[1] && box.x + box.width >= year_2025[1] + 8 * 4
box = find_reference_box(io.output, map_reference_forward(io.projection, io, level_path("row_headers", 3, 1)))
@test box !== nothing && box.x <= us[1] && box.y <= us[2] && box.y + box.height >= us[2]
box = find_reference_box(io.output, map_reference_forward(io.projection, io, element_path("column_headers", 2)))
@test box !== nothing && box.x <= quarters[2][1] && box.x + box.width >= quarters[2][1] + 8 * 2

# ── A run is at least as wide as its label ──────────────────────────────────

# A column with a weight is at least as wide as its headers, and a run of
# columns at least as wide as the label of the run. A `Fixed` column keeps its
# width and cuts a long label, as it cuts a long header with no levels.
long = "a label wider than two columns"
wide = make_table(; column_headers = Any[CellVector(Any[long, "Q1"]), CellVector(Any[long, "Q2"]),
                                          CellVector(Any["2025", "Q1"]), CellVector(Any["2025", "Q2"])],
                  policy = SizePolicy(nothing, nothing, nothing, 1.0))
wide_io = print_document(rec, nothing, wide, context())
wide_edges = wide_io.state.edges[]
@test wide_edges[3] - wide_edges[1] >= 8 * length(long)

# ── A plain press goes to the label of a level ──────────────────────────────

# A label of an outer level that takes a press gets it, in a run of more than one
# column too, and an Alt+press on it selects the run.
year_check, region_check = WidgetCheckbox("x"), WidgetCheckbox("x")
checked = make_table(; column_headers = Any[CellVector(Any["2024", "Q1"]), CellVector(Any["2024", "Q2"]),
                                             CellVector(Any[year_check, "Q1"]), CellVector(Any[year_check, "Q2"])],
                     row_regions = Any["EU", "EU", region_check, region_check])
checked_io = print_document(rec, nothing, checked, context())
for (path, check) in ((level_path("column_headers", 3, 1), year_check), (level_path("row_headers", 3, 1), region_check))
    b = find_reference_box(checked_io.output, map_reference_forward(checked_io.projection, checked_io, path))
    @test b !== nothing
    toggle = press(checked_io, b.x + 4, b.y + 4)
    @test toggle isa ReplaceReferencedValueOperation && toggle.document === check
    selected = press(checked_io, b.x + 4, b.y + 4; modifiers = ModifierKeys(alt = true))
    @test selected isa ReplaceSelectionOperation && selected.path == path
end

# ── Every header has the same count of levels ──────────────────────────────

mixed = make_table(; column_headers = Any[CellVector(Any["2024", "Q1"]), "Q2", CellVector(Any["2025", "Q1"]),
                                           CellVector(Any["2025", "Q2"])])
@test_throws ErrorException print_document(rec, nothing, mixed, context())

end
end
