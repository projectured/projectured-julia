# ═══════════════════════════════════════════════════════════════════════════
# test/editor/ConstructTest.jl
#
# Live example construction test (see plan/pending/live-example-construction.md).
#
# The goal: rebuild an example document from an empty seed using only the
# editor's own gestures, then assert the reconstruction deeply equals the
# original. This proves the interactive authoring path (gesture → binding →
# operation → apply) is expressive and correct for the whole example corpus —
# every example is reachable from nothing.
#
# This file is built up phase by phase:
#   • Phase 0 — the content-equality oracle (`compare_content`)          ← HERE
#   • Phase 1 — leaf reconstruction (print-then-type)
#   • Phase 2 — structural recipes (probe-and-learn), JSON
#   • Phase 3 — insertion-domain recipes, Julia
#   • Phase 4 — `test_construct(example)` harness + sweep
# ═══════════════════════════════════════════════════════════════════════════

# ───────────────────────────────────────────────────────────────────────────
# Phase 0 — the content-equality oracle
#
# `compare_content` walks two documents in lockstep and reports every point
# where their *content* diverges, tagged with the path to the divergence. It
# mirrors `DocumentModule.walk_document`'s descent exactly — the four shapes
# (`is_element_collection` / dict / array / struct-by-`fieldnames`), the cell
# unwrap, the `:ref` / `:selection` skip, and the `is_walk_leaf` stop — so it
# agrees with the canonical notion of what a document's content *is*. Cell
# identity, selection, and reactive wrappers are deliberately invisible to it.
#
# There is no `Base.==` on `@document` nodes (they compare by identity), so this
# is the one genuinely new primitive the construction test needs.
# ───────────────────────────────────────────────────────────────────────────

# A content leaf — nothing to descend into. Same set as `walk_document`'s
# internal `is_walk_leaf` (which is not exported): a scalar Julia value or an
# opaque document.
_content_leaf(x) = x === nothing || x isa Number || x isa AbstractString ||
                   x isa Symbol || x isa Char || is_walk_opaque(x)

# Strict leaf equality. Numbers of different concrete types are NOT equal — a
# reconstruction that yields `42.0` where the target holds `42` is a real
# divergence the construction test must surface (typing `4` then `2` producing a
# `Float64` is a reader bug, not a rounding nicety). Strings compare by content
# (a `SubString` and a `String` over the same characters are equal content).
_leaf_equal(a::AbstractString, b::AbstractString) = a == b
_leaf_equal(a, b) = typeof(a) === typeof(b) && isequal(a, b)

# Two structural nodes are the same *kind* when they share a type name. Compared
# by `typename`, not `==`, because `@document` emits parametric reactive structs
# (`RCJsonObject{…}`) whose cell-kind parameters may differ between two
# independently-built instances of the same logical document type.
_same_kind(a, b) = Base.typename(typeof(a)) === Base.typename(typeof(b))

"""
    compare_content(actual, expected) -> Vector{String}

Deep structural comparison of two documents by **content only**. Returns a list
of mismatch descriptions, each tagged with the path (`∅` = root, `.field`,
`[i]`) to the divergence; an **empty vector means the documents are equal**.

Selection state, cell identity, and reactive wrappers are ignored — the walk
unwraps cells and skips `:ref` / `:selection`, exactly as
`DocumentModule.walk_document` does. This is the oracle behind `test_construct`.
"""
function compare_content(actual, expected)
    errs = String[]
    _compare!(errs, unwrap_cell(actual), unwrap_cell(expected), "")
    errs
end

