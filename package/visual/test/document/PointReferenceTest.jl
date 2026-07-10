"""
Tests for `PointReferenceModule` — struct equality, the `@step c.point(x, y)`
DSL build registration, and the `@reference_case c.point(x, y)` pattern-match
registration.
"""
function test_point_reference()
@testset "PointReference" begin

# ── struct construction and equality ─────────────────────────────────────

pr = PointReference(3, 7)
@test pr.x == 3
@test pr.y == 7
@test pr == PointReference(3, 7)
@test pr != PointReference(3, 8)

# ── @step DSL build registration ─────────────────────────────────────────

# The `c.point(x, y)` notation is registered by PointReferenceModule's
# `dsl_build_step(::Val{:point}, …)` seam — exercised here to confirm the
# registration survived the move out of the kernel.
@test (@step c.point(2, 3)) == PointReference(2, 3)
@test (@step c.point(0, 0)) == PointReference(0, 0)

# ── @reference DSL via .point(…) ────────────────────────────────────────

pr_ref = @reference cursor.point(10, 20)
@test pr_ref == ConcreteReferencePath(FieldReference("cursor"),
                    ConcreteReferencePath(PointReference(10, 20), EmptyReferencePath()))

# ── @reference_case pattern matching ─────────────────────────────────────

# Confirm `dsl_match_step(::Val{:point}, …)` works: match a path that ends
# with a `.point(x, y)` step and extract the coordinates.
let sample = @reference cursor.point(5, 9)
    matched = @reference_case sample begin
        cursor.point(px, py) => (px, py)
    end
    @test matched == (5, 9)
end

# Wildcard-bound coordinates
let sample = @reference img.point(0, 42)
    matched = @reference_case sample begin
        img.point(_, py) => py
        _ => nothing
    end
    @test matched == 42
end

# Non-matching path falls through to wildcard
let sample = @reference value
    matched = @reference_case sample begin
        cursor.point(px, py) => :point
        _ => :other
    end
    @test matched == :other
end

end # @testset "PointReference"
end # function test_point_reference
