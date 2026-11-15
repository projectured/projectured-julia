# A row on the baseline stands each child so that the baseline of its first line
# of text meets the lowest one of the row, and a child with no text stands on its
# bottom edge.

function test_baseline_alignment()
@testset "a row on the baseline puts the text of its children on one line" begin
    big = StyleFont("Ubuntu", 40)
    # Every font has the ascent 12; the big one has the ascent 24.
    measure = FixedMeasure(10, 12, 4, 0; fonts = Dict(big => FontMetrics(24, 8, 0)))
    projection = make_widget_projection_example(; measure)
    ascent(font) = font == big ? 24 : 12
    function placed(row)
        canvas = get_iomap_output(print_document(projection, nothing, row,
            PrinterContext(EmptyReference(), nothing, nothing, Dict{Symbol,Any}())))
        found = Dict{String,Any}()
        boxes = Tuple{Int,Int,Int,Int}[]
        walk(node, ox, oy) = begin
            node = unwrap_cell(node)
            if node isa GraphicsText
                found[String(unwrap_cell(node.text))] =
                    (y = oy + Int(node.y), font = unwrap_cell(node.font))
            elseif node isa GraphicsCanvas
                x, y = ox + Int(node.x), oy + Int(node.y)
                push!(boxes, (x, y, Int(node.w), Int(node.h)))
                foreach(element -> walk(element, x, y), unwrap_cell(node.elements))
            end
        end
        walk(canvas, 0, 0)
        (texts = found, boxes = boxes, height = Int(canvas.h))
    end
    baseline(text) = text.y + ascent(text.font)

    on_baseline = placed(HorizontalLayout(Any[WidgetLabel("small"), WidgetLabel("big"; text_style = big)];
                                          vertical_align = :baseline))
    @test baseline(on_baseline.texts["small"]) == baseline(on_baseline.texts["big"])
    # On the top, the smaller text stands higher.
    on_top = placed(HorizontalLayout(Any[WidgetLabel("small"), WidgetLabel("big"; text_style = big)];
                                     vertical_align = :top))
    @test baseline(on_top.texts["small"]) < baseline(on_top.texts["big"])

    # A child with no text stands on its bottom edge: the box of the checkbox ends
    # at the baseline of the label beside it.
    box = WidgetCheckbox(true)
    row = placed(HorizontalLayout(Any[box, WidgetLabel("big"; text_style = big)];
                                  vertical_align = :baseline))
    line = baseline(row.texts["big"])
    @test any(b -> b[2] + b[4] == line, row.boxes)
end

@testset "a flow has the baseline of its first child, and a row on the baseline aligns on it" begin
    big = StyleFont("Ubuntu", 40)
    measure = FixedMeasure(10, 12, 4, 0; fonts = Dict(big => FontMetrics(24, 8, 0)))
    projection = make_widget_projection_example(; measure)
    context() = PrinterContext(EmptyReference(), nothing, nothing, Dict{Symbol,Any}())
    print_alone(document) = print_document(projection, nothing, document, context())
    # A flow has the baseline of its first child that has one, so in a row on the baseline
    # the flow stands so that its first text meets the text beside it.
    row = HorizontalLayout(Any[WidgetLabel("small"),
                               FlowLayout(Any[WidgetLabel("big"; text_style = big)])];
                           vertical_align = :baseline)
    canvas = get_iomap_output(print_alone(row))
    found = Dict{String,Int}()
    walk(node, oy) = begin
        node = unwrap_cell(node)
        if node isa GraphicsText
            found[String(unwrap_cell(node.text))] =
                oy + Int(node.y) + (unwrap_cell(node.font) == big ? 24 : 12)
        elseif node isa GraphicsCanvas
            foreach(element -> walk(element, oy + Int(node.y)), unwrap_cell(node.elements))
        end
    end
    walk(canvas, 0)
    # The text of the flow stands at the top of the row and its baseline is the ascent of the
    # big font, 24; the small text beside it stands on that line.
    @test found["big"] == 24
    @test found["small"] == 24
end
end
