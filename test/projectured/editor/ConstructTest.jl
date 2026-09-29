# ═══════════════════════════════════════════════════════════════════════════
# domain-test/editor/ConstructTest.jl
#
# Live example construction test — the driving engine (domain tier) and the JSON
# scalar cases (Phase 1). See plan/pending/live-example-construction.md.
#
# The oracle (`compare_content`) lives in ProjecturedKernelTest (kernel tier); it
# needs only kernel primitives. The *engine* lives here because it needs the
# `@domain` seed machinery (`get_nothing_document` / `get_domain_insertion`, base tier)
# and drives real domain examples.
#
# Phase 1 — leaf reconstruction by print-then-type:
#   1. seed   = the domain's empty placeholder, `get_nothing_document(get_domain_insertion(T))()`
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

using ProjecturedKernel.ReferenceModule: EmptyReference
using ProjecturedKernel.SelectionModule: set_selection!, clear_selection!
using ProjecturedKernel.OperationModule: evaluate_operation
using ProjecturedKernel.EventModule: KeyPress, KeyDown, ModifierKeys
using ProjecturedKernel.GestureBindingModule: get_document_gesture_bindings
using ProjecturedKernel.GestureModule: GesturePattern
using ProjecturedKernel.ProjectionModule: print_document, read_intent
using ProjecturedKernel.CellModule: Cell, Computation
using ProjecturedProjection.ProjectionAlgebraModule: ChainingProjection
using ProjecturedProjection.ProjectionAlgebraModule: RecursiveProjection
using ProjecturedText.TextModule: TextToString
using ProjecturedSyntax.SyntaxModule: SyntaxLeaf
using ProjecturedDomain.DomainModule: get_nothing_document, get_domain_insertion, get_insertion_root
using ProjecturedKernel.DocumentModule: Document, is_element_collection, is_walk_opaque, is_view_state_field
using ProjecturedKernel.CellModule: unwrap_cell
using ProjecturedKernel.ReferenceModule: extend_reference, FieldReferenceStep, ElementReferenceStep,
                                         try_evaluate_reference, PositionReferenceStep,
                                         annotate_reference_types
using ProjecturedCollection.CollectionModule: CellVector
using ProjecturedJson.JsonModule: JsonNull, JsonBool, JsonNumber, JsonString, JsonArray,
                                    JsonObject, JsonObjectEntry, JsonInsertion
using ProjecturedYaml.YamlModule: YamlNull, YamlBool, YamlNumber, YamlString, YamlSequence,
                                    YamlMapping, YamlMappingEntry, YamlInsertion
using ProjecturedXml.XmlModule: XmlElement, XmlAttribute, XmlText, XmlInsertion

# A mutable stand-in for the editor: construction repeatedly swaps the whole root
# (JsonNothing → JsonInsertion/JsonNumber/…), so — like ReplTest's `_ReplEditor` —
# the holder must let `evaluate_operation` rebind `.document`, and we re-read it.
mutable struct _ConstructEditor
    document::Any
    iomap::Any
end

# ── seed ─────────────────────────────────────────────────────────────────────
# The empty placeholder to build `target` up from. `get_domain_insertion(T)` is
# defined for every document type of a `@domain` (→ its `*Insertion`), and
# `get_nothing_document(*Insertion)` is its `*Nothing`.
function construct_seed(target)
    # A placeholder insertion buffer (a `*Insertion`, whose `get_insertion_root` is overridden
    # away from the default `Document`) is authored as itself — there is no completed
    # document to build up to, so a fresh one of its own type is the whole reconstruction.
    get_insertion_root(typeof(target)) !== Document && return Base.typename(typeof(target)).wrapper()
    ins = get_domain_insertion(typeof(target))
    ins === nothing && error("no @domain insertion for $(typeof(target)); cannot seed")
    get_nothing_document(ins)()
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
# Feed one event (a keystroke or a `KeyDown`) through the real reader loop. Returns
# whether it produced and applied an operation. A declined (`nothing`) or throwing event
# is a no-op — the reconstruction then simply diverges from the target, which the oracle
# reports; nothing here compensates for a broken reader.
function _feed_event!(ed, projection, event)
    op = try
        read_intent(projection, ed.iomap, event)
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

