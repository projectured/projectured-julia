# The forward map and the backward map of every widget example agree: each part
# that a widget displays maps forward to a printed node, and a point where that
# node draws something maps backward to the part, or to a part inside it. The
# examples are printed in a window of 1200 by 800, and the test is the window: it
# gives the root a point in the frame of the root's canvas, and a screen a point
# in the frame of the window of the part.

_rt_value(v) = v isa AbstractCell ? _rt_value(v[]) : v

_rt_place(node) = (hasproperty(node, :x) && hasproperty(node, :y)) ?
    (Int(_rt_value(getfield(node, :x))), Int(_rt_value(getfield(node, :y)))) : (0, 0)

_rt_center(box) = (box.x + box.width ÷ 2, box.y + box.height ÷ 2)

# Whether the widgets do not display the part at `reference`: the content of a
# tab that is not open, a menu or a submenu that is closed, the dialog of a
# button, what an action holds, and a widget that is not visible.
function _rt_is_hidden(document, reference)
    node = _rt_value(document)
    steps = collect(get_reference_steps(reference))
    for (i, step) in enumerate(steps)
        node isa WidgetDocument && hasproperty(node, :visible) && node.visible === false && return true
        step isa FieldReferenceStep && step.name in ("submenu", "menu", "dialog", "action") && return true
        if node isa WidgetTabbedPane && step isa FieldReferenceStep && step.name == "selector_element_pairs" &&
           i < length(steps)
            count = length(node.selector_element_pairs)
            open = WidgetModule._tab_index_from_selection(get_stored_selection(node), count)
            steps[i + 1].start + 1 == (open == 0 ? 1 : open) || return true
        end
        node = _rt_value(evaluate_reference_step(step, node))
    end
    node isa WidgetDocument && hasproperty(node, :visible) && node.visible === false
end

# The drawn elements under the node at `image`, level by level, as references.
function _rt_drawn_references(output, image; depth = 7, limit = 60)
    node = try
        _rt_value(evaluate_reference(output, image))
    catch
        return Reference[]
    end
    found = Reference[]
    level = Any[(node, image)]
    for _ in 1:depth
        next = Any[]
        for (child, reference) in level
            if child isa GraphicsCanvas
                elements = _rt_value(getfield(child, :elements))
                elements isa Union{AbstractVector, CellVector} || continue
                for k in 1:length(elements)
                    push!(next, (_rt_value(elements[k]), concat_references(reference,
                        extend_reference(EmptyReference(), FieldReferenceStep("elements"), ElementReferenceStep(k)))))
                end
            elseif child isa GraphicsViewport
                push!(next, (_rt_value(getfield(child, :content)), concat_references(reference,
                    extend_reference(EmptyReference(), FieldReferenceStep("content")))))
            elseif child isa GraphicsDocument
                push!(found, reference)
                length(found) >= limit && return found
            end
        end
        level = next
    end
    found
end

# The points to try: the center of the visible box, then the center of each drawn
# element under the image that is visible.
function _rt_points(output, image, box)
    points = [_rt_center(box)]
    for drawn in _rt_drawn_references(output, image)
        drawn_box = find_reference_box(output, drawn; visible = true)
        (drawn_box === nothing || drawn_box.width <= 0 || drawn_box.height <= 0) && continue
        push!(points, _rt_center(drawn_box))
    end
    points
end

# A point of the output, as the window gives it to the projection.
function _rt_point_reference(output, reference, x, y)
    if output isa ScreenDocument
        steps = collect(get_reference_steps(reference))
        (length(steps) >= 2 && steps[1] isa FieldReferenceStep && steps[1].name == "windows") || return nothing
        window = _rt_value(evaluate_reference_step(steps[2], _rt_value(getfield(output, :windows))))
        wx, wy = _rt_place(window)
        return extend_reference(EmptyReference(), steps[1], steps[2], FieldReferenceStep("content"),
                                PointReferenceStep(x - wx, y - wy))
    end
    rx, ry = _rt_place(output)
    PointReferenceStep(x - rx, y - ry)
end

# The answer of the round trip of one part: `:returns`, `:hidden`, `:out_of_view`,
# `:draws_nothing`, or what went wrong, with the answer of the backward map.
function _rt_round_trip(document, projection, iomap, output, part)
    reference = strip_reference_types(part)
    image = map_reference_forward(projection, iomap, part)
    image === nothing && return (_rt_is_hidden(document, reference) ? :hidden : :no_image, nothing)
    box = find_reference_box(output, image; visible = true)
    if box === nothing
        return (find_reference_box(output, image) === nothing ? :no_box : :out_of_view, nothing)
    end
    (box.width <= 0 || box.height <= 0) && return (:draws_nothing, nothing)
    other = nothing
    for (x, y) in _rt_points(output, image, box)
        point = _rt_point_reference(output, reference, x, y)
        point === nothing && continue
        answer = map_reference_backward(projection, iomap, point)
        if answer === nothing
            reference isa EmptyReference && return (:returns, nothing)
            continue
        end
        answer = strip_reference_types(answer)
        (answer == reference || is_reference_prefix(reference, answer)) && return (:returns, nothing)
        other = answer
    end
    (other === nothing ? :no_part : :other_part, other)
end

function test_widget_round_trip()
@testset "every part of a widget example maps forward and back again" begin
    examples = filter(example -> startswith(example.name, "widget"), substrate_examples)
    @test length(examples) >= 40
    failures = String[]
    for example in examples
        document = example.make_document()
        projection = example.make_projection()
        ctx = PrinterContext(EmptyReference(), Cell(1200), Cell(800), Dict{Symbol,Any}())
        iomap = print_document(projection, nothing, document, ctx)
        output = _rt_value(get_iomap_output(iomap))
        parts = search_references(document, node ->
            (node isa WidgetDocument || node isa LayoutDocument) && !(node isa WidgetStyle))
        returned = 0
        for part in parts
            outcome, answer = _rt_round_trip(document, projection, iomap, output, part)
            outcome === :returns && (returned += 1; continue)
            outcome in (:hidden, :out_of_view, :draws_nothing) && continue
            push!(failures, string(example.name, " ", strip_reference_types(part), ": ", outcome,
                                   answer === nothing ? "" : string(" ", answer)))
        end
        returned > 0 || push!(failures, string(example.name, ": no part makes the round trip"))
    end
    isempty(failures) || foreach(line -> println("  ", line), failures)
    @test isempty(failures)
end
end
