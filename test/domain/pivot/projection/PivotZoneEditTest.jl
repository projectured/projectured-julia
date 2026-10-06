"""
The edits of the zones of a pivot: the operations of the keys and of a drop and
their inverses, and the press, the keys and the drags of the badges of the bar
through the loop of a real editor.
"""

_pz_measure() = FixedMeasure(10, 18, 6, 0)
_pz_columns(zone) = String[item.column for item in zone]

# An editor that shows `pivot` in the window `W`.
function _pz_editor(pivot)
    scene = make_window_scene(pivot, "W"; width = 900, height = 500)
    opened = make_opened_window_projections(; measure = _pz_measure())
    composed = make_window_scene_projection(make_pivot_projection_example(measure = _pz_measure());
                                            opened_window_projections = opened)
    document, projection = make_tracking_screen(scene, composed)
    backend = HeadlessBackend()
    editor = Editor(document, projection; backend = backend, devices = Device[Keyboard(), Mouse()])
    run_frame!(editor)
    (editor, backend)
end

_pz_send!(editor, backend, event) = (push_event!(backend, WindowInput(:W, event)); run_frame!(editor))
const _PZ_NONE = ModifierKeys()
_pz_force(value) = value isa Cell ? _pz_force(value[]) : value

# Where each text is drawn in the window `W`.
function _pz_texts(editor)
    root = _pz_force(_pz_force(_pz_force(get_iomap_output(editor.iomap)).windows)[1].content)
    _pivot_texts(root)
end
_pz_place(editor, text; nth = 1) = (found = [t for t in _pz_texts(editor) if t[3] == text]; found[nth])

# A move of the pointer onto `text`, and a press there.
function _pz_press!(editor, backend, text; nth = 1, time = 1.0)
    x, y = _pz_place(editor, text; nth)
    _pz_send!(editor, backend, MouseMove(x + 3, y + 3, MouseButtons(), _PZ_NONE; time))
    _pz_send!(editor, backend, MouseDown(:left, x + 3, y + 3, _PZ_NONE; time = time + 0.01))
    (x + 3, y + 3)
end

# A drag from `text` to the point `(x, y)`, through two held moves.
function _pz_drag!(editor, backend, text, x, y; nth = 1, release = true)
    sx, sy = _pz_press!(editor, backend, text; nth, time = 2.0)
    _pz_send!(editor, backend, MouseMove(sx + 20, sy, MouseButtons(:left), _PZ_NONE; time = 2.1))
    _pz_send!(editor, backend, MouseMove(x, y, MouseButtons(:left), _PZ_NONE; time = 2.2))
    _pz_send!(editor, backend, MouseMove(x + 1, y, MouseButtons(:left), _PZ_NONE; time = 2.3))
    release && _pz_send!(editor, backend, MouseUp(:left, x + 1, y, _PZ_NONE; time = 2.4))
    nothing
end

_pz_key!(editor, backend, key; alt = false) =
    _pz_send!(editor, backend, KeyDown(key, ModifierKeys(alt = alt); time = 3.0))

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

end
end
