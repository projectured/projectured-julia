"""
What the assistant of a window reaches of a pivot through `execute_julia_code`,
with the tool set that the application declares: the pivot names, which a search
finds and the system text names, the display and one value, and the edits of the
verbs, each one step of undo.
"""

function test_pivot_assistant_api()
@testset "the assistant reads and changes a pivot" begin

editor = _pz_application()
run_code(code) = execute_julia_code!(editor.tools, editor, code)
count_undo_steps() = length(split(string(describe_undo_history(; editor)), '\n'))

# ── The names ───────────────────────────────────────────────────────────────

declared = Set{Symbol}(name for entry in editor.tools.api for name in get_api_entry_names(entry))
@test issubset([:make_pivot_table, :PivotMeasure, :PivotBarChartView, :find_pivot_value, :move_pivot_field!], declared)
found = run_code("search_api(\"pivot\")")
@test occursin("find_pivot_value", found) && occursin("move_pivot_field!", found)
@test occursin("make_pivot_table", run_code("search_api(\"make pivot table\")"))
@test occursin("move_pivot_field!(pivot_1, \"country\", :columns)", describe_registered_assistant_api())

# ── The display and one value ───────────────────────────────────────────────

shown = run_code("pivot_1 = get_edited_document(find_pane(\"Sales\")); pivot_1")
@test occursin("Columns: year. Rows: region, country.", shown)
@test occursin("\nEU      DE         60    80\n", shown)
@test strip(run_code("find_pivot_value(pivot_1, (\"US\", \"NY\"), 2025)")) == "200.0"

# ── The edits ───────────────────────────────────────────────────────────────

before = count_undo_steps()
run_code("move_pivot_field!(pivot_1, \"country\", :columns)")
run_code("insert_elements!(pivot_1.measures, 2, [PivotMeasure(\"\", :count)])")
run_code("replace_referenced_value!(pivot_1.measures[1], :aggregate, :mean)")
run_code("replace_referenced_value!(pivot_1, :totals, true)")
run_frame!(editor)
pivot = get_document(get_edited_document(find_pane("Sales"; editor)))
@test _pz_columns(pivot.column_dimensions) == ["year", "country"]
@test [(measure.column, measure.aggregate) for measure in pivot.measures] == [("amount", :mean), ("", :count)]
@test pivot.totals
@test count_undo_steps() == before + 4

end
end
