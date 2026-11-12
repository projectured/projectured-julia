# The kit of an outline: its theme and the rows that show their date.

function test_outline()
@testset "outline" begin
    @testset "the theme holds the sizes and the type of a row" begin
        @test get_outline_style(nothing, :meta_width) == 72
        @test get_outline_style(nothing, :menu_width) == 24
        @test get_outline_style(nothing, :text_line) == 22
        @test get_outline_style(nothing, :field_line) == 20
        title = get_outline_style(nothing, :title_text)
        text = get_outline_style(nothing, :text)
        id = get_outline_style(nothing, :id_text)
        @test title isa StyleText && title.font.size > text.font.size > id.font.size
        @test title.font.weight == 500
        @test id.font.family == "Ubuntu" && id.font.weight == 700
        # A scaled theme gives the same values at the scale of 1, each read from a cell.
        scaled = get_scaled_theme!(Appearance(), OutlineTheme)
        values = unwrap_cell(make_outline_values_field(scaled, get_scaled_theme!(Appearance(), WidgetTheme)))
        @test values.meta_width == 72
        @test values.tree_row_padding isa Inset
        @test (values.item_gap, values.button_gap, values.section_gap) == (4, 8, 8)
    end

    @testset "a row lights under the pointer and shows its controls, and builds nothing" begin
        outline = make_outline_values_field(nothing, nothing)
        measure = FixedMeasure(8, 12, 4, 0)
        projection = RecursiveProjection(TypeDispatchingProjection(
            WidgetToGraphics(; measure).dispatch))
        menu = make_outline_control(outline, :ellipsis, "The menu of Q1", () -> nothing)
        row = make_outline_row(outline; facts = make_outline_facts(outline, [Any[make_outline_label(outline, "Q1", :id_text)]]),
                               body = make_outline_label(outline, "Which capacity?", :text), menu,
                               revealed = Any[menu], title = "Q1",
                               compute_menu = () -> WidgetMenu(Any[WidgetMenuItem("Fold")]))
        iomap = print_document(projection, nothing, row, PrinterContext())
        band = first(rect for rect in _fit_drawn_elements(GraphicsRect, iomap.output) if Int(rect.w) > 0)
        @test band.color == color_transparent
        @test menu.style.label_text_color == color_transparent
        elements = collect(iomap.output.elements)
        replace_mouse_target!(row, EmptyReference())
        @test band.color != color_transparent
        @test menu.style.label_text_color == outline.mark_color
        # The light draws the band and the control again, and no part of the row.
        @test collect(iomap.output.elements) == elements
        replace_mouse_target!(row, nothing)
        @test band.color == color_transparent
        set_selection!(row, EmptyReference())
        @test band.color != color_transparent
        @test menu.style.label_text_color == outline.mark_color
        # A spacer keeps the place of a fold in a row that does not fold.
        spacer = print_document(projection, nothing, make_outline_spacer(outline), PrinterContext()).output
        @test Int(spacer.w[]) == outline.fold_size
        # A control that shows under the pointer is no stop of Tab.
        @test !is_focusable_document(menu)
        # A right click and Shift+F10 open the menu of the row.
        opened = read_bound_gesture(row, KeyDown(:f10, ModifierKeys(shift = true); time = 0.0))
        @test opened isa ReplaceViewStateOperation && opened.operation isa OpenContextMenuOperation
        @test opened.operation.layers[1][1] == "Q1"
    end

    @testset "a row shows its date where the day changes" begin
        @test compute_shown_dates(String[]) == Bool[]
        @test compute_shown_dates(["2026-10-22", "2026-10-22", "2026-10-23", "2026-10-23"]) ==
              [true, false, true, false]
        # A row with no time shows no date and leaves the day of the rows above it.
        @test compute_shown_dates(["2026-10-22", nothing, "2026-10-22", "2026-10-24"]) ==
              [true, false, false, true]
        @test compute_shown_dates([nothing, "2026-10-22"]) == [false, true]
    end

    @testset "a caret in a text that the view drew in a row is a step of the view at the record" begin
        steps(path) = collect(get_reference_steps(strip_reference_types(path)))
        reference(step_list...) = foldr(ConcreteReference, collect(Any, step_list); init = EmptyReference())
        record = Any[FieldReferenceStep("items"), RangeReferenceStep(0, 1)]
        row = Any[FieldReferenceStep("children"), RangeReferenceStep(2, 3)]
        slots = Any[OutlineSlot(record, row; whole = true)]
        caret = reference(row..., FieldReferenceStep("content"), RangeReferenceStep(1, 1))
        mark = reference(row..., FieldReferenceStep("mark"))
        drawn = (record_path, path) -> ConcreteReference(ProjectionReferenceStep(:view, path), EmptyReference())
        # A caret in a text of the row: the record, then the step that `introduce` gives.
        found = map_outline_backward(slots, caret; introduce = drawn)
        @test steps(found)[1:2] == record
        @test steps(found)[3] == ProjectionReferenceStep(:view, caret)
        @test find_outline_introduced_path(:view, found) == caret
        @test find_outline_introduced_path(:other, found) === nothing
        # A place for which `introduce` answers nothing, and a caret with no
        # `introduce`, is the record.
        @test steps(map_outline_backward(slots, mark; introduce = (_, _) -> nothing)) == record
        @test steps(map_outline_backward(slots, caret)) == record
        # The forward map of the view takes the step back to its place.
        @test map_outline_view_forward(:view, slots, found) == caret
        @test steps(map_outline_view_forward(:view, slots, reference(record...))) == row
    end
end
end