function _compare!(errs, a, b, path)
    here = isempty(path) ? "∅" : path

    # ── leaves ──────────────────────────────────────────────────────────────
    if _content_leaf(a) || _content_leaf(b)
        if !(_content_leaf(a) && _content_leaf(b) && _leaf_equal(a, b))
            push!(errs, "$here: value mismatch: $(repr(a)) ≠ $(repr(b))")
        end
        return
    end

    # ── both are structural nodes ────────────────────────────────────────────
    if !_same_kind(a, b)
        push!(errs, "$here: kind mismatch: $(nameof(typeof(a))) ≠ $(nameof(typeof(b)))")
        return
    end

    if is_element_collection(b)
        la, lb = length(a), length(b)
        la == lb || (push!(errs, "$here: arity mismatch: $la ≠ $lb"); return)
        for i in 1:lb
            _compare!(errs, unwrap_cell(a[i]), unwrap_cell(b[i]), "$path[$i]")
        end
    elseif b isa AbstractDict
        ka, kb = Set(keys(a)), Set(keys(b))
        ka == kb || (push!(errs, "$here: keys mismatch: $ka ≠ $kb"); return)
        for k in keys(b)
            _compare!(errs, unwrap_cell(a[k]), unwrap_cell(b[k]), "$path.$k")
        end
    elseif b isa AbstractArray
        la, lb = length(a), length(b)
        la == lb || (push!(errs, "$here: arity mismatch: $la ≠ $lb"); return)
        for i in 1:lb
            (isassigned(a, i) && isassigned(b, i)) || continue
            _compare!(errs, unwrap_cell(a[i]), unwrap_cell(b[i]), "$path[$i]")
        end
    else
        for fn in fieldnames(typeof(b))
            (fn === :ref || fn === :selection) && continue
            isdefined(b, fn) || continue
            _compare!(errs, unwrap_cell(getfield(a, fn)),
                            unwrap_cell(getfield(b, fn)), "$path.$fn")
        end
    end
end

# ── Phase-0 unit-test fixtures ──────────────────────────────────────────────
# Small `@document` types that exercise the oracle's branches without needing a
# domain (which lives above the kernel): a scalar leaf, a nested struct child,
# and a positional list (via a plain `Vector` field → the array branch). The
# `is_element_collection` branch is covered from Phase 1 on with real JSON.
@document struct _OracleLeaf
    value::Int
end
@document struct _OraclePair
    name::String
    child::_OracleLeaf
end
@document struct _OracleList
    items::Vector{Any} = Any[]
end

"""
    test_construct_oracle()

Unit tests for `compare_content`: equal documents produce no mismatch; a
differing leaf value, a differing nested value, a kind mismatch, a list arity
mismatch, and a list element mismatch each produce exactly one mismatch tagged
with the right path.
"""
function test_construct_oracle()
    @testset "construct/oracle" begin
        # equal
        @test isempty(compare_content(_OracleLeaf(3), _OracleLeaf(3)))
        @test isempty(compare_content(_OraclePair("a", _OracleLeaf(3)),
                                      _OraclePair("a", _OracleLeaf(3))))

        # differing leaf value → one mismatch at `.value`
        d = compare_content(_OracleLeaf(3), _OracleLeaf(4))
        @test length(d) == 1
        @test occursin(".value", d[1])

        # differing nested value → one mismatch at `.child.value`
        d = compare_content(_OraclePair("a", _OracleLeaf(3)),
                            _OraclePair("a", _OracleLeaf(4)))
        @test length(d) == 1
        @test occursin(".child.value", d[1])

        # differing name → one mismatch at `.name`
        d = compare_content(_OraclePair("a", _OracleLeaf(3)),
                            _OraclePair("b", _OracleLeaf(3)))
        @test length(d) == 1
        @test occursin(".name", d[1])

        # kind mismatch (leaf vs pair) → reported at root
        d = compare_content(_OracleLeaf(3), _OraclePair("a", _OracleLeaf(3)))
        @test length(d) == 1
        @test occursin("kind mismatch", d[1])

        # list arity mismatch
        d = compare_content(_OracleList(items = Any[_OracleLeaf(1)]),
                            _OracleList(items = Any[_OracleLeaf(1), _OracleLeaf(2)]))
        @test length(d) == 1
        @test occursin("arity mismatch", d[1])

        # list element mismatch → `.items[1].value`
        d = compare_content(_OracleList(items = Any[_OracleLeaf(1)]),
                            _OracleList(items = Any[_OracleLeaf(9)]))
        @test length(d) == 1
        @test occursin("[1].value", d[1])

        # strict scalar leaves: an Int and a Float of equal magnitude differ
        @test isempty(compare_content(42, 42))
        @test !isempty(compare_content(42, 42.0))    # 42 ≠ 42.0
        @test isempty(compare_content("ab", "ab"))
    end
end