_feed!(ed, projection, ch::Char) = _feed_event!(ed, projection, KeyPress(ch; time = 0.0))

# A concrete event synthesised from a gesture pattern — a `KeyPress` char, or a `KeyDown`
# key with its modifiers. `nothing` for a pattern with no fixed key (an unconstrained
# `KeyPress(c) when isdigit(c)`, a mouse pattern).
_mods(::Nothing) = ModifierKeys()
_mods(v::Vector{Symbol}) =
    ModifierKeys(ctrl = :ctrl in v, shift = :shift in v, alt = :alt in v, meta = :meta in v)

function _synth_event(pattern)
    pattern isa GesturePattern || return nothing
    haskey(pattern.fields, :char) && return KeyPress(pattern.fields.char; time = 0.0)
    haskey(pattern.fields, :key)  && return KeyDown(pattern.fields.key, _mods(pattern.modifiers); time = 0.0)
    nothing
end

# Place the ∅ (whole-element) selection at `path` in the current document.
function _select!(ed, projection, path)
    clear_selection!(ed.document)
    set_selection!(ed.document, path)
    ed.iomap = print_document(projection, ed.document)
end

# The fillable slots of `node` (reached at `node_path`), in field order — one of:
#   (:scalar,  fpath, fname, target_value)          a content scalar (a key / tag / name), typed
#   (:document, fpath, target_child)                 a `Document` child, built by recursion
#   (:element, epath, target_elem, i, coll_field)    element `i` of collection field `coll_field`
# Chrome fields (`:selection` / `:ref` / `:collapsed`) are skipped. Mirrors the canonical
# document walk: a struct descends its fields; a positional collection contributes its
# elements (a `CellVector` is itself a `Document`, so its elements — not the container — are
# the children). A leaf's own scalar `value` is *also* returned as a `:scalar` slot, but a
# leaf is recognised by having no `:document` / `:element` slot and at most one scalar (see
# `construct_node!`); a node with several scalars is a record (an XML attribute's name+value).
function _node_slots(node, node_path)
    slots = Any[]
    (node isa Document && !is_walk_opaque(node)) || return slots
    for fname in fieldnames(typeof(node))
        (is_view_state_field(fname) || fname === :ref || fname === :collapsed) && continue
        fv = unwrap_cell(getfield(node, fname))
        fpath = extend_reference(node_path, FieldReferenceStep(string(fname)))
        if fv isa CellVector || is_element_collection(fv) || fv isa AbstractVector
            for i in 1:length(fv)
                el = unwrap_cell(fv[i])
                el isa Document && push!(slots, (:element, extend_reference(fpath, ElementReferenceStep(i)), el, i, fname))
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
    (node isa Document && !is_walk_opaque(node)) && any(fieldnames(typeof(node))) do fname
        (is_view_state_field(fname) || fname === :ref || fname === :collapsed) && return false
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

# The constrained character of a `KeyPress` gesture pattern (`nothing` for a `KeyDown`,
# or an unconstrained `KeyPress(c) when isdigit(c)`).
_keypress_char(pat) = (pat isa GesturePattern && haskey(pat.fields, :char)) ? pat.fields.char : nothing

# The single keystroke that turns this domain's empty placeholder into a document of
# `target`'s kind — discovered by trying each character the placeholder's create gestures
# offer and keeping the one that produces the right kind, cached per (placeholder-kind,
# target-kind) so each kind is probed once. Needed because the create keystroke is *not*
# always the first character of the rendered surface: a JSON string opens with `"` (which
# both creates it and is its delimiter), but a YAML string is unquoted (create key `"`,
# surface starts with content) and a YAML sequence renders `[…]` yet is created by `-`.
# `nothing` when no single key makes that kind (a completion-buffer kind would need
# Insert → type → Enter; not reached by the current corpus).
const _CREATE_KEY_CACHE = IdDict{Any,Any}()

