# Pane geometry: the unit-square rectangles a tree gives its groups, the
# direction search over them, and the traversal order. No font and no backend
# take part, so every case here is plain arithmetic on a tree.
function test_pane_geometry()
@testset "PaneTree geometry" begin

_tab(name) = PaneTab(name, PrimitiveString(name))
_group(name) = PaneGroup(PaneTab[_tab(name)])

# A ≈ comparison over the four rectangle fields.
_same(a, b) = a.x ≈ b.x && a.y ≈ b.y && a.w ≈ b.w && a.h ≈ b.h

@testset "one group fills the square" begin
    group = _group("a")
    tree = PaneTree(group)
    rectangles = get_pane_rectangles(tree)
    @test length(rectangles) == 1
    @test rectangles[1][1] === group
    @test _same(rectangles[1][2], (x = 0.0, y = 0.0, w = 1.0, h = 1.0))
end

@testset "a vertical split divides the width" begin
    left, right = _group("l"), _group("r")
    tree = PaneTree(PaneSplit(:vertical, [left, right]; weights = [0.25, 0.75]))
    @test _same(get_pane_rectangle(tree, left),  (x = 0.0,  y = 0.0, w = 0.25, h = 1.0))
    @test _same(get_pane_rectangle(tree, right), (x = 0.25, y = 0.0, w = 0.75, h = 1.0))
end

@testset "a horizontal split divides the height" begin
    top, bottom = _group("t"), _group("b")
    tree = PaneTree(PaneSplit(:horizontal, [top, bottom]))
    # No weights means equal shares.
    @test _same(get_pane_rectangle(tree, top),    (x = 0.0, y = 0.0, w = 1.0, h = 0.5))
    @test _same(get_pane_rectangle(tree, bottom), (x = 0.0, y = 0.5, w = 1.0, h = 0.5))
end

# The layout every case below navigates:
#
#   +---------+---------+
#   |         |   top   |
#   |  left   +---------+
#   |         | bottom  |
#   +---------+---------+
function _nested()
    left, top, bottom = _group("left"), _group("top"), _group("bottom")
    right = PaneSplit(:horizontal, [top, bottom])
    tree = PaneTree(PaneSplit(:vertical, [left, right]))
    (tree, left, top, bottom)
end

@testset "a nested split gives each leaf its own rectangle" begin
    tree, left, top, bottom = _nested()
    @test _same(get_pane_rectangle(tree, left),   (x = 0.0, y = 0.0, w = 0.5, h = 1.0))
    @test _same(get_pane_rectangle(tree, top),    (x = 0.5, y = 0.0, w = 0.5, h = 0.5))
    @test _same(get_pane_rectangle(tree, bottom), (x = 0.5, y = 0.5, w = 0.5, h = 0.5))
end

@testset "the direction search" begin
    tree, left, top, bottom = _nested()
    # Right from the tall pane: both candidates touch it, so the one that
    # overlaps most wins — and they overlap equally, so the topmost does.
    @test get_pane_neighbour_group(tree, left, :right) === top
    @test get_pane_neighbour_group(tree, top, :left) === left
    @test get_pane_neighbour_group(tree, bottom, :left) === left
    @test get_pane_neighbour_group(tree, top, :down) === bottom
    @test get_pane_neighbour_group(tree, bottom, :up) === top
    # Nothing lies that way.
    @test get_pane_neighbour_group(tree, left, :left) === nothing
    @test get_pane_neighbour_group(tree, left, :up) === nothing
    @test get_pane_neighbour_group(tree, top, :right) === nothing
    @test get_pane_neighbour_group(tree, bottom, :down) === nothing
    # A pane that shares no edge on the other axis is not a neighbour.
    @test get_pane_neighbour_group(tree, left, :down) === nothing
end

@testset "the nearest candidate wins over the one that overlaps more" begin
    #   +------+------+------+
    #   | near | far         |    `near` is closer, `far` faces `here` fully
    #   +------+             |
    #   | here |             |
    #   +------+------+------+
    here, near, far = _group("here"), _group("near"), _group("far")
    column = PaneSplit(:horizontal, [near, here])
    tree = PaneTree(PaneSplit(:vertical, [column, far]; weights = [0.5, 0.5]))
    @test get_pane_neighbour_group(tree, here, :up) === near
    @test get_pane_neighbour_group(tree, here, :right) === far
end

@testset "a group outside the tree has no rectangle" begin
    tree, left, _, _ = _nested()
    stranger = _group("stranger")
    @test get_pane_rectangle(tree, stranger) === nothing
    @test get_pane_neighbour_group(tree, stranger, :right) === nothing
end

@testset "a point names the group under it" begin
    tree, left, top, bottom = _nested()
    @test get_pane_group_at_point(tree, 0.25, 0.5) === left
    @test get_pane_group_at_point(tree, 0.75, 0.25) === top
    @test get_pane_group_at_point(tree, 0.75, 0.75) === bottom
    @test get_pane_group_at_point(tree, 5.0, 0.5) === nothing
end

@testset "the traversal wraps around" begin
    tree, left, top, bottom = _nested()
    @test get_pane_next_group(tree, left) === top
    @test get_pane_next_group(tree, top) === bottom
    @test get_pane_next_group(tree, bottom) === left            # wraps forward
    @test get_pane_next_group(tree, left; backward = true) === bottom   # and backward
    @test get_pane_next_group(tree, top; backward = true) === left
    # A group that is not in the tree starts the traversal at the end it came from.
    stranger = _group("stranger")
    @test get_pane_next_group(tree, stranger) === left
    @test get_pane_next_group(tree, stranger; backward = true) === bottom
end

end # testset
end # function
