"""
The edits of the zones of a pivot: the operations of the keys and of a drop and
their inverses, the press, the keys and the drags of the badges of the bar
through the loop of a real editor, and the verbs of the assistant in an
application window.
"""

_pz_measure() = FixedMeasure(10, 18, 6, 0)
_pz_columns(zone) = String[item.column for item in zone]

# An editor that shows `pivot` in the window `W`, with the window of a context
# menu when `context_menu` is set.
function _pz_editor(pivot; context_menu::Bool = false)
    scene = make_window_scene(pivot, "W"; width = 900, height = 500)
    opened = make_opened_window_projections(; measure = _pz_measure())
    composed = make_window_scene_projection(make_pivot_projection_example(measure = _pz_measure());
                                            opened_window_projections = opened)
    document, projection = make_tracking_screen(scene, composed;
        inner_wrappers = context_menu ? [wrap_context_menu_window] : [])
    backend = HeadlessBackend()
    editor = Editor(document, projection; backend = backend, devices = Device[Keyboard(), Mouse()])
    run_frame!(editor)
    (editor, backend)
end

_pz_send!(editor, backend, event; window = :W) =
    (push_event!(backend, WindowInput(window, event)); run_frame!(editor))
const _PZ_NONE = ModifierKeys()
_pz_force(value) = value isa Cell ? _pz_force(value[]) : value

# Where each text is drawn in the window `W`.
function _pz_texts(editor)
    root = _pz_force(_pz_force(_pz_force(get_iomap_output(editor.iomap)).windows)[1].content)
    _pivot_texts(root)
end
_pz_place(editor, text; nth = 1) = (found = [t for t in _pz_texts(editor) if t[3] == text]; found[nth])

# Where each text is drawn in the window `id`, or nothing when no window has it.
function _pz_window_texts(editor, id::Symbol)
    windows = _pz_force(_pz_force(get_iomap_output(editor.iomap)).windows)
    index = findfirst(window -> window.id === id, collect(windows))
    index === nothing ? nothing : _pivot_texts(_pz_force(windows[index].content))
end

# A move of the pointer onto `text`, and a press there.
function _pz_press!(editor, backend, text; nth = 1, time = 1.0, window = :W)
    x, y = _pz_place(editor, text; nth)
    _pz_send!(editor, backend, MouseMove(x + 3, y + 3, MouseButtons(), _PZ_NONE; time); window)
    _pz_send!(editor, backend, MouseDown(:left, x + 3, y + 3, _PZ_NONE; time = time + 0.01); window)
    (x + 3, y + 3)
end

# A drag from `text` to the point `(x, y)`, through two held moves.
function _pz_drag!(editor, backend, text, x, y; nth = 1, release = true, window = :W)
    sx, sy = _pz_press!(editor, backend, text; nth, time = 2.0, window)
    _pz_send!(editor, backend, MouseMove(sx + 20, sy, MouseButtons(:left), _PZ_NONE; time = 2.1); window)
    _pz_send!(editor, backend, MouseMove(x, y, MouseButtons(:left), _PZ_NONE; time = 2.2); window)
    _pz_send!(editor, backend, MouseMove(x + 1, y, MouseButtons(:left), _PZ_NONE; time = 2.3); window)
    release && _pz_send!(editor, backend, MouseUp(:left, x + 1, y, _PZ_NONE; time = 2.4); window)
    nothing
end

_pz_key!(editor, backend, key; alt = false, window = :W) =
    _pz_send!(editor, backend, KeyDown(key, ModifierKeys(alt = alt); time = 3.0); window)

# An application window with the pivot of the example in the tab "Sales", as the
# assistant of the window meets it.
function _pz_application()
    document, projection = make_application_window(String[]; root = mktempdir(), assistant = nothing)
    editor = build_editor(document, projection; backend = HeadlessBackend(), tabs = false,
                          window = (; title = "ProjecturEd", width = 1280, height = 720,
                                    opened_window_projections = make_opened_window_projections(;
                                        content = make_application_content_projections())))
    start_application!(editor)
    run_frame!(editor)
    open_pane!(make_pivot_document_example(); title = "Sales", editor)
    run_frame!(editor)
    editor