function _create_keystroke(projection, target)
    tw = Base.typename(typeof(target)).wrapper
    seed = construct_seed(target)
    key = (Base.typename(typeof(seed)).wrapper, tw)
    haskey(_CREATE_KEY_CACHE, key) && return _CREATE_KEY_CACHE[key]
    found = nothing
    for b in get_document_gesture_bindings(typeof(seed))
        c = _keypress_char(b.pattern)
        c isa Char || continue
        scratch = construct_seed(target)
        sed = _ConstructEditor(scratch, print_document(projection, scratch))
        _select!(sed, projection, EmptyReference())
        _feed!(sed, projection, c)
        if Base.typename(typeof(sed.document)).wrapper === tw
            found = c
            break
        end
    end
    _CREATE_KEY_CACHE[key] = found
    found
end

# ── grow (append a collection element) ─────────────────────────────────────────
# JSON/YAML grow every collection with one uniform gesture (`,`, which appends an empty
# placeholder later built in place). XML grows differently per collection and child kind:
# a child element with `<` and a child text with `"` (the node created directly), an
# attribute with `KeyDown(:space)`. The event is discovered by building a fresh empty
# container and trying each event its own gestures offer plus the child's create keystroke,
# keeping the one that grows the right collection — preferring the event that lands the
# target child's kind (XML) over one that lands a placeholder (JSON/YAML). Cached per
# (container-kind, field, child-kind).
const _GROW_EVENT_CACHE = IdDict{Any,Any}()

_coll_length(container, field) = length(unwrap_cell(getproperty(container, field)))

# A freshly created, empty instance of `container`'s kind (seed + its create keystroke),
# as an editor, or `nothing` when the kind has no single-key create.
function _fresh_container(projection, container)
    ck = _create_keystroke(projection, container)
    ck === nothing && return nothing
    seed = construct_seed(container)
    ed = _ConstructEditor(seed, print_document(projection, seed))
    _select!(ed, projection, EmptyReference())
    _feed!(ed, projection, ck)
    Base.typename(typeof(ed.document)).wrapper === Base.typename(typeof(container)).wrapper ?
        ed : nothing
end

function _grow_event(projection, container, field, child)
    cw, tw = Base.typename(typeof(container)).wrapper, Base.typename(typeof(child)).wrapper
    key = (cw, field, tw)
    haskey(_GROW_EVENT_CACHE, key) && return _GROW_EVENT_CACHE[key]
    # Candidate events: the child's create keystroke, then every fixed-key gesture the
    # container offers (its `@gestures`, e.g. XML's `KeyDown(:space)` for an attribute).
    candidates = Any[]
    ck = _create_keystroke(projection, child)
    ck === nothing || push!(candidates, KeyPress(ck; time = 0.0))
    probe = _fresh_container(projection, container)
    if probe !== nothing
        for b in get_document_gesture_bindings(typeof(probe.document))
            e = _synth_event(b.pattern)
            e === nothing || push!(candidates, e)
        end
    end
    fallback = nothing
    for ev in candidates
        ed = _fresh_container(projection, container)
        ed === nothing && continue
        n0 = _coll_length(ed.document, field)
        _select!(ed, projection, EmptyReference())
        _feed_event!(ed, projection, ev)
        # The container must survive: a replace gesture the container inherits (JSON's `n`
        # turns the whole array into a `JsonNull`) destroys it rather than growing it.
        Base.typename(typeof(ed.document)).wrapper === cw || continue
        _coll_length(ed.document, field) == n0 + 1 || continue
        newel = unwrap_cell(getproperty(ed.document, field))[n0 + 1]
        if Base.typename(typeof(newel)).wrapper === tw
            _GROW_EVENT_CACHE[key] = ev            # lands the exact kind (XML)
            return ev
        elseif fallback === nothing && get_insertion_root(typeof(newel)) !== Document
            fallback = ev                          # lands a placeholder (JSON/YAML)
        end
    end
    _GROW_EVENT_CACHE[key] = fallback
    fallback
