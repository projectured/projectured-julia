function test_graphics_layout()
@testset "GraphicsCanvas layout field" begin

# Default constructor uses layout_none
canvas = GraphicsCanvas()
@test canvas.layout == layout_none
@test canvas.elements isa CellVector

# Vector constructor uses layout_none
canvas2 = GraphicsCanvas([GraphicsText("a", 0, 0; font = StyleFont("Ubuntu Mono", 20))])
@test canvas2.layout == layout_none

# Explicit layout constructor
cv = CellVector(Cell[Cell(GraphicsText("a", 0, 0; font = StyleFont("Ubuntu Mono", 20)))])
canvas3 = GraphicsCanvas(cv, layout_vertical)
@test canvas3.layout == layout_vertical

# ListNode-backed canvas
node = ListNode(GraphicsText("line1", 0, 0; font = StyleFont("Ubuntu Mono", 20)))
push!(node, GraphicsText("line2", 0, 20; font = StyleFont("Ubuntu Mono", 20)))
canvas4 = GraphicsCanvas(node, layout_vertical)
@test canvas4.layout == layout_vertical
@test canvas4.elements isa ListNode

# overlapping_elements defaults to true
@test canvas4.overlapping_elements == true
# Explicit non-overlapping
canvas5 = GraphicsCanvas(node; layout = layout_vertical, overlapping = false)
@test canvas5.overlapping_elements == false

end # @testset

@testset "GraphicsFence" begin

# Construction
fence = GraphicsFence()
@test fence.selection === nothing

# Fence is skipped in hit_element_at
canvas = GraphicsCanvas([
    GraphicsText("before", 0, 0; font = StyleFont("Ubuntu Mono", 20)),
    GraphicsFence(),
    GraphicsText("after", 0, 60; font = StyleFont("Ubuntu Mono", 20)),
])
# Hit on first text
result = hit_element_at(canvas, 5, 10)
@test result == 0
# Hit on text after fence — index 2 (0-based), fence at index 1 is skipped
result2 = hit_element_at(canvas, 5, 70)
@test result2 == 2
# Hit in gap — no hit
result3 = hit_element_at(canvas, 5, 55)
@test result3 === nothing

end # @testset

@testset "hit_element_at with ListNode" begin

# ListNode-backed canvas with vertical layout — early termination
node = ListNode(GraphicsText("line1", 0, 0; font = StyleFont("Ubuntu Mono", 20)))
push!(node, GraphicsText("line2", 0, 50; font = StyleFont("Ubuntu Mono", 20)))
push!(node, GraphicsText("line3", 0, 100; font = StyleFont("Ubuntu Mono", 20)))
canvas = GraphicsCanvas(node; layout = layout_vertical, overlapping = false)

# Hit first element
@test hit_element_at(canvas, 5, 10) == 0
# Hit second element
@test hit_element_at(canvas, 5, 60) == 1
# Hit third element
@test hit_element_at(canvas, 5, 110) == 2
# No hit — early stop past all elements
@test hit_element_at(canvas, 5, 200) === nothing

# ListNode with fence — fence is skipped
node2 = ListNode(GraphicsText("a", 0, 0; font = StyleFont("Ubuntu Mono", 20)))
push!(node2, GraphicsFence())
push!(node2, GraphicsText("b", 0, 60; font = StyleFont("Ubuntu Mono", 20)))
canvas2 = GraphicsCanvas(node2; layout = layout_vertical, overlapping = false)
@test hit_element_at(canvas2, 5, 10) == 0
@test hit_element_at(canvas2, 5, 70) == 2

end # @testset
end # test_graphics_layout
