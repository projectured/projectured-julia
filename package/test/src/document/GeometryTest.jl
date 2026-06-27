# Unit tests for the AffineTransform value type (compose, apply, inverse).
function test_affine_transform()
@testset "AffineTransform" begin

    @testset "identity is a no-op" begin
        @test affine_apply(affine_identity, 3.0, 7.0) == (3.0, 7.0)
        @test affine_is_axis_aligned(affine_identity)
    end

    @testset "translate and scale" begin
        T = affine_translate(10, 20)
        @test affine_apply(T, 1.0, 2.0) == (11.0, 22.0)
        S = affine_scale(2.0, 3.0)
        @test affine_apply(S, 4.0, 5.0) == (8.0, 15.0)
        @test affine_is_axis_aligned(S)
    end

    @testset "compose applies right-hand transform first" begin
        # (S ∘ T): translate then scale.
        M = affine_scale(2.0, 3.0) ∘ affine_translate(10.0, 20.0)
        @test affine_apply(M, 1.0, 1.0) == (2.0 * (1.0 + 10.0), 3.0 * (1.0 + 20.0))
        @test affine_apply(M, 1.0, 1.0) == (22.0, 63.0)
    end

    @testset "inverse round-trips" begin
        M = affine_scale(2.0, 3.0) ∘ affine_translate(10.0, 20.0)
        inv = affine_inverse(M)
        x, y = affine_apply(M, 7.0, 9.0)
        bx, by = affine_apply(inv, x, y)
        @test bx ≈ 7.0
        @test by ≈ 9.0
        # M ∘ inv == identity (within fp tolerance)
        I = M ∘ inv
        @test I.a ≈ 1.0 && I.d ≈ 1.0
        @test abs(I.b) < 1e-9 && abs(I.c) < 1e-9
        @test abs(I.e) < 1e-9 && abs(I.f) < 1e-9
    end

    @testset "zoom-about a fixed point keeps that point fixed" begin
        a = (40.0, 60.0)
        M = affine_translate(a...) ∘ affine_scale(1.5, 1.5) ∘ affine_translate(-a[1], -a[2])
        @test all(affine_apply(M, a...) .≈ a)
    end

end
end
