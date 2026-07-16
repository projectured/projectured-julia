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
using ProjecturedVisual.SyntaxModule: SyntaxLeaf
using ProjecturedBase.DomainModule: nothing_document, domain_insertion, insertion_root
using ProjecturedKernel.DocumentModule: Document, is_element_collection, is_opaque
using ProjecturedKernel.CellModule: unwrap_cell
using ProjecturedKernel.ReferenceModule: append_reference, FieldReference, ElementReference,
                                         try_evaluate_reference
using ProjecturedBase.CollectionModule: CellVector
using ProjecturedDomain.JsonModule: JsonNull, JsonBool, JsonNumber, JsonString, JsonArray,
                                    JsonObject, JsonObjectEntry, JsonInsertion

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
    # A placeholder insertion buffer (a `*Insertion`, whose `insertion_root` is overridden
    # away from the default `Document`) is authored as itself — there is no completed
    # document to build up to, so a fresh one of its own type is the whole reconstruction.
    insertion_root(typeof(target)) !== Document && return Base.typename(typeof(target)).wrapper()
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

# The fillable slots of `node` (reached at `node_path`), in field order — one of:
#   (:scalar,  fpath, fname, target_value)   a content scalar (a record's key), typed in place
#   (:document, fpath, target_child)          a `Document` child, built by recursion
#   (:element, epath, target_elem, i)         one element (1-based `i`) of a collection field
# Chrome fields (`:selection` / `:ref` / `:collapsed`) are skipped. Mirrors the canonical
# document walk: a struct descends its fields; a positional collection contributes its
# elements (a `CellVector` is itself a `Document`, so its elements — not the container — are
# the children). A leaf's own scalar `value` is *also* returned as a `:scalar` slot, but a
# leaf is recognised by having no `:document` / `:element` slot and is typed as its surface
# instead (see `_has_child_field`).
function _node_slots(node, node_path)
    slots = Any[]
    (node isa Document && !is_opaque(node)) || return slots
    for fname in fieldnames(typeof(node))
        (fname === :selection || fname === :ref || fname === :collapsed) && continue
        fv = unwrap_cell(getfield(node, fname))
        fpath = append_reference(node_path, FieldReference(string(fname)))
        if fv isa CellVector || is_element_collection(fv) || fv isa AbstractVector
            for i in 1:length(fv)
                el = unwrap_cell(fv[i])
                el isa Document && push!(slots, (:element, append_reference(fpath, ElementReference(i)), el, i))
            end
        elseif fv isa Document
            push!(slots, (:document, fpath, fv))
        else
            push!(slots, (:scalar, fpath, fname, fv))
        end
    end
    slots
end

# A node is a container/record (built by a create keystroke then filled) when it has any
# `Document` child or collection field — structurally, even when the collection is
# momentarily empty; otherwise it is a leaf, typed as its authoring surface.
_has_child_field(node) =
    (node isa Document && !is_opaque(node)) && any(fieldnames(typeof(node))) do fname
        (fname === :selection || fname === :ref || fname === :collapsed) && return false
        fv = unwrap_cell(getfield(node, fname))
        fv isa CellVector || is_element_collection(fv) || fv isa AbstractVector || fv isa Document
    end

# A delimited leaf renders `open value close`, but an author types only the opening
# delimiter (which creates the leaf) and the value — the projection supplies the
# closing delimiter as chrome, exactly as a container's `]` / `}` is never typed.
# Ask the domain→syntax stage for the leaf's `close` span and drop it from the surface,
# so reconstruction types only the keystrokes an author would (an undelimited leaf — a
# number, `null`, a boolean — keeps its whole surface).
function _leaf_authoring_surface(target, projection)
    surf = construct_surface(target, projection)
    leaf = try
        out = print_document(projection.projections[1], target).output
        out isa Cell ? out[] : out
    catch
        return surf
    end
    (leaf isa SyntaxLeaf && leaf.close !== nothing) || return surf
    close = string(leaf.close.content)
    (isempty(close) || !endswith(surf, close)) ? surf : chop(surf; tail = length(close))
end

# Recursively build `target` at `path`, driving the editor's real gestures. A slot that
# already matches the target (an insertion the create keystroke left in place) is skipped.
# A leaf is typed as its authoring surface (rendered form minus closing-delimiter chrome).
# A container/record is created by the first (kind-selecting) char of its surface, then
# each slot is filled (see `_fill_slot!`).
function construct_node!(ed, projection, target, path)
    current = try_evaluate_reference(ed.document, path)
    current !== nothing && isempty(compare_content(current, target)) && return
    _select!(ed, projection, path)
    if !_has_child_field(target)                        # leaf: type its authoring surface
        for ch in _leaf_authoring_surface(target, projection)
            _feed!(ed, projection, ch)
        end
        return
    end
    surf = construct_surface(target, projection)        # container: type only the first
    isempty(surf) || _feed!(ed, projection, first(surf))# (kind-creating) char
    for slot in _node_slots(target, path)
        _fill_slot!(ed, projection, path, slot)
    end
end

# Fill one slot of the container reached at `container_path`.
function _fill_slot!(ed, projection, container_path, slot)
    if slot[1] === :scalar
        _fill_scalar!(ed, projection, slot[4])
    elseif slot[1] === :document
        construct_node!(ed, projection, slot[3], slot[2])
    elseif slot[1] === :element
        _, epath, elem, i = slot
        if i > 1
            # Grow: a fresh element/entry is appended by the container's own gesture (`,`).
            # Feed it with the WHOLE container selected so it reaches the container's
            # `@gestures` — a caret inside a filled leaf would swallow the key as text.
            _select!(ed, projection, container_path)
            _feed!(ed, projection, ',')
        end
        _fill_element!(ed, projection, elem, epath)
    end
