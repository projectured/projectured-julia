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
using ProjecturedKernel.DocumentModule: Document, is_element_collection, is_opaque
using ProjecturedKernel.CellModule: unwrap_cell
using ProjecturedKernel.ReferenceModule: append_reference, FieldReference, ElementReference
using ProjecturedBase.CollectionModule: CellVector
using ProjecturedDomain.JsonModule: JsonNull, JsonBool, JsonNumber, JsonString, JsonArray

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
# Feed one keystroke through the real reader loop. Returns whether it produced and
# applied an operation. A declined (`nothing`) or throwing keystroke is a no-op —
# the reconstruction then simply diverges from the target, which the oracle
# reports; nothing here compensates for a broken reader.
function _feed!(ed, projection, ch)
    op = try
        read_intent(projection, ed.iomap, KeyPress(ch))
    catch
        return false
    end
    op === nothing && return false
    try
        evaluate_operation(ed, op)
        ed.iomap = print_document(projection, ed.document)
    catch
        return false
    end
    true
end

# Place the ∅ (whole-element) selection at `path` in the current document.
function _select!(ed, projection, path)
    clear_selection!(ed.document)
    set_selection!(ed.document, path)
    ed.iomap = print_document(projection, ed.document)
end

# The direct `Document` children of `node` (reached at `node_path`), each as
# `(child_path, child)`. Mirrors the canonical document walk: a struct descends
# its fields; a field that is itself a positional collection contributes its
# elements. Scalar fields (a number, a string key) are *content* — typed as part
# of the node's own surface — not children.
function _document_child_slots(node, node_path)
    slots = Tuple{Any,Any}[]
    (node isa Document && !is_opaque(node)) || return slots
    for fname in fieldnames(typeof(node))
        (fname === :selection || fname === :ref) && continue
        fv = unwrap_cell(getfield(node, fname))
        fpath = append_reference(node_path, FieldReference(string(fname)))
        # Collection first: a `CellVector` is itself a `Document`, so its elements
        # (not the container) are the children — the container is addressed by
        # `[i]`, never projected on its own.
        if fv isa CellVector || is_element_collection(fv) || fv isa AbstractVector
            for i in 1:length(fv)
                el = unwrap_cell(fv[i])
                el isa Document && push!(slots, (append_reference(fpath, ElementReference(i)), el))
            end
        elseif fv isa Document
            push!(slots, (fpath, fv))
        end
    end
    slots
end

# Recursively build `target` at `path`. A leaf (no `Document` children) is typed
# as its whole rendered surface. A container is created by the *first* character
# of its surface — the kind-selecting keystroke (`[`, `{`, a digit, `"`, `n`/`t`/`f`)
# — after which its children are filled by navigating to each child slot and
# recursing. (Multi-child sequences need a per-domain "append element" gesture
# between children; the current catalog atoms hold a single child, so that grow
# step is deferred — see the plan.)
function construct_node!(ed, projection, target, path)
    _select!(ed, projection, path)
    slots = _document_child_slots(target, path)
    if isempty(slots)                                   # leaf: type the whole surface
        for ch in construct_surface(target, projection)
            _feed!(ed, projection, ch)
        end
        return
    end
    surf = construct_surface(target, projection)        # container: type only the
    isempty(surf) || _feed!(ed, projection, first(surf))# first (kind-creating) char
    for (childpath, child) in slots
        construct_node!(ed, projection, child, childpath)
    end
end

"""
    reconstruct(target, projection) -> document

Build a fresh document that equals `target` in content by starting from the
domain's empty placeholder and driving the editor's real gestures: leaves are
typed as their rendered surface, containers are created by their kind-selecting
keystroke and then filled child by child (navigating to each child slot with a
programmatic ∅ selection). Returns the document reached — the caller compares it
against `target` with `compare_content`. Nothing here works around a broken
reader; a divergence is reported, not patched.
"""
function reconstruct(target, projection)
    doc = construct_seed(target)
    ed = _ConstructEditor(doc, print_document(projection, doc))
    construct_node!(ed, projection, target, EmptyReferencePath())
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

Reconstruct JSON documents from `JsonNothing` via the whole JSON projection (the
type-dispatching pipeline — the leaf-specific atom projections cannot project the
`JsonNothing` seed).

Phase 1 — scalar leaves: `null` / `true` / `false` reconstruct from a single
keystroke. `number` and `string` are marked broken — they expose real reader bugs
the construction test is built to reveal:
  • number: typing `4` then `2` yields `JsonNumber(42.0)` (Float64), not `42`.
  • string: after `"` opens the string, only the first content char is accepted.

Phase 2 — element-collection containers: an array is created by `[`, then each
element slot is navigated to and its child reconstructed. Single-digit / boolean
children reconstruct exactly (nested arrays too); the `number`/`string` reader
bugs above still bite an array whose child is a multi-digit number or a string.
Object entries (a record node with a string key beside a document value) are
Phase 3 — the current planner has no key-typing step for them.
"""
function test_json_construct()
    proj = make_json_projection_example()
    @testset "json/construct" begin
        # Phase 1 — scalar leaves
        test_construct("json/null",  JsonNull(),      proj)
        test_construct("json/true",  JsonBool(true),  proj)
        test_construct("json/false", JsonBool(false), proj)
        # @broken: revealed reader bug — digit typing produces a Float64 value.
        test_construct("json/number", JsonNumber(42), proj; broken=true)
        # @broken: revealed reader bug — string insertion drops all but the first char.
        test_construct("json/string", JsonString("Hello, world"), proj; broken=true)

        # Phase 2 — element-collection containers
        test_construct("json/array",        JsonArray(JsonNumber(1)),            proj)
        test_construct("json/array-bool",   JsonArray(JsonBool(true)),           proj)
        test_construct("json/array-nested", JsonArray(JsonArray(JsonNumber(1))), proj)
    end
end
