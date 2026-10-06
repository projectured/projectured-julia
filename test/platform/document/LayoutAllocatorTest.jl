function test_layout_allocator()
@testset "compute_axis_offsets — the edge of every band, cumulative" begin
    @test compute_axis_offsets(Int[], 5) == [0]
    @test compute_axis_offsets(Int[10, 20, 30], 0) == [0, 10, 30, 60]
    @test compute_axis_offsets(Int[10, 20, 30], 4) == [0, 14, 38, 72]
end

@testset "find_axis_band — the band a coordinate falls in" begin
    edges = compute_axis_offsets(Int[10, 20, 30], 4)
    @test find_axis_band(edges, 0) == 1
    @test find_axis_band(edges, 13) == 1      # inside the first band and its gap
    @test find_axis_band(edges, 14) == 2
    @test find_axis_band(edges, 71) == 3
    @test find_axis_band(edges, 72) === nothing
    @test find_axis_band(edges, -1) === nothing
end

@testset "allocate_axis — bare children" begin

# All bare → preferred = intrinsic (treated as the seed), no weight: no slack growth.
actual = allocate_axis(1000; mins = Int[0, 0, 0],
                       maxs = Int[typemax(Int), typemax(Int), typemax(Int)],
                       prefs = Int[100, 200, 300],     # the intrinsic sizes
                       weights = Float64[0.0, 0.0, 0.0],
                       gap = 0, n = 3)
@test actual == [100, 200, 300]

end # @testset

@testset "allocate_axis — fixed + flex" begin

# A pinned Files-pane column: fixed at 200, the right column flexes.
# available = 1280, gap = 0, two slots.
actual = allocate_axis(1280; mins = Int[200, 0], maxs = Int[200, typemax(Int)],
                       prefs = Int[200, 0], weights = Float64[0.0, 1.0], gap = 0, n = 2)
@test actual[1] == 200
@test actual[1] + actual[2] == 1280

end # @testset

@testset "allocate_axis — two flex children share remaining" begin

# 30/70 split via weights.
actual = allocate_axis(1000; mins = Int[0, 0], maxs = Int[typemax(Int), typemax(Int)],
                       prefs = Int[0, 0], weights = Float64[3.0, 7.0], gap = 0, n = 2)
@test sum(actual) == 1000
@test actual[1] >= 290 && actual[1] <= 310
@test actual[2] >= 690 && actual[2] <= 710

end # @testset

@testset "allocate_axis — gap reduces available" begin

# 3 slots, 10 px gap → 20 px total gap consumed before the seed allocation.
actual = allocate_axis(320; mins = Int[0, 0, 0],
                       maxs = Int[typemax(Int), typemax(Int), typemax(Int)],
                       prefs = Int[100, 100, 100], weights = Float64[0.0, 0.0, 0.0],
                       gap = 10, n = 3)
@test actual == [100, 100, 100]   # seed already fills 300 + 20 gaps = 320

end # @testset

@testset "allocate_axis — shrink under min" begin

# Available = 100 but mins sum to 200 → overflow allowed, each pinned at min.
actual = allocate_axis(100; mins = Int[80, 80, 80], maxs = Int[200, 200, 200],
                       prefs = Int[80, 80, 80], weights = Float64[1.0, 1.0, 1.0], gap = 0,
                       n = 3)
@test actual == [80, 80, 80]

end # @testset

@testset "allocate_axis — weighted shrink to min" begin

# Available less than preferred sum; only weighted children shrink.
actual = allocate_axis(300; mins = Int[100, 50, 50],
                       maxs = Int[typemax(Int), typemax(Int), typemax(Int)],
                       prefs = Int[200, 200, 200],     # the seed is 600, so 300 must go
                       weights = Float64[0.0, 1.0, 1.0],
                       gap = 0, n = 3)
@test actual[1] == 200          # weight 0 → not touched
@test sum(actual) == 300
@test actual[2] >= 50 && actual[3] >= 50

end # @testset

@testset "allocate_axis — max caps growth" begin

# 1000 avail; first child capped at 250, second flex absorbs the rest.
actual = allocate_axis(1000; mins = Int[0, 0], maxs = Int[250, typemax(Int)],
                       prefs = Int[0, 0], weights = Float64[1.0, 1.0], gap = 0, n = 2)
@test actual[1] == 250
@test actual[2] == 750

end # @testset

end # test_layout_allocator

function test_layout_constraint_helpers()
@testset "LayoutConstraint — defaults" begin

bare = WidgetLabel("x")
@test layout_min(bare,       :x, 100) == 0
@test layout_max(bare,       :x, 100) == typemax(Int)
@test layout_preferred(bare, :x, 100) == 100
@test layout_weight(bare,    :x) == 0.0

end # @testset

@testset "LayoutConstraint — overrides applied per axis" begin

inner = WidgetLabel("x")
wrapped = LayoutConstraint(inner;
                           min_width=50, max_width=300, preferred_width=200, weight_width=0.5,
                           min_height=10, max_height=20)
@test layout_min(wrapped,       :x, 999) == 50
@test layout_max(wrapped,       :x, 999) == 300
@test layout_preferred(wrapped, :x, 999) == 200
@test layout_weight(wrapped,    :x) == 0.5
# Height fields use defaults for the ones not set.
@test layout_min(wrapped,       :y, 99) == 10
@test layout_max(wrapped,       :y, 99) == 20
@test layout_preferred(wrapped, :y, 99) == 99    # falls back to intrinsic
@test layout_weight(wrapped,    :y) == 0.0

end # @testset

@testset "LayoutConstraint — reactive updates" begin

inner = WidgetLabel("x")
wrapped = LayoutConstraint(inner; weight_width=0.3)
@test layout_weight(wrapped, :x) == 0.3
wrapped.weight_width = 0.7
@test layout_weight(wrapped, :x) == 0.7

end # @testset

end # test_layout_constraint_helpers
