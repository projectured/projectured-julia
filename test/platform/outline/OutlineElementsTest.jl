# The elements of a record: documents of any domain in a list field named
# `elements`, which the kit adds, moves and removes, and draws in a light inset.

using ProjecturedKernel.DocumentModule: @document

"""
A record of the tests that holds elements.
"""
@document struct OutlineElementsHolder
    name::String = ""
    elements::CellVector = CellVector()
end

function test_elements()
@testset "elements" begin
    texts(holder) = [element.value for element in holder.elements]
    make_holder() = OutlineElementsHolder(name = "X1",
                                          elements = Any[PrimitiveString("a"), PrimitiveString("b"), PrimitiveString("c")])

    @testset "add, move and remove an element, and undo each" begin
        holder = make_holder()
        added = PrimitiveString("d")
        for (operation, expected) in ((make_add_element_operation(holder, added), ["a", "b", "c", "d"]),
                                      (make_add_element_operation(holder, PrimitiveString("z"); index = 1), ["z", "a", "b", "c"]),
                                      (make_move_element_operation(holder, 1, 2), ["b", "a", "c"]),
                                      (make_move_element_operation(holder, 3, 2), ["a", "c", "b"]),
                                      (make_remove_element_operation(holder, 2), ["a", "c"]))
            # A move is two edits, so its way back is taken as each one runs.
            inverse = evaluate_invertible_operation!((; document = holder), operation)
            @test texts(holder) == expected
            evaluate_operation(nothing, inverse)
            @test texts(holder) == ["a", "b", "c"]
        end
        # An added document is the document itself, so a note stands at two places.
        evaluate_operation(nothing, make_add_element_operation(holder, added))
        @test holder.elements[4] === added
    end

    @testset "the menu of an element moves it where it can move, and removes it" begin
        holder = make_holder()
        labels(menu) = [(string(item.action.label), item.enabled) for item in menu.elements if item isa WidgetMenuItem]
        @test labels(make_element_menu(holder, 1)) == [("Move up", false), ("Move down", true), ("Remove", true)]
        @test labels(make_element_menu(holder, 3)) == [("Move up", true), ("Move down", false), ("Remove", true)]
        opened = labels(make_element_menu(holder, 2; open = DoNothingOperation()))
        @test opened[1] == ("Open in a tab", true)
    end

    @testset "the kinds list adds a new element of a kind that stands as an element" begin
        holder = make_holder()
        list = make_element_choice_list(holder)
        @test list isa WidgetChoiceList
        @test all(choice -> is_element_type(choice.value), list.find(""))
    end

    @testset "an element draws in a light inset, and the element is at the steps of the kit" begin
        outline = get_theme_defaults(OutlineTheme)
        element = PrimitiveString("a")
        block = make_outline_element(outline; content = element)
        reached = evaluate_reference(block, extend_reference(EmptyReference(), get_outline_element_steps()...))
        @test reached === element
    end
end
end
