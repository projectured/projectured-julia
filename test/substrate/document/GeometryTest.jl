# Unit tests for the AffineTransform value type (compose, apply, inverse).
function test_affine_transform()
@testset "AffineTransform" begin

    @testset "identity is a no-op" begin
        @test apply_affine_transform(affine_identity, 3.0, 7.0) == (3.0, 7.0)
        @test is_affine_axis_aligned(affine_identity)
    end

    @testset "translate and scale" begin
        T = make_affine_translate(10, 20)
        @test apply_affine_transform(T, 1.0, 2.0) == (11.0, 22.0)
        S = make_affine_scale(2.0, 3.0)
        @test apply_affine_transform(S, 4.0, 5.0) == (8.0, 15.0)
        @test is_affine_axis_aligned(S)
    end

    @testset "compose applies right-hand transform first" begin
        # (S ∘ T): translate then scale.
        M = make_affine_scale(2.0, 3.0) ∘ make_affine_translate(10.0, 20.0)
        @test apply_affine_transform(M, 1.0, 1.0) == (2.0 * (1.0 + 10.0), 3.0 * (1.0 + 20.0))
        @test apply_affine_transform(M, 1.0, 1.0) == (22.0, 63.0)
    end

    @testset "inverse round-trips" begin
        M = make_affine_scale(2.0, 3.0) ∘ make_affine_translate(10.0, 20.0)
        inv = compute_affine_inverse(M)
        x, y = apply_affine_transform(M, 7.0, 9.0)
        bx, by = apply_affine_transform(inv, x, y)
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
        M = make_affine_translate(a...) ∘ make_affine_scale(1.5, 1.5) ∘ make_affine_translate(-a[1], -a[2])
        @test all(apply_affine_transform(M, a...) .≈ a)
    end

end
end
