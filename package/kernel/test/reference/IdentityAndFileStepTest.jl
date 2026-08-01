"""
Tests for the file-storage step vocabulary added to `ReferenceModule`:
`IdentityDocument`, `FileReferenceStep`, `IdentityReferenceStep`.
"""

using Test
using ProjecturedKernel.ReferenceModule
using ProjecturedKernel.DocumentModule: @document, Document, search_documents

# Placeholder document with a heterogeneous `items` slot — homes the
# `IdentityDocument` children the resolver hunts through.
@document struct _IdBag <: Document
    items::Vector{Any}
end

# A minimal fully-typed document graph so `@reference(document, path)` can
# annotate through the reference-chain steps we add.
@document struct _AnchorChild <: Document
    body::Int
end
@document struct _Anchor <: Document
    child::_AnchorChild
end

function test_identity_and_file_step()
@testset "IdentityDocument + FileReferenceStep + IdentityReferenceStep" begin

    # ── IdentityDocument shape ───────────────────────────────────────────

    @testset "IdentityDocument two-field wrapper" begin
        d = IdentityDocument("host-1", 42)
        @test d.identity == "host-1"
        @test d.content == 42
        # Any content is accepted
        @test IdentityDocument("blob", ["a", 1, nothing]).content == ["a", 1, nothing]
    end

    # ── FileReferenceStep struct + printer + eq ──────────────────────────

    @testset "FileReferenceStep struct" begin
        s = FileReferenceStep("model/Aloha.ned")
        @test s.path == "model/Aloha.ned"
        @test s == FileReferenceStep("model/Aloha.ned")
        @test s != FileReferenceStep("other.ned")
        @test get_reference_step_kind(s) == :structural
    end

    @testset "FileReferenceStep printer" begin
        @test sprint(show, FileReferenceStep("a.jl")) == ".file(\"a.jl\")"
        @test sprint(show, FileReferenceStep("dir/child.json")) == ".file(\"dir/child.json\")"
    end

    @testset "FileReferenceStep evaluate errors without a driver" begin
        # Cross-file navigation is delegated to a FileProject driver. A bare
        # walk (no driver) must fail loudly rather than silently descend.
        @test_throws ErrorException evaluate_reference_step(FileReferenceStep("a.jl"), nothing)
    end

    # ── IdentityReferenceStep struct + printer + eq ──────────────────────

    @testset "IdentityReferenceStep struct" begin
        s = IdentityReferenceStep("host-1")
        @test s.identity == "host-1"
        @test s == IdentityReferenceStep("host-1")
        @test s != IdentityReferenceStep("other")
        @test get_reference_step_kind(s) == :structural
    end

    @testset "IdentityReferenceStep printer" begin
        @test sprint(show, IdentityReferenceStep("host-1")) == ".identity(\"host-1\")"
    end

    # ── IdentityReferenceStep DFS resolver ───────────────────────────────

    @testset "resolver finds the matching IdentityDocument's content" begin
        bag = _IdBag(Any[IdentityDocument("host-1", 42),
                         IdentityDocument("host-2", "abc")])
        @test evaluate_reference_step(IdentityReferenceStep("host-1"), bag) == 42
        @test evaluate_reference_step(IdentityReferenceStep("host-2"), bag) == "abc"
    end

    @testset "resolver descends recursively" begin
        # An IdentityDocument nested inside another IdentityDocument's
        # content must still be found (DFS descent, not shallow scan).
        nested = _IdBag(Any[IdentityDocument("outer",
                                             _IdBag(Any[IdentityDocument("inner", 99)]))])
        @test evaluate_reference_step(IdentityReferenceStep("inner"), nested) == 99
    end

    @testset "resolver errors on no match" begin
        bag = _IdBag(Any[IdentityDocument("host-1", 42)])
        @test_throws IdentityDocumentNotFound evaluate_reference_step(
            IdentityReferenceStep("nope"), bag)
    end

    @testset "resolver errors on duplicate identities" begin
        # Two IdentityDocuments with the same identity in the same focus
        # must be rejected — a stored reference cannot silently pick one.
        bag = _IdBag(Any[IdentityDocument("dup", 1),
                         IdentityDocument("dup", 2)])
        @test_throws DuplicateIdentityDocument evaluate_reference_step(
            IdentityReferenceStep("dup"), bag)
    end

    # ── DSL round-trip (@reference) ──────────────────────────────────────

    @testset "@reference construction — file step head, then fields" begin
        # Use `@reference(document, path)` to skip the strict-typing check
        # (cross-file steps can't be evaluated for annotation, so partial
        # types are expected).
        d = _Anchor(_AnchorChild(0))
        r = @reference(d, file("a.jl").child.body)
        stripped = strip_reference_types(r)
        # Chain shape: file("a.jl") → child → body
        expected = Reference(FileReferenceStep("a.jl"),
                             FieldReferenceStep("child"),
                             FieldReferenceStep("body"))
        @test stripped == expected
    end

    @testset "@reference construction — identity step" begin
        d = _Anchor(_AnchorChild(0))
        r = @reference(d, identity("host-1").body)
        stripped = strip_reference_types(r)
        expected = Reference(IdentityReferenceStep("host-1"),
                             FieldReferenceStep("body"))
        @test stripped == expected
    end

    @testset "@reference construction — full cross-file chain" begin
        d = _Anchor(_AnchorChild(0))
        r = @reference(d, file("model/Aloha.ned").identity("host-1").child.body)
        stripped = strip_reference_types(r)
        expected = Reference(FileReferenceStep("model/Aloha.ned"),
                             IdentityReferenceStep("host-1"),
                             FieldReferenceStep("child"),
                             FieldReferenceStep("body"))
        @test stripped == expected
    end

    # ── @reference_case pattern matching ─────────────────────────────────

    @testset "@reference_case matches file() with bound path" begin
        r = Reference(FileReferenceStep("a.jl"), FieldReferenceStep("body"))
        matched = @reference_case r begin
            file(p).body => (:file, p)
            _            => :miss
        end
        @test matched == (:file, "a.jl")
    end

    @testset "@reference_case matches identity() with bound id" begin
        r = Reference(IdentityReferenceStep("host-1"), FieldReferenceStep("body"))
        matched = @reference_case r begin
            identity(i).body => (:id, i)
            _                => :miss
        end
        @test matched == (:id, "host-1")
    end

end
end
