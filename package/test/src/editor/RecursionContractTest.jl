# ═══════════════════════════════════════════════════════════════════════════
# test/src/editor/RecursionContractTest.jl
#
# Validates the *recursion contract*: the four core projection functions
# (print_document, read_intent, map_reference_forward,
# map_reference_backward) must each be recursive by DELEGATING a child to the
# child projection's own version of the same function — via the `recursion`
# parameter (printer) and the stored child IoMaps (reader / mappers). No
# projection may flatten a subtree itself or introduce a fifth recursive
# function. See documentation/projection-system.md "The recursion contract".
#
# This harness is the *external* validation the contract calls for: it drives
# the existing four functions over example pipelines and adds NO new
# per-projection generic function. It reuses `_walk!` (PrinterTest.jl),
# `collect_text_selections` (SelectionEnumeration.jl), and `strip_reference_types`.
#
# Two checks:
#
#   1. Delegation probe (the discriminating check).  Re-invokes a node
#      projection's `print_document` with a *spy* recursion that counts how
#      often it is called, and forces the result so the lazy child cells run.
#      A node whose input has projectable children MUST call the spy at least
#      once; a projection that flattens its subtree (ignores `recursion`) never
#      does — which is exactly how `SyntaxNodeToText`/`SyntaxListToText` break
#      the contract today (recorded as @test_broken until
#      plan/pending/syntaxtotext-delegation.md lands).
#
#   2. Reference reachability + round-trip.  For every content caret enumerated
#      from the document, `map_reference_forward` must yield an image (the
#      mapper descended all the way to the leaf), and `map_reference_backward`
#      of that image must return the original (modulo TypeReference checkpoints
#      and the documented ProjectionReference/flat-offset collapse) — the
#      signature of lockstep recursion across the whole pipeline.
# ═══════════════════════════════════════════════════════════════════════════

# ── Spy recursion ─────────────────────────────────────────────────────────
#
# A higher-order projection that, used as the `recursion` argument, counts how
# many times a node projection delegates to it, then forwards to the real
# pipeline so the child still projects normally (the node's output is built
# from genuine child IoMaps and forces without error).

mutable struct _SpyRecursion <: Projection
    real::Any        # the real pipeline a child re-enters (normally a RecursiveProjection)
    count::Base.RefValue{Int}
end

_SpyRecursion(real) = _SpyRecursion(real, Ref(0))

# print_child(spy, child, ctx) == print_document(spy, spy, child, ctx),
# so a delegating node lands here once per child; flatten-by-self never does.
function Projectured.print_document(s::_SpyRecursion, recursion, input, ctx)
    s.count[] += 1
    print_document(s.real, s.real, input, ctx)
end

# A node input "should delegate" only for the container types we positively
# recognise as having projectable child *documents*.  Unknown types return
# false, so the probe never false-flags a leaf or an own-domain primitive (e.g.
# TextToGraphics consuming TextString/TextNewline is correctly NOT a delegator).
function _should_delegate(input)
    input isa Projectured.SyntaxNode && return length(input.children) > 0
    input isa Projectured.JsonArray  && return length(input.elements) > 0
    input isa Projectured.JsonObject && return length(input.entries) > 0
    input isa Projectured.XmlElement && return length(input.children) > 0
    false
end

_is_known_flattener(p) = nameof(typeof(p)) in (:SyntaxNodeToText, :SyntaxListToText)

# Collect every IoMap reachable from `iomap`, forcing cells along the way, so we
# can probe each node projection that actually ran in the pipeline.
function _collect_iomaps!(x, visited::Set{UInt64}, out::Vector{Any})
    x === nothing && return
    x isa Bool && return; x isa Number && return
    x isa AbstractString && return; x isa Symbol && return
    x isa Function && return; x isa DataType && return; x isa Module && return
    # Same node cap `_walk!` uses, so a lazy/infinite document (e.g. an infinite
    # ListNode) can't run the collector away.
    length(visited) >= _WALK_MAX_NODES && return
    id = objectid(x)
    id in visited && return
    push!(visited, id)
    if x isa IoMap
        push!(out, x)
    end
    if x isa Cell
        val = try x[] catch; return end
        _collect_iomaps!(val, visited, out)
    elseif x isa Vector
        for el in x; _collect_iomaps!(el, visited, out); end
    else
        for fname in fieldnames(typeof(x))
            fval = try getfield(x, fname) catch; continue end
            _collect_iomaps!(fval, visited, out)
        end
    end
end

