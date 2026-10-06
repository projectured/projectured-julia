# ═══════════════════════════════════════════════════════════════════════════
# test/projection/TableCellEditingTest.jl
#
# A cell of a WidgetTable is edited by the readers of its own domain. A click
# puts the caret in the cell, and an arrow, a character and Backspace then edit
# the JSON string or the XML tag name there, as they do outside a table.
# ═══════════════════════════════════════════════════════════════════════════

mutable struct _TableCellMockEditor; document::Any; end

# `_table_measure` is defined in TableSelectionTest.jl, in the same module.

# Every text a table drew, through the viewports of its cells, joined.
function _collect_table_texts(node, found = String[])
    if node isa GraphicsCanvas
        foreach(element -> _collect_table_texts(element, found), node.elements)
    elseif node isa GraphicsViewport
        _collect_table_texts(node.content, found)
    elseif node isa GraphicsText
        push!(found, string(node.text))
    end
    found
end

function test_table_cell_editing()
@testset "TableCellEditing" begin
    mods = ModifierKeys()
    projection = make_table_projection_example(measure = _table_measure())
    xml_table() = WidgetTable(; column_headers = Any[PrimitiveString("tag")], row_headers = Any[],
                              cells = Any[Any[XmlElement("b", [XmlText("hi")])]])
    cases = [
        ("a JSON string", make_table_document_example, t -> t.cells[1][1].value, "Jennifer", "YJennifer"),
        ("an XML tag name", xml_table, t -> t.cells[1][1].tag, "b", "Yb"),
    ]
    for (label, make_table, get_text, original, edited) in cases
        @testset "$label" begin
            table = make_table()
            editor = _TableCellMockEditor(table)
            iomap = print_document(projection, table)
            read_key(event) = read_intent(projection, iomap, event)
            g = iomap.geometry
            # The left edge of the first body cell: the caret is before the
            # opening quote, or before the `<`, and an arrow moves it past.
            click = read_key(MouseClick(:left, g.col_x[1] + g.grid_off_x + 2, g.row_y[2] + g.grid_off_y + 2, mods;
                                        time = 0.0))
            @test click isa ReplaceSelectionOperation
            evaluate_operation(editor, click)
            evaluate_operation(editor, read_key(KeyDown(:right, mods; time = 0.0)))
            typed = read_key(KeyPress('Y', "Y", mods; time = 0.0))
            @test typed isa ReplaceStringRangeOperation
            @test typed.reference.head.name == "cells"
            evaluate_operation(editor, typed)
            @test get_text(table) == edited
            @test occursin(edited, join(_collect_table_texts(iomap.output)))
            evaluate_operation(editor, read_key(KeyDown(:backspace, mods; time = 0.0)))
            @test get_text(table) == original
            @test !occursin(edited, join(_collect_table_texts(iomap.output)))
        end
    end
end
end
