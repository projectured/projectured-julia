"""
Tests for `PointReferenceModule` — struct equality, the `@step c.point(x, y)`
DSL build registration, and the `@reference_case c.point(x, y)` pattern-match
registration.
"""

struct PRA end
struct PRB end
struct PRC end

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

# cursor.point(10, 20) cannot be typed inline via ::T notation because the
# PointReference extension step has no ::T{...} or ::T[...] equivalent
# in the @reference DSL. Build the typed path with @reference(doc, path)
# or directly; here we verify the SKELETON equality using strip on a typed
# reference built with @reference(doc, …), or directly via ConcreteReferencePath.
# We use @reference(doc, path) on a toy document for end-to-end DSL coverage.
# (The 2-arg @reference form is not strict-type-checked.)
let doc = (cursor = (10, 20),)
    # 2-arg form auto-annotates types from doc — no ::T needed, no strict check.
    pr_ref_typed = @reference(doc, cursor)
    @test strip_reference_types(pr_ref_typed) ==
          ConcreteReferencePath(FieldReference("cursor"), EmptyReferencePath())
end

# Verify the .point(x, y) extension step is built correctly via @step and
# that it can be assembled into a ConcreteReferencePath.
let step = @step c.point(10, 20)
    @test step == PointReference(10, 20)
    pr_ref = ConcreteReferencePath(FieldReference("cursor"),
                 ConcreteReferencePath(PointReference(10, 20), EmptyReferencePath()))
    @test pr_ref == ConcreteReferencePath(FieldReference("cursor"),
                        ConcreteReferencePath(PointReference(10, 20), EmptyReferencePath()))
end

# ── @reference_case pattern matching ─────────────────────────────────────

# Confirm `dsl_match_step(::Val{:point}, …)` works: match a path that ends
# with a `.point(x, y)` step and extract the coordinates.
# Build sample paths directly (can't use typed @reference for .point steps).
let sample = ConcreteReferencePath(FieldReference("cursor"),
                 ConcreteReferencePath(PointReference(5, 9), EmptyReferencePath()))
    matched = @reference_case sample begin
        cursor.point(px, py) => (px, py)
    end
    @test matched == (5, 9)
end

# Wildcard-bound coordinates
let sample = ConcreteReferencePath(FieldReference("img"),
                 ConcreteReferencePath(PointReference(0, 42), EmptyReferencePath()))
    matched = @reference_case sample begin
        img.point(_, py) => py
        _ => nothing
    end
    @test matched == 42
end

# Non-matching path falls through to wildcard
let sample = strip_reference_types(@reference ::PRA.value::PRB)
    matched = @reference_case sample begin
        cursor.point(px, py) => :point
        _ => :other
    end
    @test matched == :other
end

end # @testset "PointReference"
end # function test_point_reference
