"""
Tests for `PointReferenceModule` — struct equality, the `@reference_step c.point(x, y)`
DSL build registration, and the `@reference_case c.point(x, y)` pattern-match
registration.
"""

struct PRA end
struct PRB end
struct PRC end

function test_point_reference()
@testset "PointReferenceStep" begin

# ── struct construction and equality ─────────────────────────────────────

pr = PointReferenceStep(3, 7)
@test pr.x == 3
@test pr.y == 7
@test pr == PointReferenceStep(3, 7)
@test pr != PointReferenceStep(3, 8)

# ── @reference_step DSL build registration ─────────────────────────────────────────

# The `c.point(x, y)` notation is registered by PointReferenceModule's
# `build_reference_step(::Val{:point}, …)` seam — exercised here to confirm the
# registration survived the move out of the kernel.
@test (@reference_step c.point(2, 3)) == PointReferenceStep(2, 3)
@test (@reference_step c.point(0, 0)) == PointReferenceStep(0, 0)

# ── @reference DSL via .point(…) ────────────────────────────────────────

# cursor.point(10, 20) cannot be typed inline via ::T notation because the
# PointReferenceStep extension step has no ::T{...} or ::T[...] equivalent
# in the @reference DSL. Build the typed path with @reference(doc, path)
# or directly; here we verify the SKELETON equality using strip on a typed
# reference built with @reference(doc, …), or directly via ConcreteReference.
# We use @reference(doc, path) on a toy document for end-to-end DSL coverage.
# (The 2-arg @reference form is not strict-type-checked.)
let doc = (cursor = (10, 20),)
    # 2-arg form auto-annotates types from doc — no ::T needed, no strict check.
    pr_ref_typed = @reference(doc, cursor)
    @test strip_reference_types(pr_ref_typed) ==
          ConcreteReference(FieldReferenceStep("cursor"), EmptyReference())
end

# Verify the .point(x, y) extension step is built correctly via @reference_step and
# that it can be assembled into a ConcreteReference.
let step = @reference_step c.point(10, 20)
    @test step == PointReferenceStep(10, 20)
    pr_ref = ConcreteReference(FieldReferenceStep("cursor"),
                 ConcreteReference(PointReferenceStep(10, 20), EmptyReference()))
    @test pr_ref == ConcreteReference(FieldReferenceStep("cursor"),
                        ConcreteReference(PointReferenceStep(10, 20), EmptyReference()))
end

# ── @reference_case pattern matching ─────────────────────────────────────

# Confirm `match_reference_step(::Val{:point}, …)` works: match a path that ends
# with a `.point(x, y)` step and extract the coordinates.
# Build sample paths directly (can't use typed @reference for .point steps).
let sample = ConcreteReference(FieldReferenceStep("cursor"),
                 ConcreteReference(PointReferenceStep(5, 9), EmptyReference()))
    matched = @reference_case sample begin
        cursor.point(px, py) => (px, py)
    end
    @test matched == (5, 9)
end

# Wildcard-bound coordinates
let sample = ConcreteReference(FieldReferenceStep("img"),
                 ConcreteReference(PointReferenceStep(0, 42), EmptyReference()))
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

end # @testset "PointReferenceStep"
end # function test_point_reference