end

_pz_undo!(editor) = (call_tool(editor.tools, "undo"; args = Dict{String,Any}(), target = editor); run_frame!(editor))

function test_pivot_zone_edits()
@testset "the edits of the zones of a pivot" begin

# ── The operations and their inverses ───────────────────────────────────────

pivot = make_pivot_document_example()
move = PivotModule._make_pivot_item_move(pivot, "row_dimensions", 1, "column_dimensions", 2)
evaluate_operation(nothing, move.operations[1])
@test _pz_columns(pivot.column_dimensions) == ["year", "region"]
@test _pz_columns(pivot.row_dimensions) == ["country"]
@test strip_reference_types(move.operations[2].path) ==
      PivotModule._make_pivot_zone_item_path("column_dimensions", 2)
# The move keeps the cell of the dimension, and its inverse puts it back.
evaluate_operation(nothing, make_inverse_operation(pivot, move.operations[1]))
@test _pz_columns(pivot.column_dimensions) == ["year"]
@test _pz_columns(pivot.row_dimensions) == ["region", "country"]
# A move onto its own place is no edit.
@test PivotModule._make_pivot_item_move(pivot, "row_dimensions", 1, "row_dimensions", 1) === nothing
@test PivotModule._make_pivot_item_move(pivot, "row_dimensions", 1, "row_dimensions", 2) === nothing
# A measure of a dimension: the sum of a number, the count of a text.
insert = PivotModule._make_pivot_measure_insert(pivot, pivot.unused_dimensions[1], 1)
evaluate_operation(nothing, insert.operations[1])
@test [(m.column, m.aggregate) for m in pivot.measures] == [("quarter", :count), ("amount", :sum)]
@test _pz_columns(pivot.unused_dimensions) == ["quarter", "product", "amount"]
evaluate_operation(nothing, make_inverse_operation(pivot, insert.operations[1]))
@test [(m.column, m.aggregate) for m in pivot.measures] == [("amount", :sum)]
removal = PivotModule._make_pivot_measure_removal(pivot, 1)
evaluate_operation(nothing, removal.operations[1])
@test isempty(pivot.measures)
@test strip_reference_types(removal.operations[2].path) == PivotModule._make_pivot_zone_path("measures")
# A drop of a measure outside the measures takes it out of the pivot.
pivot = make_pivot_document_example()
drop = PivotModule._make_pivot_drop_operation(pivot, ("measures", 1), ("unused_dimensions", 1))
evaluate_operation(nothing, drop.operations[1])
@test isempty(pivot.measures)

# ── A press selects, and the keys move the selected item ───────────────────

pivot = make_pivot_document_example()
editor, backend = _pz_editor(pivot)
_pz_press!(editor, backend, "year")
_pz_send!(editor, backend, MouseUp(:left, 0, 0, _PZ_NONE; time = 1.1))
@test strip_reference_types(pivot.selection) == PivotModule._make_pivot_zone_item_path("column_dimensions", 1)
_pz_key!(editor, backend, :down; alt = true)
@test isempty(pivot.column_dimensions)
@test _pz_columns(pivot.row_dimensions) == ["year", "region", "country"]
@test strip_reference_types(pivot.selection) == PivotModule._make_pivot_zone_item_path("row_dimensions", 1)
_pz_key!(editor, backend, :right; alt = true)
@test _pz_columns(pivot.row_dimensions) == ["region", "year", "country"]
_pz_key!(editor, backend, :up; alt = true)
@test _pz_columns(pivot.column_dimensions) == ["year"]
_pz_key!(editor, backend, :delete)
@test _pz_columns(pivot.unused_dimensions) == ["quarter", "product", "amount", "year"]
@test isempty(pivot.column_dimensions)
# The table follows: one column with the name of the measure.
@test get_pivot_column_count(pivot.cross_table) == 1

# ── A drag moves a dimension, and the bar shows where the drop puts it ─────