end

# ── build a node ───────────────────────────────────────────────────────────────
# Recursively build `target` at `path`, driving the editor's real gestures. A slot already
# matching the target (an insertion the create/grow left in place) is skipped. Three shapes:
#  • leaf — no child fields and at most one scalar: its create keystroke + content, the
#    create key prefixed when it is not already the surface's first char (`"` for an
#    unquoted string, `-` for a YAML sequence);
#  • record — several scalars (an XML attribute's name + value): create, then each scalar
#    navigated to and typed;
#  • container — has a `Document`/collection field: create, then each slot filled.
# The create keystroke is skipped when the slot is already the target's kind (a child a
# grow gesture built directly, an entry an object created with `{`).
function construct_node!(ed, projection, target, path)
    current = try_evaluate_reference(ed.document, path)
    current !== nothing && isempty(compare_content(current, target)) && return
    _select!(ed, projection, path)
    slots   = _node_slots(target, path)
    nscalar = count(s -> s[1] === :scalar, slots)
    already = current !== nothing &&
              Base.typename(typeof(current)).wrapper === Base.typename(typeof(target)).wrapper
    if !already && !_has_child_field(target) && nscalar <= 1
        # A fresh leaf: type its authoring surface (which encodes the value), prefixing the
        # create keystroke when it is not already the surface's first char.
        create = _create_keystroke(projection, target)
        surf   = _leaf_authoring_surface(target, projection)
        authoring = (create !== nothing && !startswith(surf, string(create))) ?
                    string(create) * surf : surf
        for ch in authoring
            _feed!(ed, projection, ch)
        end
        return
    end
    if !already                                         # create the container / record
        create = _create_keystroke(projection, target)
        if create !== nothing
            _feed!(ed, projection, create)
        else
            surf = construct_surface(target, projection)
            isempty(surf) || _feed!(ed, projection, first(surf))
        end
    end
    # Fill each slot. An already-created leaf (a node a grow gesture built directly, e.g. an
    # XML text child) reaches here too and fills its single content scalar in place.
    for slot in slots
        _fill_slot!(ed, projection, target, path, slot)
    end
end

# Fill one slot of `container` (reached at `container_path`).
function _fill_slot!(ed, projection, container, container_path, slot)
    if slot[1] === :scalar
        _fill_scalar!(ed, projection, slot[2], slot[4])
    elseif slot[1] === :document
        construct_node!(ed, projection, slot[3], slot[2])
    elseif slot[1] === :element
        _, epath, elem, i, field = slot
        if try_evaluate_reference(ed.document, epath) === nothing   # slot not yet present: grow
            ev = _grow_event(projection, container, field, elem)
            if ev !== nothing
                # Feed the grow with the WHOLE container selected so the key reaches the
                # container's `@gestures` rather than being swallowed as text by a leaf.
                _select!(ed, projection, container_path)
                _feed_event!(ed, projection, ev)
            end
        end
        construct_node!(ed, projection, elem, epath)
    end
end

