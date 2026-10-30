# A card that stands in an exact height, and has a title document and nothing else
# above or below its body, offers the body what is left of that height. A card in
# a free height, and a card whose title is a text, keep their body free on that axis.

function test_widget_card_slot()
    @testset "a card in an exact height fills its body" begin
        natural = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))
        # The body is a line over a part that takes the rest of the height it is offered.
        make_body() = VerticalLayout(Any[WidgetLabel("top"), LayoutConstraint(WidgetLabel("rest"); height = Fill)])
        offer(height) = with_exact_size(PrinterContext(); width = Cell(Int32(400)),
                                        height = height === nothing ? nothing : Cell(Int32(height)))
        # The height of the body of a card that was printed: the second child of the card.
        function body_height(iomap)
            while !hasfield(typeof(iomap), :child_iomaps)
                iomap = iomap.inner_iomap
            end
            Int(getfield(iomap, :child_iomaps)[][end][3].output.h[])
        end

        titled = WidgetCard(; title = WidgetLabel("Result"), content = make_body())
        slot = print_document(natural, nothing, titled, offer(300))
        @test 200 <= body_height(slot) <= 300
        @test Int(slot.output.h[]) == 300

        free = print_document(natural, nothing, WidgetCard(; title = WidgetLabel("Result"), content = make_body()),
                              offer(nothing))
        @test body_height(free) < 60

        texted = print_document(natural, nothing, WidgetCard(; title = "Result", content = make_body()), offer(300))
        @test body_height(texted) < 60

        footed = print_document(natural, nothing,
                                WidgetCard(; title = WidgetLabel("Result"), content = make_body(), footer = "end"),
                                offer(300))
        @test body_height(footed) < 60
    end
end
