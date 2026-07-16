# ═══════════════════════════════════════════════════════════════════════════
# domain-test/editor/ConstructTest.jl
#
# Live example construction test — the driving engine (domain tier) and the JSON
# scalar cases (Phase 1). See plan/pending/live-example-construction.md.
#
# The oracle (`compare_content`) lives in ProjecturedKernelTest (kernel tier); it
# needs only kernel primitives. The *engine* lives here because it needs the
# `@domain` seed machinery (`nothing_document` / `domain_insertion`, base tier)
# and drives real domain examples.
#
# Phase 1 — leaf reconstruction by print-then-type:
#   1. seed   = the domain's empty placeholder, `nothing_document(domain_insertion(T))()`
#   2. surface = the target rendered to plain text (swap the projection's graphics
#      terminal for `RecursiveProjection(TextToString())`) — the keystrokes to type
#   3. drive   = set the ∅ (whole-element) selection, then feed each surface
#      character through the real `read_intent → evaluate_operation` loop, exactly
#      as the editor would (a mutable holder catches whole-root swaps like
#      JsonNothing → JsonNumber)
#   4. compare = `compare_content` (strict: 42 ≠ 42.0)
#
# The test drives purely by typing; it never works around a domain reader. Where
# reconstruction diverges, that is a *revealed* bug (a `@test_broken` with the
# reason), not something this file patches.
# ═══════════════════════════════════════════════════════════════════════════

using ProjecturedKernel.ReferenceModule: EmptyReferencePath
using ProjecturedKernel.SelectionModule: set_selection!, clear_selection!
using ProjecturedKernel.OperationModule: evaluate_operation
using ProjecturedKernel.EventModule: KeyPress
using ProjecturedKernel.ProjectionApiModule: print_document, read_intent
using ProjecturedKernel.CellModule: Cell
using ProjecturedBase.ChainingProjectionModule: ChainingProjection
using ProjecturedBase.RecursiveProjectionModule: RecursiveProjection
using ProjecturedVisual.TextToStringModule: TextToString
using ProjecturedBase.DomainModule: nothing_document, domain_insertion
using ProjecturedDomain.JsonModule: JsonNull, JsonBool, JsonNumber, JsonString

# A mutable stand-in for the editor: construction repeatedly swaps the whole root
# (JsonNothing → JsonInsertion/JsonNumber/…), so — like ReplTest's `_ReplEditor` —
# the holder must let `evaluate_operation` rebind `.document`, and we re-read it.
mutable struct _ConstructEditor
    document::Any
    iomap::Any
end

# ── seed ─────────────────────────────────────────────────────────────────────
# The empty placeholder to build `target` up from. `domain_insertion(T)` is
# defined for every document type of a `@domain` (→ its `*Insertion`), and
# `nothing_document(*Insertion)` is its `*Nothing`.
function construct_seed(target)
    ins = domain_insertion(typeof(target))
    ins === nothing && error("no @domain insertion for $(typeof(target)); cannot seed")
    nothing_document(ins)()
end

# ── surface (the keystrokes) ─────────────────────────────────────────────────
# The plain text the projection renders `target` as — which is exactly the
# sequence of characters that authors it. Reuse the example projection's own
# domain→syntax→text stages and replace its graphics terminal with a text→String
# terminal, so the surface matches what the editor shows on screen.
function construct_surface(target, projection)
    projection isa ChainingProjection ||
        error("construct_surface needs a ChainingProjection, got $(typeof(projection))")
    text_projection = ChainingProjection(projection.projections[1:end-1]...,
                                         RecursiveProjection(TextToString()))
    iomap = print_document(text_projection, target)
    out = iomap.output
    out isa Cell ? out[] : out
end

# ── drive ────────────────────────────────────────────────────────────────────
"""
    reconstruct(target, projection) -> document

Build a fresh document that equals `target` in content by starting from the
domain's empty placeholder and typing `target`'s rendered surface through the
real reader loop. Returns the document reached (which the caller compares against
`target` with `compare_content`).

A keystroke that the reader declines (`nothing`) or that throws is skipped — the
result then simply diverges from `target`, which the oracle reports. Nothing here
compensates for a broken reader.
"""
function reconstruct(target, projection)
    doc = construct_seed(target)
    clear_selection!(doc)
    set_selection!(doc, EmptyReferencePath())          # ∅ whole-element selection
    ed = _ConstructEditor(doc, print_document(projection, doc))
    for ch in construct_surface(target, projection)
        op = try
            read_intent(projection, ed.iomap, KeyPress(ch))
        catch
            continue                                    # a throwing reader → skip
        end
        op === nothing && continue                      # declined
        try
            evaluate_operation(ed, op)
            ed.iomap = print_document(projection, ed.document)
        catch
            continue
        end
    end
    ed.document
end

# ── test entry points ────────────────────────────────────────────────────────
"""
    test_construct(label, target, projection; broken=false)

Reconstruct `target` from an empty seed by typing, and assert the result equals
`target` in content. `broken=true` marks a case whose divergence is a known,
revealed domain bug (documented at the call site) — do not fix the reader to make
it pass; an unexpected pass means the bug is gone.
"""
function test_construct(label, target, projection; broken::Bool=false)
    @testset "$label" begin
        reached = try
            reconstruct(target, projection)
        catch e
            @warn "[$label] reconstruct threw" exception=e
            nothing
        end
        diff = reached === nothing ? ["reconstruct threw"] : compare_content(reached, target)
        if broken
            @test_broken isempty(diff)
        else
            isempty(diff) || @warn "[$label] reconstruction diverged: $diff"
            @test isempty(diff)
        end
    end
end

"""
    test_json_construct()

Phase 1: reconstruct the JSON scalar documents from `JsonNothing` via the whole
JSON projection (the type-dispatching pipeline — the leaf-specific atom
projections cannot project the `JsonNothing` seed).

`null` / `true` / `false` reconstruct from a single keystroke. `number` and
`string` are marked broken: they expose real reader bugs the construction test is
built to reveal —
  • number: typing `4` then `2` yields `JsonNumber(42.0)` (Float64), not `42`.
  • string: after `"` opens the string, only the first content character is
    accepted; the rest are declined.
"""
function test_json_construct()
    proj = make_json_projection_example()
    @testset "json/construct" begin
        test_construct("json/null",  JsonNull(),      proj)
        test_construct("json/true",  JsonBool(true),  proj)
        test_construct("json/false", JsonBool(false), proj)
        # @broken: revealed reader bug — digit typing produces a Float64 value.
        test_construct("json/number", JsonNumber(42), proj; broken=true)
        # @broken: revealed reader bug — string insertion drops all but the first char.
        test_construct("json/string", JsonString("Hello, world"), proj; broken=true)
    end
end