# Type a content scalar (a key / tag / attribute name or value). Navigate to its start
# first: the create/grow leaves the caret at the first scalar, but a record's later scalars
# (an XML attribute's value after its name) need an explicit move. A char cursor at offset
# 0 is `<field>` + Position(0), the same shape `move_to_field` produces.
function _fill_scalar!(ed, projection, fpath, value)
    value isa AbstractString || return
    cursor = annotate_reference_types(ed.document, extend_reference(fpath, PositionReferenceStep(0)))
    _select!(ed, projection, cursor)
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
    construct_node!(ed, projection, target, EmptyReference())
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

        # From the text caret alone, with no structural selection: Right leaves a
        # string, and a `,` after a value adds the next entry. The text layer claims
        # every `,` as a character; where no step can carry that claim — on the
        # delimiter after a string, in a number — the JSON step reads the key itself.
        @testset "json/caret-only" begin
            chars(text) = [KeyPress(c; time = 0.0) for c in text]
            tab, right = KeyDown(:tab, ModifierKeys(); time = 0.0), KeyDown(:right, ModifierKeys(); time = 0.0)
            function build(events)
                seed = JsonInsertion()
                set_selection!(seed, EmptyReference())
                ed = _ConstructEditor(seed, print_document(proj, seed))
                answered = [_feed_event!(ed, proj, event) for event in events]
                (ed.document, answered)
            end
            (doc, answered) = build(vcat(
                [KeyPress('{'; time = 0.0)], chars("name"), [tab, KeyPress('"'; time = 0.0)], chars("Alice"),
                [right, KeyPress(','; time = 0.0)], chars("age"), [tab], chars("30"),
                [KeyPress(','; time = 0.0)], chars("city"), [tab, KeyPress('"'; time = 0.0)], chars("W")))
            @test all(answered)
            @test isempty(compare_content(doc, JsonObject("name" => JsonString("Alice"),
                                                          "age" => JsonNumber(30),
                                                          "city" => JsonString("W"))))
            # The caret after a nested value belongs to the nested object, which
            # printed the delimiter under it, so the `,` adds the entry there.
            (doc, answered) = build(vcat(
                [KeyPress('{'; time = 0.0)], chars("a"), [tab, KeyPress('{'; time = 0.0)], chars("b"), [tab, KeyPress('"'; time = 0.0)],
                chars("x"), [right, KeyPress(','; time = 0.0)], chars("c"), [tab], chars("1")))
            @test all(answered)
            @test isempty(compare_content(doc, JsonObject("a" => JsonObject("b" => JsonString("x"),
                                                                             "c" => JsonNumber(1)))))
            # On the closing brace of the nested object, the object declines the `,`
            # and its parent adds the entry. From `"x"│`, the four presses of Right
            # pass the end of the line and the indentation, onto the `}`.
            (doc, answered) = build(vcat(
                [KeyPress('{'; time = 0.0)], chars("a"), [tab, KeyPress('{'; time = 0.0)], chars("b"), [tab, KeyPress('"'; time = 0.0)],
                chars("x"), [right, right, right, right, KeyPress(','; time = 0.0)], chars("c"), [tab], chars("1")))
            @test all(answered)
            @test isempty(compare_content(doc, JsonObject("a" => JsonObject("b" => JsonString("x")),
                                                          "c" => JsonNumber(1))))
            # The same for an array: after the nested `]`, the outer array takes the `,`.
            (doc, answered) = build(vcat(
                [KeyPress('['; time = 0.0), KeyPress('['; time = 0.0), KeyPress('1'; time = 0.0), right, KeyPress(','; time = 0.0), KeyPress('2'; time = 0.0)]))
            @test all(answered)
            @test isempty(compare_content(doc, JsonArray(JsonArray(JsonNumber(1)), JsonNumber(2))))
        end

        # @broken: authoring gap — an empty [] / {} is unreachable by typing (creation
        # leaves one placeholder child and JSON has no element-delete gesture).
        test_construct("json/array-empty", JsonArray(), proj; broken=true)
        test_construct("json/obj-empty",   JsonObject(), proj; broken=true)
    end
end

