using ProjecturedPlatform.ArrangementModule: make_value_list_text, is_value_listed

"""
    test_widget_column_header()

The parts of the header of a column of a table: the keys after a click and a
Shift+click on the glyph, the icon and the place label of the glyph, the field
of a filter with its reason, and the counts and the take of the dialog of the
values of a column.
"""
function test_widget_column_header()
@testset "the header of a column" begin
    @testset "the keys after a click and a Shift+click" begin
        click(keys, name; adding = false) = compute_clicked_sort_keys(keys, name, adding)
        # A click sorts by the column alone: off, ascending, descending, off.
        @test click(Tuple{String,Bool}[], "age") == [("age", false)]
        @test click([("age", false)], "age") == [("age", true)]
        @test click([("age", true)], "age") == Tuple{String,Bool}[]
        @test click([("name", false), ("age", true)], "name") == [("name", true)]
        @test click([("name", false)], "age") == [("age", false)]
        # A Shift+click adds the column, turns its key in place, or removes it.
        @test click([("name", false)], "age"; adding = true) == [("name", false), ("age", false)]
        @test click([("name", false), ("age", false)], "name"; adding = true) == [("name", true), ("age", false)]
        @test click([("name", true), ("age", false)], "name"; adding = true) == [("age", false)]
        @test find_sort_state([("name", false), ("age", true)], "age") == (true, 2)
        @test find_sort_state([("name", false)], "age") === nothing
    end

    @testset "the glyph shows the state of the column" begin
        faint = StyleColor(0.5, 0.5, 0.5, 1.0)
        posted = Any[]
        glyph(keys, name) = make_sort_glyph(keys, name, faint, adding -> (push!(posted, adding); adding);
                                            domain = "table")
        parts = glyph(Tuple{String,Bool}[], "age")
        @test length(parts) == 1
        @test parts[1].action.icon == :arrow_up_down
        @test parts[1].style.label_text_color == faint
        @test parts[1].tooltip.title == "Sort by age"
        @test parts[1].tooltip.hint == "Shift+Left click adds it to the order of the rows."
        parts = glyph([("age", false)], "age")
        @test length(parts) == 1 && parts[1].action.icon == :arrow_up && parts[1].style === nothing
        @test glyph([("age", true)], "age")[1].action.icon == :arrow_down
        # The place of the key shows when more than one column sorts.
        parts = glyph([("name", false), ("age", true)], "age")
        @test length(parts) == 2 && parts[2] isa WidgetLabel && parts[2].content == "2"
        # A column that does not sort has no place, whatever the other keys are.
        @test length(glyph([("name", false), ("age", true)], "city")) == 1
        # The click and the Shift+click of the glyph ask for the operation.
        click, shift = parts[1].gestures
        @test click.domain == "table" && shift.domain == "table"
        @test click.operation(nothing, nothing) === false
        @test shift.operation(nothing, nothing) === true
        @test posted == [false, true]
    end

    @testset "the field shows its text and the reason it does not parse" begin
        text = Cell("> 3")
        reason = Cell(nothing)
        range = Cell(nothing)
        red = StyleColor(1.0, 0.0, 0.0, 1.0)
        field = make_filter_field(() -> text[], () -> range[], () -> reason[], 120, red)
        @test field.content == "> 3" && field.width == 120
        @test field.tooltip === nothing && field.style === nothing && field.selection === nothing
        reason[] = "expected a number"
        @test field.tooltip == "expected a number"
        @test field.style.content_color == red
        range[] = (2, 2)
        @test field.selection !== nothing
        reason[] = nothing
        @test field.tooltip === nothing && field.style === nothing
        # The labeled field holds the field as its second child, and maps the caret into it.
        layout = make_labeled_field(WidgetLabel("age"), field, 80)
        @test layout.children[2] === field
        @test layout.selection == make_field_child_reference(field.selection)
        @test make_field_child_reference(nothing) === nothing
    end

    @testset "the dialog of the values counts the values and takes the ticked ones" begin
        column = ["b", "a", "b", "c", missing, "a, b"]
        @test compute_value_counts(column) == ["a" => 1, "a, b" => 1, "b" => 2, "c" => 1]
        @test compute_value_counts(1:5; limit = 4) === nothing
        @test compute_value_counts(1:4; limit = 4) == [i => 1 for i in 1:4]
        written = Any[]
        write(values, ticked) = (text = make_value_list_text(values, ticked); push!(written, text); text)
        dialog, take = make_value_list_dialog("kind", column, _ -> true, write)
        boxes = dialog.content.content.children
        @test [box.label for box in boxes] == ["a  (1)", "a, b  (1)", "b  (2)", "c  (1)"]
        @test all(box -> box.content, boxes)
        # Every value ticked is the empty text, which is no filter.
        @test take() == ""
        getfield(boxes[3], :content)[] = false
        getfield(boxes[4], :content)[] = false
        @test take() == "= a, \"a, b\""
        # The boxes start from the filter text, and no value ticked takes nothing.
        dialog, take = make_value_list_dialog("kind", column, value -> is_value_listed("= b", value), make_value_list_text)
        @test [box.content for box in dialog.content.content.children] == [false, false, true, false]
        foreach(box -> getfield(box, :content)[] = false, dialog.content.content.children)
        @test take() === nothing
        # A column of more than 1,000 distinct values says so and takes nothing.
        dialog, take = make_value_list_dialog("id", collect(1:1001), _ -> true, make_value_list_text)
        @test dialog.content isa AbstractString && occursin("more than 1000", dialog.content)
        @test take() === nothing
    end

    @testset "the styles are in the widget theme" begin
        theme = WidgetTheme()
        style(theme, name) = unwrap_cell(get_widget_style(theme, name))
        @test style(theme, :header_field_minimum_width) == 80
        @test style(theme, :header_gap) == 4
        @test style(nothing, :value_list_size).x[] == 320
        scaled = get_scaled_theme!(Appearance(control_scale = 1.5, spacing_scale = 1.5), WidgetTheme)
        @test style(scaled, :header_field_minimum_width) == 120
        @test style(scaled, :header_gap) == 6
    end
end
end