end

# An element is either a record — a scalar key beside a `Document` value (a JSON object
# entry), pre-created by the container's `{` / `,` with the caret already at its key — whose
# key is typed and value recursed, or a plain `Document` placeholder built by recursion.
function _fill_element!(ed, projection, elem, epath)
    eslots  = _node_slots(elem, epath)
    scalars = filter(s -> s[1] === :scalar,   eslots)
    docs    = filter(s -> s[1] === :document, eslots)
    if !isempty(scalars) && !isempty(docs)              # record: key(s) then value(s)
        for s in scalars; _fill_scalar!(ed, projection, s[4]); end
        for s in docs;    construct_node!(ed, projection, s[3], s[2]); end
    else
        construct_node!(ed, projection, elem, epath)    # plain placeholder element
    end
end

# Type a content scalar (a record's key) at the caret the create/grow gesture left in it
# (an entry opens at `key{0}`). Only string scalars are authored by typing; a non-string
# content scalar would need a per-kind gesture (none occur among JSON keys).
function _fill_scalar!(ed, projection, value)
    value isa AbstractString || return
    for ch in value
        _feed!(ed, projection, ch)
    end
end

"""
    reconstruct(target, projection) -> document

Build a fresh document that equals `target` in content by starting from the domain's
empty placeholder and driving the editor's real gestures: a leaf types its authoring
surface; a container is created by its kind-selecting keystroke and filled slot by slot —
each `Document` child recursed (reached with a programmatic ∅ selection), a second-or-later
collection element grown first with the container's append gesture, and a record entry's
key typed in place before its value is recursed. Returns the document reached — the caller
compares it against `target` with `compare_content`. Nothing here works around a broken
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

Reconstruct every JSON document from its empty seed by typing, through the whole JSON
projection (the type-dispatching pipeline — the leaf-specific atom projections cannot
project the `JsonNothing` seed), and assert each equals its target in content. This is
the reachability proof for the JSON domain: every document in the corpus is authorable
through the editor's own gestures, from nothing.

- **Scalar leaves** (`null` / `true` / `false` / a number / a string) type their
  authoring surface: one kind-selecting keystroke for the literals, digit-by-digit for a
  number (which stays an integer), and `"` then the content for a string (the closing
  quote is projection chrome, so it is not typed).
- **Element collections** (arrays) are created by `[`, then each element is navigated to
  and reconstructed; a second-or-later element is grown with the `,` gesture first.
- **Record collections** (objects) are created by `{`; each entry's quoted key is typed
  at the caret the create/grow leaves in it and its value recursed; a second-or-later
  entry is grown with `,`. An entry whose value stays a `JsonInsertion` placeholder is
  left as created.
- The full nested `make_json_document_example()` exercises all of the above at once.

Known authoring gaps (not reader bugs) are marked `@test_broken`: a *truly empty* array
or object (`[]` / `{}`) is unreachable because creation always leaves one placeholder
child and the JSON domain has no element-delete gesture to remove it.
"""
function test_json_construct()
    proj = make_json_projection_example()
    @testset "json/construct" begin
        # Scalar leaves
        test_construct("json/null",   JsonNull(),                 proj)
        test_construct("json/true",   JsonBool(true),             proj)
        test_construct("json/false",  JsonBool(false),            proj)
        test_construct("json/number", JsonNumber(42),             proj)
        test_construct("json/string", JsonString("Hello, world"), proj)

        # Element collections (arrays), including multi-element grow and nesting
        test_construct("json/array",        JsonArray(JsonNumber(1)),                     proj)
        test_construct("json/array-bool",   JsonArray(JsonBool(true)),                    proj)
        test_construct("json/array-nested", JsonArray(JsonArray(JsonNumber(1))),          proj)
        test_construct("json/array-string", JsonArray(JsonString("ab")),                  proj)
        test_construct("json/array-2",      JsonArray(JsonNumber(1), JsonNumber(2)),      proj)
        test_construct("json/array-3",      JsonArray(JsonNumber(1), JsonNumber(2), JsonNumber(3)), proj)
        test_construct("json/array-2str",   JsonArray(JsonString("a"), JsonString("b")),  proj)

        # Record collections (objects): keyed entries, multi-entry grow, nesting
        test_construct("json/obj-1",        JsonObject("a" => JsonNumber(1)),             proj)
        test_construct("json/obj-2",        JsonObject("a" => JsonNumber(1), "b" => JsonNumber(2)), proj)
        test_construct("json/obj-str",      JsonObject("name" => JsonString("Alice")),    proj)
        test_construct("json/obj-nested",   JsonObject("addr" => JsonObject("city" => JsonString("W"))), proj)
        test_construct("json/obj-insert",   JsonObject("ph" => JsonInsertion()),          proj)

        # The catalog example documents end to end: the empty insertion buffer, and the
        # full nested object (objects / arrays / strings / numbers / bools / a placeholder
        # entry, all at once). The scalar/string catalog docs are the inline cases above.
        test_construct("json/doc-insertion", make_json_insertion_document_example(), proj)
        test_construct("json/doc-main",      make_json_document_example(),           proj)

        # @broken: authoring gap — an empty [] / {} is unreachable by typing (creation
        # leaves one placeholder child and JSON has no element-delete gesture).
        test_construct("json/array-empty", JsonArray(), proj; broken=true)
        test_construct("json/obj-empty",   JsonObject(), proj; broken=true)
    end
end