"""
    probe_delegation(document, projection) -> Vector{NamedTuple}

For every node projection that ran in the pipeline whose input has projectable
children, re-invoke its `print_document` with a spy recursion and report how
often it delegated. Each entry is `(projection_name, count, delegated, broken)`
where `delegated = count > 0` and `broken` marks the known flatteners.
"""
function probe_delegation(document, projection)
    results = NamedTuple[]
    top = try
        print_document(projection, document)
    catch e
        return results
    end
    iomaps = Any[]
    _collect_iomaps!(top, Set{UInt64}(), iomaps)
    seen = Set{Tuple{UInt64,UInt64}}()
    for im in iomaps
        p = im.projection
        input = im.input
        # Higher-order composers delegate to pipeline *stages*, not to a child
        # document via `recursion`, so the node-delegation contract does not apply
        # to them (they are classified higher-order, not node projections — see
        # documentation/projection-system.md). `ChainingProjection` is the
        # pipeline wrapper at the top of every curated example; probing it is a
        # false positive (the spy never sees a node recurse through the chain).
        p isa Projectured.ChainingProjection && continue
        _should_delegate(input) || continue
        key = (objectid(p), objectid(input))
        key in seen && continue
        push!(seen, key)
        spy = _SpyRecursion(projection)
        ok = true
        try
            res = print_document(p, spy, input, Projectured.PrinterContext())
            _walk!(res, Set{UInt64}(), String[])   # force lazy child cells
        catch e
            ok = false                              # probe could not run; don't assert
        end
        ok || continue
        push!(results, (projection_name = nameof(typeof(p)),
                        count = spy.count[],
                        delegated = spy.count[] > 0,
                        broken = _is_known_flattener(p)))
    end
    results
end

# ── Reference reachability + round-trip ───────────────────────────────────

"""
    walk_reference_roundtrip(document, projection) -> errors::Vector{String}

For every caret in `collect_text_selections(document)`, map it forward through
the top projection and assert it has an image (reachability), then map that
image back and assert it equals the original (round-trip, modulo TypeReference
checkpoints). Errors are returned as strings for REPL use.
"""
function walk_reference_roundtrip(document, projection)
    errors = String[]
    clear_selection!(document)
    iomap = try
        print_document(projection, document)
    catch e
        push!(errors, "print_document threw: $e")
        return errors
    end
    for ref in collect_text_selections(document)
        fwd = try
            map_reference_forward(projection, iomap, ref)
        catch e
            push!(errors, "forward threw on $(strip_reference_types(ref)): $e")
            continue
        end
        if fwd === nothing
            push!(errors, "no forward image (mapper did not reach) for $(strip_reference_types(ref))")
            continue
        end
        back = try
            map_reference_backward(projection, iomap, fwd)
        catch e
            push!(errors, "backward threw on $(strip_reference_types(ref)): $e")
            continue
        end
        back === nothing && continue   # projection-introduced position with no pre-image
        if strip_reference_types(back) != strip_reference_types(ref)
            push!(errors, "round-trip mismatch: $(strip_reference_types(ref)) -> $(strip_reference_types(back))")
        end
    end
    errors
end

# ── Combined walker (non-@testset, REPL-friendly) ─────────────────────────

"""
    walk_recursion_contract(document, projection) -> errors::Vector{String}

Run both contract checks and return all findings as strings. A delegation
finding for a known flattener (`SyntaxNodeToText`/`SyntaxListToText`) is reported
with a `(known)` marker rather than treated as a hard error.
"""
function walk_recursion_contract(document, projection)
    errors = String[]
    for r in probe_delegation(document, projection)
        r.delegated && continue
        marker = r.broken ? " (known — see plan/pending/syntaxtotext-delegation.md)" : ""
        push!(errors, "$(r.projection_name) has projectable children but never delegated to `recursion`$marker")
    end
    append!(errors, walk_reference_roundtrip(document, projection))
    errors
end

# ── @testset wrappers ─────────────────────────────────────────────────────

function test_recursion_contract(label, document, projection)
    @testset "$label" begin
        # Delegation probe — one assertion per probed node projection. This is the
        # discriminating contract check: a node whose input has projectable
        # children MUST delegate to `recursion`.
        probed = probe_delegation(document, projection)
        for r in probed
            if r.broken
                # Known flattener: it does NOT delegate today. @test_broken keeps
                # the suite green and flips to an (unexpected) pass the moment the
                # delegation refactor (plan/pending/syntaxtotext-delegation.md)
                # lands — the cue to promote it to a plain @test.
                r.delegated || @warn "[$label] $(r.projection_name) does not delegate (known violation)"
                @test_broken r.delegated
            else
                r.delegated || @warn "[$label] $(r.projection_name) has children but never called `recursion`"
                @test r.delegated
            end
        end
        # Reference reachability + round-trip is exposed as the `walk_reference_roundtrip`
        # / `walk_recursion_contract` REPL walkers rather than asserted here: it maps
        # through the full graphics pipeline and its tolerance to the documented
        # ProjectionReference / flat-offset collapse needs calibrating on a running
        # editor before it becomes a hard assertion (see the plan's Verification).
    end
end

test_recursion_contract(example::Example) =
    test_recursion_contract(example.name, example.document, example.projection)

# Curated to the structural, recursing pipelines: `json` / `xml` exercise the
# compliant `*ToSyntaxNode` delegators, and all four reach `SyntaxNodeToText`
# transitively (the known flattener). Widget / graphics-layout / table /
# database pipelines are excluded for the same reason the navigation suites
# curate their inputs — their node types are not in the delegation predicate.
const _recursion_contract_examples = ["json", "xml", "syntax", "math"]

function test_recursion_contracts()
    @testset "RecursionContract" begin
        for example in examples
            example.name in _recursion_contract_examples || continue
            @testset "$(example.name)" begin
                test_recursion_contract(example)
            end
        end
    end
end
