# No viewport cuts the ink of a text: the box of every drawn text, as a backend
# draws it (`compute_text_extent`), is inside every viewport around it. The cases
# are the places where a line box sized by the em size of a font cut the
# descenders under it: the cells of a table, the body of a card, a scroll pane
# with no height, and a Markdown result in the chat pane. Every case holds less
# than its room, so nothing in it has to scroll.
function test_text_ink_inside_viewports()
@testset "no viewport cuts the ink of a text" begin

    measure = FontFileMeasure()

    # Every text under `node`, and those whose box leaves the room of a viewport
    # around it, as `(text, top, bottom, room top, room bottom)` in absolute
    # pixels.
    function find_cut_texts(node, x0 = 0, y0 = 0, room = (typemin(Int), typemax(Int)),
                            found = (seen = String[], cut = Any[]))
        if node isa GraphicsCanvas
            for element in node.elements
                find_cut_texts(element, x0 + Int(node.x), y0 + Int(node.y), room, found)
            end
        elseif node isa GraphicsViewport
            top = y0 + Int(node.y)
            find_cut_texts(node.content, x0 + Int(node.x), top,
                           (max(room[1], top), min(room[2], top + Int(node.h))), found)
        elseif node isa GraphicsText
            text = String(node.text)
            isempty(text) && return found
            push!(found.seen, text)
            _, ascent, descent = compute_text_extent(text, node.font)
            top = y0 + Int(node.y)
            (top < room[1] || top + ascent + descent > room[2]) &&
                push!(found.cut, (text, top, top + ascent + descent, room...))
        end
        found
    end

    widgets = RecursiveProjection(TypeDispatchingProjection(vcat(
        LayoutToGraphics().dispatch,
        WidgetToGraphics(font_ubuntu_regular_20; measure = measure).dispatch)))
    print_widget(widget; width = 600) =
        print_document(widgets, nothing, widget,
                       with_exact_size(PrinterContext(); width = Cell(Int32(width)))).output

    @testset "the walk finds a text that a viewport cuts" begin
        # A viewport as high as the em size of Ubuntu 20 cuts its descenders: the
        # box of a text in it is 19 + 4 high.
        text = GraphicsText("gypsy", 0, 0; font = font_ubuntu_regular_20, color = color_black)
        viewport = GraphicsViewport(0, 10, 200, 20, GraphicsCanvas(Any[text]))
        found = find_cut_texts(GraphicsCanvas(Any[viewport]))
        @test found.seen == ["gypsy"]
        @test found.cut == [("gypsy", 10, 10 + 23, 10, 10 + 20)]
    end

    @testset "the cells of a table" begin
        table = WidgetTable(Any["Type", "gap"], Any[Any["yes", "py"], Any["jog", "quay"]])
        found = find_cut_texts(print_widget(table))
        @test issubset(["Type", "gap", "yes", "py", "jog", "quay"], found.seen)
        @test isempty(found.cut)
    end

    @testset "the body of a card" begin
        card = WidgetCard(; title = "A typing guide", content = "The last line has a gypsy.")
        found = find_cut_texts(print_widget(card))
        @test issubset(["A typing guide", "The last line has a gypsy."], found.seen)
        @test isempty(found.cut)
    end

    @testset "a scroll pane with no height" begin
        pane = WidgetScrollPane(WidgetLabel("a gypsy query"); size = Point2D(0, 0))
        found = find_cut_texts(print_widget(pane))
        @test "a gypsy query" in found.seen
        @test isempty(found.cut)
    end

    @testset "a Markdown result in the chat pane" begin
        written = "A first paragraph that ends in gypsy.\n\nA second paragraph, on its typing.\n\n" *
                  "| Type | gap |\n|---|---|\n| yes | py |\n\nThe last line has a guide."
        conversation = ConversationConversation([
            ConversationTurn(:user, [ConversationPart("look it up")]),
            ConversationTurn(:assistant, [ConversationPart(
                EvaluatorForm(TextBlock(TextString("uri: resource://guide/x"));
                              tool_name = "read_resource",
                              input = Dict{String,Any}("uri" => "resource://guide/x"),
                              result = parse_markdown(written), output = written,
                              tool_use_id = "tu_1"))])])
        projection = make_conversation_widget_projection_example(measure = measure)
        context = with_exact_size(PrinterContext(); width = Cell(Int32(900)))
        output = print_document(projection, projection, conversation, context).output
        found = find_cut_texts(output)
        @test issubset(["Type", "gap", "yes", "py", "The last line has a guide."], found.seen)
        @test isempty(found.cut)
    end

end
end
