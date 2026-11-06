# A menu that a button opens under itself, and that the keys of a list drive.

# The choices of a long list, each made when it is read, with the count of the
# reads, so a test sees how many rows a list builds.
struct _MenuKeysCountedChoices <: AbstractVector{WidgetChoice}
    count::Int
    reads::Base.RefValue{Int}
end
Base.size(choices::_MenuKeysCountedChoices) = (choices.count,)
Base.getindex(choices::_MenuKeysCountedChoices, index::Int) =
    (choices.reads[] += 1; WidgetChoice("row $index"))

# Each rectangle that `canvas` draws, at any depth.
function _menu_keys_rects(canvas, found = Any[])
    for element in canvas.elements
        element isa GraphicsRect && push!(found, element)
        element isa GraphicsCanvas && _menu_keys_rects(element, found)
    end
    found
end

# Each text that `canvas` draws, at any depth, with its left edge in the frame of
# `canvas`.
function _menu_keys_texts(canvas, ox = 0, found = Tuple{String,Int}[])
    x = ox + Int(canvas.x)
    for element in canvas.elements
        element isa GraphicsText && push!(found, (String(element.text), x + Int(element.x)))
        element isa GraphicsCanvas && _menu_keys_texts(element, x, found)
    end
    found
end

function test_widget_menu_keys()
@testset "a menu that the keys drive" begin
    measure = FixedMeasure(8, 12, 4, 0)
    projection = RecursiveProjection(TypeDispatchingProjection(
        WidgetToGraphics(; measure).dispatch))
    key(name) = KeyDown(name, ModifierKeys(); time = 0.0)
    make_menu() = WidgetMenu(Any[WidgetMenuItem("Accept"; operation = DoNothingOperation()),
                                 WidgetMenuItem("Reject"; enabled = false),
                                 WidgetSeparator(),
                                 WidgetMenuItem("Delete"; operation = DoNothingOperation(), keys = Any["Delete"])])

    @testset "Down, Up, Home and End light the enabled items, and Return chooses" begin
        menu = make_menu()
        lit(operation) = operation isa ReplaceViewStateOperation ? operation.operation.value : nothing
        iomap = print_document(projection, nothing, menu, PrinterContext())
        @test lit(read_intent(projection, iomap, key(:down))) == 1
        menu.highlighted = 1
        # The disabled item and the separator are passed over.
        @test lit(read_intent(projection, iomap, key(:down))) == 4
        @test lit(read_intent(projection, iomap, key(:up))) == 1
        @test lit(read_intent(projection, iomap, key(:end))) == 4
        @test lit(read_intent(projection, iomap, key(:home))) == 1
        chosen = read_intent(projection, iomap, key(:return))
        @test chosen isa CompoundOperation
        @test chosen.operations[1] isa EditMenuPartOperation
        @test chosen.operations[1].description == "Accept"
        # A key with a modifier is not a key of the list.
        @test read_intent(projection, iomap, KeyDown(:down, ModifierKeys(ctrl = true); time = 0.0)) === nothing
    end

    @testset "the lit item draws the selection band, and a menu with none draws no band" begin
        band = WidgetModule._make_selected_row_color(nothing)
        unlit = make_menu()
        plain = _menu_keys_rects(print_document(projection, nothing, unlit, PrinterContext()).output)
        lit = make_menu()
        lit.highlighted = 4
        rects = _menu_keys_rects(print_document(projection, nothing, lit, PrinterContext()).output)
        @test length(rects) == length(plain) + 1
        @test count(rect -> rect.color == band, rects) == 1
        @test count(rect -> rect.color == band, plain) == 0
    end

    @testset "an item draws its keys at its right edge" begin
        texts = _menu_keys_texts(print_document(projection, nothing, make_menu(), PrinterContext()).output)
        keys = [text for text in texts if text[1] == "Delete"]
        @test length(keys) == 2
        @test keys[2][2] > keys[1][2] + 8 * length("Delete")
    end

    @testset "a list that a person types into narrows its rows, and Return chooses" begin
        names = ["Chart", "Sequence chart", "Code"]
        list = WidgetChoiceList(; prompt = "Add",
                                find = query -> WidgetChoice[WidgetChoice(name; note = "a kind")
                                                             for name in names
                                                             if occursin(lowercase(query), lowercase(name))],
                                choose = value -> ReplaceReferencedValueOperation(nothing, EmptyReference(), value))
        choice_projection = WidgetChoiceListToWidget()
        iomap = print_document(choice_projection, nothing, list, PrinterContext())
        read(gesture) = read_intent(choice_projection, nothing, Intent(gesture), iomap).operation
        typed = read(KeyPress('c'; time = 0.0))
        @test typed isa ReplaceViewStateOperation
        evaluate_operation(nothing, typed)
        @test list.query == "c"
        evaluate_operation(nothing, read(KeyPress('h'; time = 0.0)))
        @test [choice.label for choice in list.find(list.query)] == ["Chart", "Sequence chart"]
        evaluate_operation(nothing, read(key(:down)))
        @test list.row == 2
        evaluate_operation(nothing, read(key(:backspace)))
        @test list.query == "c" && list.row == 1
        returned = read(KeyPress('\n'; time = 0.0))
        @test returned isa CompoundOperation
        @test returned.operations[1] isa EditMenuPartOperation
        @test returned.operations[1].description == "Chart"
        @test returned.operations[1].operation.value == "Chart"
        # A key with Ctrl goes on to the window under the list.
        @test read(KeyDown(:down, ModifierKeys(ctrl = true); time = 0.0)) === nothing
    end

    @testset "a long list builds only the rows that it shows, and they follow the row" begin
        reads = Ref(0)
        choices = _MenuKeysCountedChoices(10_000, reads)
        list = WidgetChoiceList(; shown_rows = 12, find = query -> choices, choose = value -> nothing)
        shown() = [item.action.label for item in WidgetModule._make_choice_widgets(list)[2].elements]
        # The index of the lit row among the rows that show, and its icon.
        lit() = WidgetModule._make_choice_widgets(list)[2].highlighted
        lit_icon() = WidgetModule._make_choice_widgets(list)[2].elements[lit()].action.icon
        @test shown() == ["row $index" for index in 1:12]
        # The lazy list builds the rows that show, and the link after the last one.
        @test reads[] <= 13
        @test lit() == 1
        # The row that Return chooses keeps the icon of its choice.
        @test lit_icon() === nothing
        choice_projection = WidgetChoiceListToWidget()
        iomap = print_document(choice_projection, nothing, list, PrinterContext())
        read(gesture) = read_intent(choice_projection, nothing, Intent(gesture), iomap).operation
        for _ in 1:12
            evaluate_operation(nothing, read(key(:down)))
        end
        @test (list.row, list.top) == (13, 2)
        @test first(shown()) == "row 2" && last(shown()) == "row 13"
        @test lit() == 12
        evaluate_operation(nothing, read(key(:pagedown)))
        @test (list.row, list.top) == (25, 14)
        evaluate_operation(nothing, read(key(:up)))
        @test (list.row, list.top) == (24, 14)
        @test lit() == 11
        # A turn of the wheel scrolls the rows that show, and keeps the row; a
        # positive turn scrolls up.
        evaluate_operation(nothing, read(MouseScroll(0, 1, 5, 5, ModifierKeys(), 0.0)))
        @test (list.row, list.top) == (24, 11)
        # The row is below the rows that show, so no row lights.
        @test lit() == 0
        evaluate_operation(nothing, read(MouseScroll(0, -10, 5, 5, ModifierKeys(), 0.0)))
        @test list.top == 41
        # The top stops at the last rows of the list.
        list.top = 20_000
        @test last(shown()) == "row 10000"
        # A typed letter narrows the list to its first row, at the top.
        evaluate_operation(nothing, read(KeyPress('r'; time = 0.0)))
        @test (list.row, list.top) == (1, 1)
    end

    @testset "a button opens its menu under itself" begin
        menu = make_menu()
        button = WidgetToolbarItem("More"; icon = :ellipsis,
                                   gestures = GestureBinding[make_menu_button_binding(_ -> menu)])
        iomap = print_document(projection, nothing, button, PrinterContext())
        answer = read_intent(projection, iomap, MouseClick(:left, 2, 2, 1, ModifierKeys(); time = 0.0))
        @test answer isa ReplaceViewStateOperation
        opened = answer.operation
        @test opened isa OpenContextMenuOperation
        @test opened.point === nothing
        @test opened.layers[1][2] === menu
    end
end
end
