# A move of the pointer over a JSON document names the part under it. The text
# maps the point back to its place in the document, and each document on the path
# holds its own tail: in `[1, [2, 3]]` with the pointer on the `2`, the outer array
# holds `.elements[2].elements[1]` and more, the inner array `.elements[1]` and
# more, and the number the place in its own value.

# Write an answer at `root`: the mouse target by the chain write, and every other
# operation on its own document.
function _jmt_apply!(root, operation)
    operation === nothing && return
    if operation isa CompoundOperation
        foreach(member -> _jmt_apply!(root, member), operation.operations)
    elseif operation isa ReplaceMouseTargetOperation
        replace_mouse_target!(root, operation.path)
    else
        evaluate_operation(nothing, operation)
    end
    nothing
end

# The first `n` steps of the mouse target of `document`, or `nothing`.
function _jmt_head(document, n)
    target = get_mouse_target(document)
    target === nothing && return nothing
    steps = collect(get_reference_steps(target))
    length(steps) < n ? steps : steps[1:n]
end

_jmt_element(i) = [FieldReferenceStep("elements"), ElementReferenceStep(i)]

function test_json_mouse_target()
@testset "a move over a JSON document names the part under the pointer" begin
    one = JsonNumber(1)
    two = JsonNumber(2)
    inner = JsonArray([two, JsonNumber(3)])
    outer = JsonArray([one, inner])
    projection = make_json_projection_example(measure = FixedMeasure(10, 18, 6, 0))
    iomap = print_document(projection, outer)
    text = _find_text_iomap(iomap)
    # A point inside the first character of the segment that shows `shown`, the
    # `index`-th such segment.
    function point(shown, index = 1)
        segments = [sc for sc in text.char_to_coord if sc.text == shown]
        segment = segments[index]
        (segment.x + 2, segment.y + segment.font.size ÷ 2)
    end
    move!(x, y) = _jmt_apply!(outer, read_child_move(iomap, MouseMove(x, y; time = 0.0)))

    move!(point("2")...)
    @test _jmt_head(outer, 4) == [_jmt_element(2); _jmt_element(1)]
    @test _jmt_head(inner, 2) == _jmt_element(1)
    @test _jmt_head(two, 1) == [FieldReferenceStep("value")]
    @test get_mouse_target(one) === nothing

    # Onto the `1`: the branch of the inner array is cleared.
    move!(point("1")...)
    @test _jmt_head(outer, 2) == _jmt_element(1)
    @test _jmt_head(one, 1) == [FieldReferenceStep("value")]
    @test get_mouse_target(inner) === nothing
    @test get_mouse_target(two) === nothing

    # Onto the bracket that opens the inner array: the bracket is a part of that
    # array, not of the number after it.
    move!(point("[", 2)...)
    @test _jmt_head(outer, 2) == _jmt_element(2)
    @test has_introduced_step(get_mouse_target(inner))
    @test get_mouse_target(two) === nothing
    @test get_mouse_target(one) === nothing
end
end # test_json_mouse_target