pivot = make_pivot_document_example()
editor, backend = _pz_editor(pivot)
x, y = _pz_place(editor, "year")
_pz_drag!(editor, backend, "region", x + 3, y + 3; release = false)
@test pivot.drag !== nothing && pivot.drag.started
@test pivot.drag.target == ("column_dimensions", 1)
@test count(t -> t[3] == "region", _pz_texts(editor)) == 3   # the badge, the badge of the drop, the corner
_pz_send!(editor, backend, MouseUp(:left, x + 4, y + 3, _PZ_NONE; time = 2.5))
@test pivot.drag === nothing
@test _pz_columns(pivot.column_dimensions) == ["region", "year"]
@test _pz_columns(pivot.row_dimensions) == ["country"]

# A drag of a field onto the name of the values gives a new measure at the end,
# and the field stays.
x, y = _pz_place(editor, "Values")
_pz_drag!(editor, backend, "quarter", x + 3, y + 3)
@test [(m.column, m.aggregate) for m in pivot.measures] == [("amount", :sum), ("quarter", :count)]
@test "quarter" in _pz_columns(pivot.unused_dimensions)

# A drag of a measure out of the values takes it out of the pivot.
x, y = _pz_place(editor, "Fields")
_pz_drag!(editor, backend, "count(quarter)" in [t[3] for t in _pz_texts(editor)] ? "count(quarter)" : "count",
          x + 3, y + 3)
@test [(m.column, m.aggregate) for m in pivot.measures] == [("amount", :sum)]

# In a tab of an application window, a drop and a key move the field too: the
# move goes up through every view between the pivot and the window.
editor = _pz_application()
document = get_document(get_edited_document(find_pane("Sales"; editor)))
window = _pz_force(_pz_force(get_iomap_output(editor.iomap)).windows)[1].id
x, y = _pz_place(editor, "Rows")
_pz_drag!(editor, editor.backend, "year", x + 3, y + 3; window)
@test document.drag === nothing
@test isempty(document.column_dimensions)
@test _pz_columns(document.row_dimensions) == ["region", "country", "year"]
@test count(t -> t[3] == "year", _pz_texts(editor)) == 2   # the badge and the corner
_pz_key!(editor, editor.backend, :up; alt = true, window)
@test _pz_columns(document.column_dimensions) == ["year"]
@test _pz_columns(document.row_dimensions) == ["region", "country"]
# Ctrl+Z takes back the key and then the drop, and the selection goes back with
# each to the field where it was; Ctrl+Y puts the drop back.
zone_item(field, index) = PivotModule._make_pivot_zone_item_path(field, index)
_pz_send!(editor, editor.backend, KeyDown(:z, ModifierKeys(ctrl = true); time = 3.1); window)
@test _pz_columns(document.row_dimensions) == ["region", "country", "year"]
@test strip_reference_types(document.selection) == zone_item("row_dimensions", 3)
_pz_send!(editor, editor.backend, KeyDown(:z, ModifierKeys(ctrl = true); time = 3.2); window)
@test _pz_columns(document.column_dimensions) == ["year"]
@test _pz_columns(document.row_dimensions) == ["region", "country"]
@test strip_reference_types(document.selection) == zone_item("column_dimensions", 1)
_pz_send!(editor, editor.backend, KeyDown(:y, ModifierKeys(ctrl = true); time = 3.3); window)
@test _pz_columns(document.row_dimensions) == ["region", "country", "year"]
@test strip_reference_types(document.selection) == zone_item("row_dimensions", 3)

# ── The menu of a right click ────────────────────────────────────────────────