"""
    test_yaml_construct()

Reconstruct every YAML document from its empty seed by typing. YAML is structurally the
same corpus as JSON — scalars, sequences, and keyed mappings — so it exercises the same
generic planner, but its create keystrokes differ from its rendered surface: a YAML string
is unquoted (created by `"`, surface starts with content) and a sequence renders `[…]` yet
is created by `-`. Reconstruction here is the proof that the create-keystroke *discovery*
(not "first surface char") is what drives node creation.

The same empty-container authoring gap applies (an empty sequence/mapping keeps its
placeholder child), marked `@test_broken`.
"""
function test_yaml_construct()
    proj = make_yaml_projection_example()
    @testset "yaml/construct" begin
        # Scalar leaves (the string is unquoted — create key `"` is not in the surface)
        test_construct("yaml/null",   YamlNull(),                 proj)
        test_construct("yaml/true",   YamlBool(true),             proj)
        test_construct("yaml/false",  YamlBool(false),            proj)
        test_construct("yaml/number", YamlNumber(42),             proj)
        test_construct("yaml/string", YamlString("Hello, world"), proj)

        # Sequences (created by `-`), including multi-element grow and nesting
        test_construct("yaml/seq-1",      YamlSequence(YamlNumber(1)),                          proj)
        test_construct("yaml/seq-3",      YamlSequence(YamlNumber(1), YamlNumber(2), YamlNumber(3)), proj)
        test_construct("yaml/seq-str",    YamlSequence(YamlString("a"), YamlString("b")),       proj)
        test_construct("yaml/seq-nested", YamlSequence(YamlSequence(YamlNumber(1))),            proj)

        # Mappings: keyed entries, multi-entry grow, nesting, placeholder value
        test_construct("yaml/map-1",      YamlMapping("a" => YamlNumber(1)),                    proj)
        test_construct("yaml/map-2",      YamlMapping("a" => YamlNumber(1), "b" => YamlNumber(2)), proj)
        test_construct("yaml/map-str",    YamlMapping("name" => YamlString("Alice")),           proj)
        test_construct("yaml/map-nested", YamlMapping("addr" => YamlMapping("city" => YamlString("W"))), proj)
        test_construct("yaml/map-insert", YamlMapping("ph" => YamlInsertion()),                 proj)

        # The catalog document end to end (the full nested mapping)
        test_construct("yaml/doc-main", make_yaml_document_example(), proj)

        # @broken: same empty-container authoring gap as JSON (no element-delete gesture).
        test_construct("yaml/seq-empty", YamlSequence(), proj; broken=true)
        test_construct("yaml/map-empty", YamlMapping(),  proj; broken=true)
    end
end

"""
    test_xml_construct()

Reconstruct every XML document from its empty seed by typing. XML stretches the generic
planner furthest: an `XmlElement` is a scalar `tag` beside *two* collections (attributes
and children), an `XmlAttribute` is a two-scalar `name`/`value` record, and its collections
are grown by *different, kind-specific* gestures — a child element with `<`, a child text
with `"`, an attribute with `KeyDown(:space)` — rather than one uniform separator. All of
this is discovered generically (create + grow keystrokes probed per kind). There is no
empty-container gap here: an XML element is created empty and its children are appended one
at a time, so an element with no children is the natural resting state.

(`<`/`"`/`@` are made to build a node directly from the empty `XmlNothing`, like JSON — see
`_xml_replaceable` — so a structure is authorable without the typed-name insertion buffer.)
"""
function test_xml_construct()
    proj = make_xml_projection_example()
    @testset "xml/construct" begin
        # Leaf and two-scalar record
        test_construct("xml/text",      XmlText("hi"),          proj)
        test_construct("xml/attribute", XmlAttribute("k", "v"), proj)

        # Elements: bare (empty), a text child, multiple children, attributes, nesting
        test_construct("xml/elem-bare",   XmlElement("br"),                     proj)
        test_construct("xml/elem-text",   XmlElement("p", [XmlText("hi")]),     proj)
        test_construct("xml/elem-2child", XmlElement("ul", [XmlElement("li", [XmlText("a")]),
                                                            XmlElement("li", [XmlText("b")])]), proj)
        test_construct("xml/elem-attr",   XmlElement("a", [XmlAttribute("href", "x")]), proj)
        test_construct("xml/elem-2attr",  XmlElement("a", [XmlAttribute("id", "1"),
                                                           XmlAttribute("k", "v")]), proj)
        test_construct("xml/elem-attr-child",
                       XmlElement("a", [XmlAttribute("href", "x")], [XmlText("link")]), proj)
        test_construct("xml/elem-nested", XmlElement("ul", [XmlElement("li", [XmlText("a")])]), proj)

        # The full catalog document (library → books with attributes + text children)
        test_construct("xml/doc-main", make_xml_document_example(), proj)
    end
end
