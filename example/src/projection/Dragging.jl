# Dragging example projection. DraggingState wraps a content sub-tree exactly the
# way WidgetScrollPane does, so this mirrors `make_scrolling_projection`:
# NestingProjection applies DraggingProjection at the wrapper and hands the inner
# `content` to the supplied `recursion` (the ordinary json → graphics pipeline).
# DraggingProjection's printer is transparent, so the array renders as usual; its
# reader turns a press-drag-release into a MoveRangeOperation that reorders the
# array's elements.
function make_dragging_projection_example(; measure=truetype_measure_text)
    NestingProjection(
        DraggingProjection();
        recursion = make_json_projection_example(measure=measure),
    )
end