# A right click on a measure opens the menu of the measure, its aggregates. F2
# adds the menu of the pivot after it, and a choice of an aggregate writes it.
pivot = make_pivot_document_example()
editor, backend = _pz_editor(pivot; context_menu = true)
x, y = _pz_place(editor, "sum(amount)")
_pz_send!(editor, backend, MouseMove(x + 3, y + 3, MouseButtons(), _PZ_NONE; time = 4.0))
_pz_send!(editor, backend, MouseDown(:right, x + 3, y + 3, _PZ_NONE; time = 4.1))
_pz_send!(editor, backend, MouseUp(:right, x + 3, y + 3, _PZ_NONE; time = 4.15))
menu = _pz_window_texts(editor, :widget_popup)
@test menu !== nothing
@test "mean(amount)" in [t[3] for t in menu]
@test !("Show the totals" in [t[3] for t in menu])
_pz_send!(editor, backend, KeyDown(:f2, _PZ_NONE; time = 4.3))
menu = _pz_window_texts(editor, :widget_popup)
@test "mean(amount)" in [t[3] for t in menu] && "Show the totals" in [t[3] for t in menu]
x, y = first((t[1], t[2]) for t in menu if t[3] == "mean(amount)")
_pz_send!(editor, backend, MouseDown(:left, x + 3, y + 3, _PZ_NONE; time = 4.5); window = :widget_popup)
_pz_send!(editor, backend, MouseUp(:left, x + 3, y + 3, _PZ_NONE; time = 4.55); window = :widget_popup)
@test only(pivot.measures).aggregate === :mean
@test _pz_window_texts(editor, :widget_popup) === nothing

# A right click on a dimension opens the menu of the pivot with the items of the
# dimension first.
x, y = _pz_place(editor, "year")
_pz_send!(editor, backend, MouseMove(x + 3, y + 3, MouseButtons(), _PZ_NONE; time = 5.0))
_pz_send!(editor, backend, MouseDown(:right, x + 3, y + 3, _PZ_NONE; time = 5.1))
_pz_send!(editor, backend, MouseUp(:right, x + 3, y + 3, _PZ_NONE; time = 5.15))
menu = [t[3] for t in something(_pz_window_texts(editor, :widget_popup), [])]
@test "Order by the measure" in menu && "Show the totals" in menu

# ── The verbs of the assistant ──────────────────────────────────────────────

# A field moves as a drag moves it, and each move is one step that undo takes
# back. The selection of the person stays where it is.
editor = _pz_application()
pivot = get_edited_document(find_pane("Sales"; editor))
selected = repr(get_selection(editor.document))
@test move_pivot_field!(pivot, "country", :columns; editor) === pivot
run_frame!(editor)
@test _pz_columns(pivot.row_dimensions) == ["region"]
@test _pz_columns(pivot.column_dimensions) == ["year", "country"]
move_pivot_field!(pivot, "country", :rows; place = 1, editor)
move_pivot_field!(pivot, "region", :rows; place = 1, editor)
run_frame!(editor)
@test _pz_columns(pivot.row_dimensions) == ["region", "country"]
move_pivot_field!(pivot, "year", :fields; editor)
run_frame!(editor)
@test _pz_columns(pivot.unused_dimensions) == ["quarter", "product", "amount", "year"]
@test isempty(pivot.column_dimensions)
@test repr(get_selection(editor.document)) == selected
_pz_undo!(editor)
_pz_undo!(editor)
@test _pz_columns(pivot.row_dimensions) == ["country", "region"]
@test _pz_columns(pivot.column_dimensions) == ["year"]
@test_throws ArgumentError move_pivot_field!(pivot, "price", :rows; editor)
@test_throws ArgumentError move_pivot_field!(pivot, "amount", :values; editor)

# A setting of the pivot, of a field and of a measure is written by its field, as
# the menus write it. The view of the cells holds `nothing` while it is the
# automatic one.
document = get_document(pivot)
@test document.cell_view === nothing
@test replace_referenced_value!(pivot, :cell_view, PivotBarChartView(); editor) === pivot
replace_referenced_value!(pivot, :totals, true; editor)
replace_referenced_value!(pivot.measures[1], :aggregate, :mean; editor)
replace_referenced_value!(pivot.row_dimensions[1], :order, :measure; editor)
run_frame!(editor)
@test document.cell_view isa PivotBarChartView
@test document.totals
@test only(document.measures).aggregate === :mean
@test first(document.row_dimensions).order === :measure
@test repr(get_selection(editor.document)) == selected
foreach(_ -> _pz_undo!(editor), 1:4)
@test document.cell_view === nothing && !document.totals
@test only(document.measures).aggregate === :sum && first(document.row_dimensions).order === :natural
@test_throws ArgumentError replace_referenced_value!(pivot, :colour, true; editor)

end
end
