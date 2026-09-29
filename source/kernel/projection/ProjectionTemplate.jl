# Fragment of `ProjectionModule` — `@projection_template` and the
# builder-and-walk engine behind it. Every structural projection is written
# with it rather than as a hand-written printer and reader pair.
#
# It names no concrete children-container type: `make_children_container` builds
# the container and `get_children_container_type` returns the concrete type for
# a `TypeReferenceStep` marker, and a higher package registers both. That is the
# pressure that keeps the engine kernel-pure.
#
# Two seams stay open for a higher package. The `RuleIoMap` readers keyed on the
# transparent recursive wrapper, and the one text-range-replace retype method,
# live there beside the reader defaults: that wrapper projection and that
# operation type are defined there, and the kernel can name neither. The higher
# package imports `RuleIoMap` and `AtomicWiring` from here to keep the same
# dispatch.


# ── The marker words of a template body ─────────────────────────────────────

"""
The words a template body writes to mark a slot. They are resolved by
`make_template_builder`, so no module that writes a template needs them in its
namespace.
"""
const TEMPLATE_MARKER_WORDS = (:bound, :project, :collection, :tokens, :sections)

"""
    make_template_builder(expr) -> expr

Return the template body with every marker-word call bound to this module's
function, whatever the calling module has in scope.

`bound`, `project`, `collection`, `tokens` and `sections` are ordinary English
words, and a domain wants them for its own code: four files in this repository
already bind one of them as a local. A macro that escaped the body wholesale
would make every module that writes a template import all five. This resolves
the call head instead, so the words stay private to this module.

Only a call head is resolved. A local of the same name, a field access and a
word in a string are left alone.
"""
function make_template_builder(expr)
    expr isa Expr || return expr
    if expr.head === :call && !isempty(expr.args) &&
       expr.args[1] isa Symbol && expr.args[1] in TEMPLATE_MARKER_WORDS
        return Expr(:call, getfield(@__MODULE__, expr.args[1]),
                    map(make_template_builder, expr.args[2:end])...)
    end
    Expr(expr.head, map(make_template_builder, expr.args)...)
end

# ── Markers (build-time only; stripped before the output reaches the API) ─────

struct Bound;      input::Symbol; type::Any; render::Any; retype::Any; end
struct Project;    input::Symbol; override::Any; end              # override: `as=` projection|thunk|nothing
struct Collection; input::Symbol; element::Any; end
struct Tokens;     thunk::Any; end                                # computed inline token leaves
struct Sections;   specs::Vector{Any}; end                        # grouped per-field sub-collections

bound(input::Symbol, T, render; retype=nothing) = Bound(input, T, render, retype)
# `project(:f)` delegates the child to its type-dispatched projection; `project(:f;
# as=proj)` delegates through a supplied projection instead. `as` may be a projection
# instance (always used) or a function `v -> projection|nothing` (chosen per child
# value; `nothing` ⇒ fall back to the type-dispatcher) — the latter lets a callee
# render as a function name only when it is a bare identifier.
project(input::Symbol; as=nothing) = Project(input, as)
collection(input::Symbol) = Collection(input, nothing)
collection(element, input::Symbol) = Collection(input, element)   # collection(:f) do x … end
tokens(thunk) = Tokens(thunk)                                     # tokens(() -> [leaf, bound-leaf, …])
# sections([(field::Symbol, make_wrapper), …]); make_wrapper(entry_outputs) builds
# the per-section wrapper node. Empty sections are skipped; index is dynamic.
sections(specs) = Sections(Any[specs...])

# Resolve a `project(:f; as=…)` override for a concrete child value.
_override(as, v) = as === nothing ? nothing : (as isa Function ? as(v) : as)

# Build the (reconciling) child iomap for a `project(:f)` slot, honouring an `as=`
# override. Shared by `_fixed_print`/`_mixed_print`.
_project_child_cell(recursion, doc, ctx, prj::Project) =
    reconcile_child_iomap(() -> getproperty(doc, prj.input),
        v -> begin
            cctx = make_child_context(ctx, FieldReferenceStep(String(prj.input)))
            ov = _override(prj.override, v)
            ov === nothing ? print_child(recursion, v, cctx) :
                             ProjectionModule.print_document(ov, recursion, v, cctx)
        end)

# ── Wiring + IoMap ───────────────────────────────────────────────────────────

# What the walk recovers for a leaf: the (optional) bound field. Any *other*
# output field is projection-introduced, so the backward mapper proj-wraps a
# cursor on it without the engine needing to know the output domain's text type.
struct AtomicWiring
    intype::Type
    outtype::Type
    bound_field::Union{Symbol,Nothing}   # nothing ⇒ opaque (all-introduced) leaf
    bound_type::Union{Type,Nothing}
    value_field::Union{Symbol,Nothing}   # output field carrying the bound value
    # The element type of the output field, from the render of the marker.
    value_checkpoint::Union{Type,Nothing}
    retype::Union{Type,Nothing}
end

# What the walk recovers for a node: which input field is the recursive
# collection and which output field holds the projected children. Per-child
# correspondence lives in the stored `child_iomaps` (School A).
struct NodeWiring
    intype::Type
    outtype::Type
    coll_input_field::Symbol             # input collection field, e.g. :elements
    children_field::Symbol               # output field holding the children, e.g. :children
end

# A fixed-children node (e.g. an object's per-entry key/value pair node): its children are
# a fixed list, each wired individually rather than a homogeneous collection.
# Such a node is produced by a `collection(:f) do x … end` element builder, walked
# per element, and delegated to by the enclosing collection mapper.
# A child that is a leaf: whole key ↔ whole child, char of `in_field` ↔ char of the
# leaf's `value_field`.
struct KeySlot
    in_field::Symbol
    value_field::Symbol
    in_type::Type
    checkpoint::Type
end
struct ProjectSlot; in_field::Symbol; end                                 # child delegated (iomap in the store)
struct IntroSlot end                                                      # introduced child (keyword/delimiter)
# A child that is itself a marker-bearing output node (a header/bracket grouping
# with no input pre-image whose `project`/`collection` children key off the *same*
# parent input). Walked recursively with the parent doc/ctx; its nested iomap is
# embedded here so the mappers can delegate through it (prepending one `.children[k]`).
struct SubNodeSlot; iomap::Any; end

struct FixedNodeWiring
    intype::Type
    outtype::Type
    children_field::Symbol               # output field holding the fixed children
    slots::Vector{Any}                   # KeySlot|ProjectSlot|IntroSlot|SubNodeSlot per child index
end

# A fixed-shaped node whose child *slot list* is reactive (F2): the children cell
# computes a marker vector, again on each structural change (an optional
# field toggling appears/disappears a slot). Like `FixedNodeWiring` but the slots +
# project store live in a Cell (`child_iomaps`), read fresh by the mappers.
struct ConditionalNodeWiring
    intype::Type
    outtype::Type
    children_field::Symbol
end

# A node whose children are a fixed prefix (bound/delegated/introduced leaves)
# followed by one spliced `collection(:field)` whose elements become the trailing
# siblings (e.g. a section heading leaf + its entries). `child_iomaps` is a
# NamedTuple `(prefix=Dict{Symbol,iomap}, coll=Cell{Vector{iomap}})`.
struct MixedNodeWiring
    intype::Type
    outtype::Type
    children_field::Symbol
    prefix_slots::Vector{Any}            # KeySlot|ProjectSlot|IntroSlot, children[1..prefix_len]
    coll_field::Symbol                   # input collection field spliced after the prefix
end

# An inline node whose children are a computed, variable-length token-leaf vector
# (recomputed reactively); exactly one token is a `bound` leaf at a stable index,
# the rest are decorative (no input pre-image → flat-offset fallback).
struct InlineWiring
    intype::Type
    outtype::Type
    children_field::Symbol
    bound_index::Int                     # 1-based index of the bound token leaf
    bound_field::Symbol                  # input field it edits
    value_field::Symbol                  # field of the token leaf that holds the value
    bound_type::Union{Type,Nothing}
    value_checkpoint::Union{Type,Nothing}
end

# A node grouping several per-field sub-collections under labelled wrapper nodes,
# skipping empty fields (dynamic section index). `child_iomaps` is a Cell yielding
# a Vector of `(field=Symbol, entries=Vector{iomap})` for the non-empty sections in
# render order. `.field[i].tail ↔ .children[sec].children[i].tail`.
struct SectionsWiring
    intype::Type
    outtype::Type
    children_field::Symbol
end

# The projection, the input, the output and the wiring never change after the print,
# so they are immutable cells, which a computation that reads them does not track.
@iomap struct RuleIoMap
    projection::ImmutableCell{Any}
    input::ImmutableCell{Any}
    output::ImmutableCell{Any}
    wiring::ImmutableCell{Any}
    child_iomaps::Any                    # Cell or nothing (nodes; WIP)
end

# ── Path helpers (build the exact shapes @reference/@reference_case produce) ───

# A whole-element selection typed `::T`: the folded terminal carrying T.
_typed(T) = EmptyReference(T)
# Build a path from `steps...` (which may include unfolded `TypeReferenceStep`
# checkpoint steps), then fold those checkpoints into node types so the result is
# the canonical folded form `@reference`/`@reference_case` produce.
_path(steps...) = begin
    p = EmptyReference()
    for i in length(steps):-1:1
        p = ConcreteReference(steps[i], p)
    end
    fold_reference_types(p)
end
# prepend `steps...` in front of an existing (already-folded) path tail, then fold
# any prepended `TypeReferenceStep` checkpoint steps into node types.
_prepend(tail::Reference, steps...) = begin
    p = tail
    for i in length(steps):-1:1
        p = ConcreteReference(steps[i], p)
    end
    fold_reference_types(p)
end
# Reduce a path to its plain navigation skeleton (node types blanked). A structural
# input boundary wants clean, type-free reference paths; a delegated child's backward
# result carries the child's folded node types, so the collection mapper strips them
# when it splices the child's tail under `.elements[i]` / `.entries[i]`.
_strip_checkpoints(x) = strip_reference_types(x)

# ── The builder/walk printer ─────────────────────────────────────────────────

# @positional: the arity of the printer of the projection protocol, with the
# builder of the template beside it. The macro emits a method of that shape.
"""
    print_template_rule(p, recursion, doc, ctx, builder)

Build the marked output via `builder(p, doc)`, walk it to record the wiring,
strip the markers (replacing each with its real value *through* the field's Cell),
and return a `RuleIoMap`. The selection cell is wired at construction time: each
node is rebuilt once via [`_with_selection`](@ref) with its final selection cell in
place, reusing every other field's Cell object. No node is retargeted after
anything else references it (prerequisite for the immutable kind-parameterized
stem — plan/pending/cell-kind-documents.md, Phase 0).
"""
print_template_rule(p, recursion, doc, ctx, builder) = _dispatch_print(p, recursion, doc, ctx, builder(p, doc))

# Dispatch an *already-built* output on its shape. Factored out of `print_template_rule` so a
# nested marker-bearing sub-node (a `SubNodeSlot`) is walked by the same rules with
# the parent doc/ctx (F1), not just the top-level builder output.
function _dispatch_print(p, recursion, doc, ctx, out)
    cond_field, cond = _find_conditional(out)
    cond !== nothing && return _conditional_print(p, recursion, doc, ctx, out, cond_field, cond)
    coll_field, coll = _find_collection(out)
    coll !== nothing && return _node_print(p, recursion, doc, ctx, out, coll_field, coll)
    tok_field, tok = _find_tokens(out)
    tok !== nothing && return _inline_print(p, recursion, doc, ctx, out, tok_field, tok.thunk)
    sec_field, secs = _find_sections(out)
    secs !== nothing && return _sections_print(p, recursion, doc, ctx, out, sec_field, secs.specs)
    # A node built with a raw children Vector (markers/leaves) but no Collection
    # marker *field* is a fixed-children node. If that Vector contains a Collection
    # marker among fixed children, it is a mixed node (fixed prefix + one spliced
    # collection); otherwise it is a pure fixed-children record. Leaves have neither.
    if _has_fixed_children(out)
        cf = _find_fixed_children(out)
        any(c -> c isa Collection, getproperty(out, cf)) &&
            return _mixed_print(p, recursion, doc, ctx, out, cf)
        return _fixed_print(p, recursion, doc, ctx, out)
    end
    return _atomic_print(p, doc, out)
end

# ── A blueprint's fixed child list ───────────────────────────────────────────
#
# A node built with a *positional* constructor stores its children as a raw `Vector`
# — whatever it was handed. One built with a *keyword* constructor has them coerced
# into an element collection, because that is what a real output
# node needs: the reference machinery navigates `.children[i]` through its element
# cells.
#
# Both are the same blueprint, and the engine has to walk either. Recognising only the
# raw `Vector` is why a fixed-children template node had to be spelled in the long
# positional form: written with a node constructor over a raw child vector, its
# children were invisible here, the node fell through to `_atomic_print`, and the
# `bound`/`project` markers reached the printer unresolved — where it reads `.content`
# off a `Bound` and dies.
#
# A raw `Vector` counts unconditionally. An element collection counts
# only when it actually CARRIES a marker: a marker-free one is an ordinary output subtree
# and must keep going to `_atomic_print`. So the rule is strictly additive — it cannot
# change what any existing template does.
#
# `is_element_collection` is the document-layer trait a positional collection opts into.
# The kernel cannot name the concrete element-collection type, so it asks the trait instead.
_is_fixed_children(::Vector) = true
_is_fixed_children(x) = is_element_collection(x) && any(_carries_marker, x)

# Does a blueprint child carry a marker? Not the same question as `_is_marker` or
# `_is_marker_bearing_subnode`: the commonest fixed child is a `SyntaxLeaf(bound(:x))`,
# which is neither — it is an ordinary document holding a marker in a *field*. Only ever
# called on a builder's blueprint (never on a hand-written projection's output), so
# forcing the cells it reads costs nothing at print time.
_carries_marker(x) = _is_marker(x)
function _carries_marker(x::Document)
    for fname in fieldnames(typeof(x))
        v = getfield(x, fname)[]
        _is_marker(v) && return true
        (v isa Vector || is_element_collection(v)) && any(_carries_marker, v) && return true
    end
    false
end

_has_fixed_children(out) = any(fname -> _is_fixed_children(getfield(out, fname)[]), fieldnames(typeof(out)))

# Locate a reactive child list (F2): a field whose cell computes a blueprint child
# list. A builder writes it as a thunk, `SyntaxConcatenation(() -> [...])`, and the
# node constructor makes the thunk the computation of the children cell. A cell that
# holds a value, or that computes anything other than a child list, is not one. The
# read is untracked: the state cell of `_conditional_print` depends on the child
# list, and the computation that prints this node does not.
function _find_conditional(out)
    for fname in fieldnames(typeof(out))
        cell = getfield(out, fname)
        is_computed_cell(cell) && _is_fixed_children(peek(cell)) && return (fname, cell)
    end
    (nothing, nothing)
end

# ── Nested-marker detection (F1) ─────────────────────────────────────────────
# A child in a fixed-children vector is a `SubNodeSlot` iff it is itself an output
# *node* (has a children vector or a Collection/Tokens/Sections marker field) that
# *contains markers*. A bound/opaque leaf (marker in its `value`, no children field)
# is NOT a sub-node — it stays a Key/Intro slot.
_is_marker(v) = v isa Union{Bound, Project, Collection, Tokens, Sections}

function _vector_has_markers(node)
    cf = _find_fixed_children(node)
    for c in getproperty(node, cf)
        (_is_marker(c) || _is_marker_bearing_subnode(c)) && return true
    end
    return false
end

function _is_marker_bearing_subnode(child)
    _is_marker(child) && return false                       # a bare marker is handled by the caller
    (_find_collection(child)[1] !== nothing || _find_tokens(child)[1] !== nothing ||
     _find_sections(child)[1] !== nothing) && return true
    _has_fixed_children(child) && _vector_has_markers(child) && return true
    return false
end

# Locate a `Tokens` marker among the built output's fields, if any.
function _find_tokens(out)
    for fname in fieldnames(typeof(out))
        val = getfield(out, fname)[]
        val isa Tokens && return (fname, val)
    end
    (nothing, nothing)
end

# Locate a `Sections` marker among the built output's fields, if any.
function _find_sections(out)
    for fname in fieldnames(typeof(out))
        val = getfield(out, fname)[]
        val isa Sections && return (fname, val)
    end
    (nothing, nothing)
end

# Selection cell for a bound child leaf of a fixed node: lens `doc.<in_field>{k}`
# onto the leaf's own `.<value_field>{k}` span; pass a proj-wrapped structural cursor
# through unchanged.
function _key_leaf_sel(doc, in_field::Symbol, value_field::Symbol)
    fname = String(in_field)
    Cell(@computation(map_selection_forward(doc, sel -> begin
        is_introduced_reference(sel) && return sel
        core = sel
        if core isa ConcreteReference && core.head isa FieldReferenceStep && core.head.name == fname
            return ConcreteReference(FieldReferenceStep(String(value_field)), core.tail)
        end
        return nothing
    end)))
end

# Locate a `Collection` marker among the built output's fields, if any.
function _find_collection(out)
    for fname in fieldnames(typeof(out))
        val = getfield(out, fname)[]
        val isa Collection && return (fname, val)
    end
    (nothing, nothing)
end

# Rebuild `node` with `sel` as its selection cell, reusing every other field's Cell
# object — child/shared cells keep their identity, and prior value writes through
# those cells are preserved. The auto-wrapping inner ctor passes Cells through
# unchanged. Every call site rebuilds the node *before* anything else references it, so
# document nodes are never retargeted after construction. A `field => value`
# replacement puts `value` in place of the cell of `field`, and the constructor wraps
# it in a new cell: a write into the old cell deletes its computation, if it has one.
_with_selection(node, sel::Cell, replacement::Pair{Symbol} = :selection => sel) =
    Base.typename(typeof(node)).wrapper(   # the UnionAll: its ctor accepts cells
        (f === :selection ? sel : f === first(replacement) ? last(replacement) :
         getfield(node, f) for f in fieldnames(typeof(node)))...)

# Kind-agnostic type name for a document node: the UnionAll wrapper of a
# kind-parameterized `@document` type, the type itself otherwise. Wirings record
# this (not the concrete kind-specialized `typeof`) so the reference paths they
# build carry the same bare names the `@reference` macro and
# `annotate_reference_types` use — the `.type === .type` reference comparisons
# then hold across an input and a kind-converted copy of it.
_dtype(x) = Base.typename(typeof(x)).wrapper

function _atomic_print(p, doc, out)
    wiring = _scan_atomic!(p, doc, out)
    # Wire the output leaf's selection cell (construction-time, deferred-iomap trick):
    #   opaque (no bound field) ⇒ forward-map (∅↔∅, else unmapped). The generic
    #                             mapper tolerates the `nothing` iomap (a ∅ stays
    #                             untyped, an unmapped path returns as-is).
    #   output field named as   ⇒ share doc's cell raw — the input cursor `.field{k}`
    #   the input field           already names the leaf's value span (leaf fast path).
    #   another output field    ⇒ value-lens: forward-map `.field{k}` to the leaf's
    #                             `.<value_field>{k}`.
    iomap_cell = Cell(nothing)
    # `map_selection_forward`, not a plain read of `doc.selection`: the property
    # answers `nothing` for a dormant selection, so a plain read would drop the
    # live/dormant state at this hop and the painter at the end of the chain would
    # have nothing left to paint pale.
    # `map_missing`: this branch mapped an absent selection too, and a projection
    # that introduces one answers a real image for `nothing`. A guard here would
    # make such an introduced caret unreachable.
    sel = wiring.bound_field === nothing ?
              Cell(@computation(map_selection_forward(doc, path -> map_reference_forward(p, nothing, path);
                                                      map_missing = true))) :
          wiring.value_field === wiring.bound_field ? getfield(doc, :selection) :
                                           Cell(@computation begin
                                               im = iomap_cell[]
                                               im === nothing && return nothing
                                               map_selection_forward(doc, path -> map_reference_forward(p, im, path))
                                           end)
    out = _with_selection(out, sel)
    iomap = RuleIoMap(p, doc, out, wiring, nothing)
    iomap_cell[] = iomap
    iomap
end

# Reactive output of a reconciling delegated child: tracks the (possibly rebuilt)
# child iomap's `output`. A free function so the closure captures *this* cell, not
# a loop variable reassigned on the next iteration.
_project_output_cell(child_cell) = Cell(@computation child_cell[].output)

# The child IoMaps of the collection `doc.<field>`, each element printed by its own
# projection. An element that stays at its index keeps its IoMap across an edit.
_reconcile_element_iomaps(doc, field::Symbol; recursion, context) =
    reconcile_child_iomaps(() -> getproperty(doc, field), (i, x) ->
        print_child(recursion, x, make_child_context(context,
            FieldReferenceStep(String(field)), ElementReferenceStep(i))))

# A node-shaped output: recurse over `doc.<input>` (School A), reconstruct the
# node with the projected children and a deferred selection cell, and store the
# child iomaps so the mappers can delegate each child's tail.
function _node_print(p, recursion, doc, ctx, out, children_field, coll)
    input_field = coll.input
    elements_fn = () -> getproperty(doc, input_field)
    child_iomaps = if coll.element === nothing
        # homogeneous: each element projected by its own projection
        _reconcile_element_iomaps(doc, input_field; recursion, context = ctx)
    else
        # templated: build a fixed-children node per element via the element builder
        reconcile_child_iomaps(elements_fn, (i, x) ->
            _fixed_print(p, recursion, x,
                make_child_context(ctx, FieldReferenceStep(String(input_field)), ElementReferenceStep(i)),
                coll.element(x)))
    end
    iomap_cell = Cell(nothing)
    sel = Cell(@computation begin
        im = iomap_cell[]
        im === nothing && return nothing
        map_selection_forward(doc, path -> map_reference_forward(p, im, path))
    end)
    children = make_children_container(() -> [im.output for im in child_iomaps[]])
    setproperty!(out, children_field, children)   # replace the Collection marker with the real children
    out = _with_selection(out, sel)
    wiring = NodeWiring(_dtype(doc), _dtype(out), input_field, children_field)
    iomap = RuleIoMap(p, doc, out, wiring, child_iomaps)
    iomap_cell[] = iomap
    return iomap
end

# Scan a leaf-shaped output for the (optional) `bound` marker and strip it in
# place to its real value. Fields are classified by *value*, so no output-domain
# field names are referenced: a non-marker field is left alone (and treated as
# introduced by the mapper).
function _scan_atomic!(p, doc, out)
    intype = _dtype(doc); outtype = _dtype(out)
    bound_field = nothing; bound_type = nothing
    value_field = nothing; value_checkpoint = nothing; retype = nothing
    for fname in fieldnames(outtype)
        val = getfield(out, fname)[]
        if val isa Bound
            bound_field = val.input; bound_type = val.type
            value_field = fname; value_checkpoint = typeof(val.render); retype = val.retype
            setproperty!(out, fname, val.render)          # strip ⇒ real value
        elseif val isa Union{Project,Collection}
            error("ProjectionTemplate: node markers are not yet supported (leaf-only)")
        end
    end
    AtomicWiring(intype, outtype, bound_field, bound_type, value_field, value_checkpoint, retype)
end

# A fixed-children node built per element (e.g. an object's key/value pair node). Each child
# of its `children` vector is classified: a `project(:f)` marker → delegated child;
# a built leaf carrying a `bound` marker → key slot (its value holds a doc field);
# anything else → introduced. The element's own selection cells (set by the
# element builder, e.g. the entry selection and key→value remap) are left intact.
# Walk a marker vector into (slots, project-store, output cells). Each child is
# classified: `project(:f)` → ProjectSlot (reconciling iomap in the store); a nested
# marker-bearing node → SubNodeSlot (F1); a `bound` leaf → KeySlot; anything else →
# IntroSlot. Shared by `_fixed_print` (static vector) and `_conditional_print`
# (computed child list, F2).
function _walk_markers(p, recursion, doc, ctx, markers)
    slots = Any[]; store = Dict{Symbol,Any}(); output_cells = Cell[]
    for child in markers
        if child isa Project
            # Delegated child reconciled by value identity, so a later type-swap of
            # `doc.<field>` (type-to-replace on an insertion slot) rebuilds it
            # instead of leaving a stale child iomap. The store holds the *cell*;
            # mappers/reader force it (`[]`) for the current child iomap.
            fld = child.input
            cell = _project_child_cell(recursion, doc, ctx, child)
            store[fld] = cell
            push!(slots, ProjectSlot(fld))
            push!(output_cells, _project_output_cell(cell))
        elseif child isa Collection
            error("ProjectionTemplate: nested collection inside a fixed-children node is not supported")
        elseif _is_marker_bearing_subnode(child)
            # F1: a nested marker-bearing node (a header/bracket grouping). Walk it
            # recursively with the *parent* doc/ctx — its `project`/`collection`
            # children key off parent input fields — and embed the nested iomap.
            sub = _dispatch_print(p, recursion, doc, ctx, child)
            push!(slots, SubNodeSlot(sub))
            push!(output_cells, Cell(sub.output))
        else
            w = _scan_atomic!(p, doc, child)   # strips a `bound` marker if present
            if w.bound_field === nothing
                push!(slots, IntroSlot())
            else
                # A bound child leaf renders its own cursor from its own selection
                # cell. Lens the element's `.<bound_field>{k}` onto the leaf's
                # `.<value_field>{k}` generically, so the builder needn't hand-wire it.
                child = _with_selection(child, _key_leaf_sel(doc, w.bound_field, w.value_field))
                push!(slots, KeySlot(w.bound_field, w.value_field, w.bound_type,
                                     w.value_checkpoint))
            end
            push!(output_cells, Cell(child))
        end
    end
    (slots, store, output_cells)
end

function _fixed_print(p, recursion, doc, ctx, out)
    children_field = _find_fixed_children(out)
    slots, store, output_cells = _walk_markers(p, recursion, doc, ctx, getproperty(out, children_field))
    setproperty!(out, children_field, make_children_container(output_cells))
    # The fixed node is a real output node, so its selection cell must hold an
    # *output* path: forward-map the element's input selection through this node's
    # own wiring (deferred-iomap trick, as the top node does).
    iomap_cell = Cell(nothing)
    out = _with_selection(out, Cell(@computation begin
        im = iomap_cell[]
        im === nothing && return nothing
        # `map_selection_forward`, so a dormant selection maps forward as one.
        map_selection_forward(doc, path -> map_reference_forward(p, im, path))
    end))
    im = RuleIoMap(p, doc, out, FixedNodeWiring(_dtype(doc), _dtype(out), children_field, slots), store)
    iomap_cell[] = im
    return im
end

# F2: a node whose children cell `markers` computes a marker vector (an
# optional-field toggle appears/disappears a `project`/leaf slot). The state cell
# reads `markers` and re-walks the markers on each structural change; the mappers
# read the current (slots, store) from it, and the output children double-track the
# state cell (structure) and each output cell (child content / type-swap). The
# output node gets its children in a new cell, so `markers` keeps its computation.
function _conditional_print(p, recursion, doc, ctx, out, children_field, markers)
    state = Cell(@computation _walk_markers(p, recursion, doc, ctx, markers[]))
    children = make_children_container(() -> [c[] for c in state[][3]])
    iomap_cell = Cell(nothing)
    out = _with_selection(out, Cell(@computation begin
        im = iomap_cell[]
        im === nothing && return nothing
        map_selection_forward(doc, path -> map_reference_forward(p, im, path))
    end), children_field => children)
    im = RuleIoMap(p, doc, out, ConditionalNodeWiring(_dtype(doc), _dtype(out), children_field), state)
    iomap_cell[] = im
    return im
end

function _find_fixed_children(out)
    for fname in fieldnames(typeof(out))
        _is_fixed_children(getfield(out, fname)[]) && return fname
    end
    error("ProjectionTemplate: fixed-children node has no children vector")
end

# A mixed node: a fixed prefix of leaves/markers followed by one spliced
# `collection(:field)` whose elements become the trailing children (e.g. a section
# heading leaf + its entries). The collection must be last (no fixed suffix).
function _mixed_print(p, recursion, doc, ctx, out, children_field)
    raw = getproperty(out, children_field)
    # Each prefix output source is either a reconciling child cell (a `project(:f)`,
    # forced for its current output) or a static leaf node. Keeping the project ones
    # reactive lets a prefix value type-swap rebuild its child (see `_fixed_print`).
    prefix_slots = Any[]; store = Dict{Symbol,Any}(); prefix_sources = Any[]
    coll_field = nothing
    for child in raw
        if child isa Collection
            coll_field === nothing || error("ProjectionTemplate: only one spliced collection per mixed node")
            coll_field = child.input
        elseif coll_field !== nothing
            error("ProjectionTemplate: fixed children after a spliced collection are not supported")
        elseif child isa Project
            fld = child.input
            cell = _project_child_cell(recursion, doc, ctx, child)
            store[fld] = cell
            push!(prefix_slots, ProjectSlot(fld))
            push!(prefix_sources, cell)
        else
            w = _scan_atomic!(p, doc, child)
            if w.bound_field === nothing
                push!(prefix_slots, IntroSlot())
            else
                child = _with_selection(child, _key_leaf_sel(doc, w.bound_field, w.value_field))
                push!(prefix_slots, KeySlot(w.bound_field, w.value_field, w.bound_type,
                                            w.value_checkpoint))
            end
            push!(prefix_sources, child)
        end
    end
    coll_field === nothing && error("ProjectionTemplate: mixed node has no spliced collection")
    coll_iomaps = _reconcile_element_iomaps(doc, coll_field; recursion, context = ctx)
    children = make_children_container(() -> vcat(
        [s isa Cell ? s[].output : s for s in prefix_sources],
        [im.output for im in coll_iomaps[]]))
    setproperty!(out, children_field, children)
    iomap_cell = Cell(nothing)
    out = _with_selection(out, Cell(@computation begin
        im = iomap_cell[]; im === nothing && return nothing
        map_selection_forward(doc, path -> map_reference_forward(p, im, path))
    end))
    wiring = MixedNodeWiring(_dtype(doc), _dtype(out), children_field, prefix_slots, coll_field)
    iomap = RuleIoMap(p, doc, out, wiring, (prefix=store, coll=coll_iomaps))
    iomap_cell[] = iomap
    return iomap
end

# An inline node over a *computed* token-leaf vector (`tokens(thunk)`). The thunk
# yields decorative leaves plus exactly one `bound` leaf (the editable token) at a
# stable index. The output children re-run the thunk reactively and strip the
# marker each recompute (so a varying token count stays live); the wiring's
# bound index is sampled once. Decorative tokens have no input pre-image and round-
# trip via the consumer's flat-offset reader.
function _inline_print(p, recursion, doc, ctx, out, children_field, thunk)
    sample = thunk()
    bound_index = 0; bound_field = :_; value_field = :_
    bound_type = nothing; value_checkpoint = nothing
    for (i, leaf) in enumerate(sample)
        for fname in fieldnames(typeof(leaf))
            v = getfield(leaf, fname)[]
            if v isa Bound
                bound_index = i; bound_field = v.input; value_field = fname
                bound_type = v.type; value_checkpoint = typeof(v.render)
                break
            end
        end
        bound_index == 0 || break
    end
    children = make_children_container(() -> begin
        # The thunk rebuilds the leaves fresh each recompute, so rebuilding a bound
        # leaf with its selection cell here happens before anything references it.
        map(thunk()) do leaf
            for fname in fieldnames(typeof(leaf))
                v = getfield(leaf, fname)[]
                if v isa Bound
                    setproperty!(leaf, fname, v.render)
                    leaf = _with_selection(leaf, _key_leaf_sel(doc, v.input, fname))
                    break
                end
            end
            leaf
        end
    end)
    setproperty!(out, children_field, children)
    iomap_cell = Cell(nothing)
    out = _with_selection(out, Cell(@computation begin
        im = iomap_cell[]; im === nothing && return nothing
        map_selection_forward(doc, path -> map_reference_forward(p, im, path))
    end))
    wiring = InlineWiring(_dtype(doc), _dtype(out), children_field, bound_index,
                          bound_field, value_field, bound_type, value_checkpoint)
    iomap = RuleIoMap(p, doc, out, wiring, nothing)
    iomap_cell[] = iomap
    return iomap
end

# A section-grouped node: each spec `(field, make_wrapper)` whose `doc.field` is
# non-empty becomes a labelled wrapper child whose own children are that field's
# recursively-projected entries (School A). Empty sections are skipped, so the
# section index is dynamic; `make_wrapper(entry_outputs)` is consumer code that
# builds the (output-domain) wrapper node, keeping the engine output-neutral.
function _sections_print(p, recursion, doc, ctx, out, children_field, specs)
    entry_iomaps = [_reconcile_element_iomaps(doc, field; recursion, context = ctx)
                    for (field, _) in specs]
    section_iomaps = Cell(@computation begin
        res = NamedTuple[]
        for ((field, mk), entries_cell) in zip(specs, entry_iomaps)
            entries = entries_cell[]
            isempty(entries) && continue
            push!(res, (field=field, mk=mk, entries=entries))
        end
        res
    end)
    children = make_children_container(() -> [s.mk([im.output for im in s.entries]) for s in section_iomaps[]])
    setproperty!(out, children_field, children)
    iomap_cell = Cell(nothing)
    out = _with_selection(out, Cell(@computation begin
        im = iomap_cell[]; im === nothing && return nothing
        map_selection_forward(doc, path -> map_reference_forward(p, im, path))
    end))
    iomap = RuleIoMap(p, doc, out, SectionsWiring(_dtype(doc), _dtype(out), children_field), section_iomaps)
    iomap_cell[] = iomap
    return iomap
end

# ── Generic, data-driven mappers (one method, all template projections) ───────

# Ensure a generic (template) mapper emits a fully-typed sub-path so a parent's
# `^(inner)` splice stays typed (the reference-types-always-present invariant).
# The template machinery builds paths from raw steps / `ProjectionReferenceStep`
# wraps whose terminals it cannot always spell inline; annotating the finished
# path against the mapper's own document (the one it navigates) fills every node
# type at the source, so consumers need no boundary re-annotation.
_typed_generic(::Nothing, _doc) = nothing
_typed_generic(r, doc) = is_fully_typed_reference(r) ? r : annotate_reference_types(doc, r)

# Each wiring maps a reference by a method of `_map_forward` and `_map_backward`.
function map_reference_forward(p::Projection, iomap::RuleIoMap, reference)
    mapped = _map_forward(iomap.wiring, iomap, reference; projection = p)
    _typed_generic(mapped, iomap.output)
end

# A node wiring prints parts of its own (delimiters, separators, layout), which a
# reference can reach and which have no input pre-image.
const _INTRODUCING_WIRINGS = Union{NodeWiring,MixedNodeWiring,InlineWiring,SectionsWiring,
                                   FixedNodeWiring,ConditionalNodeWiring}

# A child maps a position of its own output back to its input. A position that the
# child can not map is a part that its own projection printed, so the step that names
# it stands at the child: as late in the reference as it can, never at an ancestor.
function _map_child_backward(child, reference)
    inner = map_reference_backward(child.projection, child, reference)
    inner === nothing || return inner
    (child isa RuleIoMap && child.wiring isa _INTRODUCING_WIRINGS) || return nothing
    return make_introduced_reference(child.projection, child.input, reference)
end

function map_reference_backward(p::Projection, iomap::RuleIoMap, reference)
    mapped = _map_backward(iomap.wiring, iomap, reference; projection = p)
    _typed_generic(mapped, iomap.input)
end

# ── atomic (leaf) ─────────────────────────────────────────────────────────────

function _map_forward(w::AtomicWiring, iomap, reference; projection)
    reference === nothing && return nothing
    core = reference
    # unwrap this projection's own introduced step (both opaque & transparent)
    if is_introduced_reference(core, projection)
        return core.head.output_path
    end
    if w.bound_field === nothing
        # opaque ⇒ mirror the default mapper: ∅ ⇒ ∅ (typed to the output node so
        # the strict-typing invariant holds), otherwise unmapped
        core isa EmptyReference && return _typed(w.outtype)
        return nothing
    end
    core isa EmptyReference && return _typed(w.outtype)                 # whole ⇒ ::Out
    if core isa ConcreteReference && core.head isa FieldReferenceStep && core.head.name == String(w.bound_field)
        rest = core.tail
        if rest isa ConcreteReference && rest.head isa RangeReferenceStep
            return _prepend(rest, TypeReferenceStep(w.outtype),
                            FieldReferenceStep(String(w.value_field)), TypeReferenceStep(w.value_checkpoint))
        end
    end
    return nothing
end

function _map_backward(w::AtomicWiring, iomap, reference; projection)
    reference === nothing && return nothing
    if w.bound_field === nothing
        # opaque ⇒ mirror the default mapper exactly (typed empty so the
        # strict-typing invariant holds on the whole-node case)
        reference isa EmptyReference && return _typed(w.intype)
        return make_introduced_reference(projection, w.intype, reference)
    end
    core = reference
    core isa EmptyReference && return _typed(w.intype)                  # whole ⇒ ::In
    if core isa ConcreteReference && core.head isa FieldReferenceStep
        fname = Symbol(core.head.name)
        if fname == w.value_field
            rest = core.tail
            if rest isa ConcreteReference && rest.head isa RangeReferenceStep
                return _prepend(rest, TypeReferenceStep(w.intype),
                                FieldReferenceStep(String(w.bound_field)), TypeReferenceStep(w.bound_type))
            end
            return nothing
        end
        # any other output field is projection-introduced ⇒ wrap in our own step
        return make_introduced_reference(projection, w.intype, reference)
    end
    return nothing
end

# ── node ──────────────────────────────────────────────────────────────────────
#
# Peel the one step this projection owns (.input[i] ↔ .children[i]) and delegate
# the tail to child i's own mapper through the stored child iomap (School A). A
# `proj(^(p), …)` head is this projection's own introduced output (a delimiter /
# structural position) — kept wrapped forward, produced by the reader fallback.

function _map_forward(w::NodeWiring, iomap, reference; projection)
    reference === nothing && return nothing
    core = reference
    core isa EmptyReference && return _typed(w.outtype)                 # whole ⇒ ::Out
    if is_introduced_reference(core, projection)
        return reference                                                   # keep wrapped
    end
    if core isa ConcreteReference && core.head isa FieldReferenceStep && core.head.name == String(w.coll_input_field)
        after = core.tail
        if after isa ConcreteReference && after.head isa RangeReferenceStep
            child_i = after.head.start + 1
            ims = iomap.child_iomaps
            1 <= child_i <= length(ims) || return nothing
            child = ims[child_i]
            inner = map_reference_forward(child.projection, child, after.tail)
            inner === nothing && return nothing
            return _prepend(inner, TypeReferenceStep(w.outtype), FieldReferenceStep(String(w.children_field)),
                            TypeReferenceStep(get_children_container_type()), ElementReferenceStep(child_i))
        end
    end
    return nothing
end

function _map_backward(w::NodeWiring, iomap, reference; projection)
    reference === nothing && return nothing
    core = reference
    core isa EmptyReference && return _typed(w.intype)                  # whole ⇒ ::In
    if core isa ConcreteReference && core.head isa FieldReferenceStep && core.head.name == String(w.children_field)
        after = core.tail
        if after isa ConcreteReference && after.head isa RangeReferenceStep
            child_i = after.head.start + 1
            ims = iomap.child_iomaps
            1 <= child_i <= length(ims) || return nothing
            inner = _map_child_backward(ims[child_i], after.tail)
            inner === nothing && return nothing
            # Structural boundary: emit a clean, checkpoint-free input path (matches the
            # canonical walk and what clicks produce), so navigation reaches every
            # caret. The child's tail is stripped of its checkpoints before splicing.
            return _prepend(_strip_checkpoints(inner), FieldReferenceStep(String(w.coll_input_field)), ElementReferenceStep(child_i))
        end
    end
    return nothing
end

# ── fixed-children node (e.g. an object key/value pair node) ───────────────────
#
# References here are relative to the element (input = the entry, output = the pair
# node). The enclosing collection mapper prepends `.children[i]`. A KeySlot's child
# is a leaf whose value carries the bound field: a whole-key reference maps to the
# whole child leaf, a char reference to `.children[k].<value_field>`. A ProjectSlot's child
# is delegated through the per-slot stored iomap.

# Shared slot-vector mappers. `project_child(fname)` returns the current child iomap
# for a `ProjectSlot` (the store is a Dict in the fixed case, in the reactive state in
# the conditional case); SubNodeSlots carry their own embedded iomap.
function _slots_forward(slots, project_child, children_field, outtype, reference)
    reference === nothing && return nothing
    core = reference
    core isa EmptyReference && return _typed(outtype)                   # whole ⇒ ::Out
    if core isa ConcreteReference && core.head isa FieldReferenceStep
        fname = Symbol(core.head.name)
        for (k, slot) in enumerate(slots)
            if slot isa KeySlot && slot.in_field === fname
                inner = core.tail
                inner isa EmptyReference &&
                    return _path(FieldReferenceStep(String(children_field)), ElementReferenceStep(k))
                return _prepend(inner, FieldReferenceStep(String(children_field)),
                                ElementReferenceStep(k), FieldReferenceStep(String(slot.value_field)))
            elseif slot isa ProjectSlot && slot.in_field === fname
                child = project_child(fname)
                inner = map_reference_forward(child.projection, child, core.tail)
                inner === nothing && return nothing
                return _prepend(inner, FieldReferenceStep(String(children_field)), ElementReferenceStep(k))
            elseif slot isa SubNodeSlot
                # The sub-node's mapper owns the same parent input; delegate the whole
                # reference and, on a hit, prepend this sub-node's `.children[k]` hop.
                inner = map_reference_forward(slot.iomap.projection, slot.iomap, reference)
                inner === nothing && continue
                return _prepend(inner, FieldReferenceStep(String(children_field)), ElementReferenceStep(k))
            end
        end
    end
    return nothing
end

function _slots_backward(slots, project_child, children_field, intype, reference)
    reference === nothing && return nothing
    core = reference
    core isa EmptyReference && return _typed(intype)                    # whole ⇒ ::In
    if core isa ConcreteReference && core.head isa FieldReferenceStep && core.head.name == String(children_field)
        after = core.tail
        if after isa ConcreteReference && after.head isa RangeReferenceStep
            k = after.head.start + 1
            1 <= k <= length(slots) || return nothing
            slot = slots[k]
            leaf_path = after.tail
            if slot isa KeySlot
                leaf_path isa EmptyReference &&
                    return _path(FieldReferenceStep(String(slot.in_field)))     # whole key leaf ⇒ .key
                lp = leaf_path
                if lp isa ConcreteReference && lp.head isa FieldReferenceStep &&
                   lp.head.name == String(slot.value_field)
                    return _prepend(lp.tail, FieldReferenceStep(String(slot.in_field)))   # leaf char ⇒ .key char
                end
                return nothing
            elseif slot isa ProjectSlot
                inner = _map_child_backward(project_child(slot.in_field), leaf_path)
                inner === nothing && return nothing
                return _prepend(inner, FieldReferenceStep(String(slot.in_field)))
            elseif slot isa SubNodeSlot
                # A *whole-element* selection of an introduced grouping sub-node (e.g.
                # a keyword-header node's leading token) has no input pre-image;
                # delegating maps ∅ back to the whole parent (∅), colliding with the
                # root and stalling tree navigation. Represent it as an opaque
                # structural position — a ProjectionReferenceStep into this node's output —
                # so it round-trips distinctly (forward via `is_introduced_reference`;
                # the render stage renders it transparently). A *deeper*
                # selection delegates: its `leaf_path` may resolve to a real child.
                leaf_path isa EmptyReference &&
                    return make_introduced_reference(slot.iomap.projection, intype, reference)
                return map_reference_backward(slot.iomap.projection, slot.iomap, leaf_path)
            else
                return nothing                                             # introduced
            end
        end
    end
    return nothing
end

# A `ProjectionReferenceStep(^(p), …)` head is this projection's own introduced output
# (a delimiter / structural position with no input pre-image) — keep it wrapped
# forward, as the `_map_forward` of a node, a mixed and an inline wiring does. Without
# this the cursor on an introduced token of a fixed/conditional node fails to
# forward-project (selection → nothing), so no caret renders and relative navigation
# and typein die (a keyword node's leading/operator tokens are all such positions).
_map_forward(w::FixedNodeWiring, iomap, reference; projection) =
    is_introduced_reference(reference, projection) ? reference :
    _slots_forward(w.slots, fn -> iomap.child_iomaps[fn][], w.children_field, w.outtype, reference)
_map_backward(w::FixedNodeWiring, iomap, reference; projection) =
    _slots_backward(w.slots, fn -> iomap.child_iomaps[fn][], w.children_field, w.intype, reference)

# Conditional node: read the current (slots, store) from the reactive state cell.
_map_forward(w::ConditionalNodeWiring, iomap, reference; projection) =
    is_introduced_reference(reference, projection) ? reference :
    (st = iomap.child_iomaps; _slots_forward(st[1], fn -> st[2][fn][], w.children_field, w.outtype, reference))
_map_backward(w::ConditionalNodeWiring, iomap, reference; projection) =
    (st = iomap.child_iomaps; _slots_backward(st[1], fn -> st[2][fn][], w.children_field, w.intype, reference))

# ── mixed node (fixed prefix + spliced collection) ─────────────────────────────
#
# Combines the fixed-children KeySlot/ProjectSlot handling (prefix children) with
# the node collection delegation (trailing children), offset by the prefix length.
# `.prefix_field{k}` ↔ `.children[slot].<value_field>{k}`; `.coll_field[i].tail` ↔
# `.children[prefix_len+i].tail` (delegated). Paths are plain (checkpoint-free),
# matching the surrounding node mappers.

function _map_forward(w::MixedNodeWiring, iomap, reference; projection)
    reference === nothing && return nothing
    core = reference
    core isa EmptyReference && return _typed(w.outtype)
    if is_introduced_reference(core, projection)
        return reference
    end
    (core isa ConcreteReference && core.head isa FieldReferenceStep) || return nothing
    fname = Symbol(core.head.name)
    for (k, slot) in enumerate(w.prefix_slots)
        if slot isa KeySlot && slot.in_field === fname
            inner = core.tail
            inner isa EmptyReference &&
                return _path(FieldReferenceStep(String(w.children_field)), ElementReferenceStep(k))
            return _prepend(inner, FieldReferenceStep(String(w.children_field)), ElementReferenceStep(k),
                            FieldReferenceStep(String(slot.value_field)))
        elseif slot isa ProjectSlot && slot.in_field === fname
            child = iomap.child_iomaps.prefix[fname][]
            inner = map_reference_forward(child.projection, child, core.tail)
            inner === nothing && return nothing
            return _prepend(inner, FieldReferenceStep(String(w.children_field)), ElementReferenceStep(k))
        end
    end
    if fname === w.coll_field
        after = core.tail
        if after isa ConcreteReference && after.head isa RangeReferenceStep
            i = after.head.start + 1
            ims = iomap.child_iomaps.coll[]
            1 <= i <= length(ims) || return nothing
            child_i = length(w.prefix_slots) + i
            after.tail isa EmptyReference &&
                return _path(FieldReferenceStep(String(w.children_field)), ElementReferenceStep(child_i))
            inner = map_reference_forward(ims[i].projection, ims[i], after.tail)
            inner === nothing && return nothing
            return _prepend(inner, FieldReferenceStep(String(w.children_field)), ElementReferenceStep(child_i))
        end
    end
    return nothing
end

function _map_backward(w::MixedNodeWiring, iomap, reference; projection)
    reference === nothing && return nothing
    core = reference
    core isa EmptyReference && return _typed(w.intype)
    (core isa ConcreteReference && core.head isa FieldReferenceStep &&
     core.head.name == String(w.children_field)) || return nothing
    after = core.tail
    (after isa ConcreteReference && after.head isa RangeReferenceStep) || return nothing
    k = after.head.start + 1
    leaf_path = after.tail
    n_prefix = length(w.prefix_slots)
    if k <= n_prefix
        slot = w.prefix_slots[k]
        if slot isa KeySlot
            leaf_path isa EmptyReference &&
                return _path(FieldReferenceStep(String(slot.in_field)))
            lp = leaf_path
            if lp isa ConcreteReference && lp.head isa FieldReferenceStep &&
               lp.head.name == String(slot.value_field)
                return _prepend(lp.tail, FieldReferenceStep(String(slot.in_field)))
            end
            return nothing
        elseif slot isa ProjectSlot
            inner = _map_child_backward(iomap.child_iomaps.prefix[slot.in_field][], leaf_path)
            inner === nothing && return nothing
            return _prepend(inner, FieldReferenceStep(String(slot.in_field)))
        else
            return nothing
        end
    else
        i = k - n_prefix
        ims = iomap.child_iomaps.coll[]
        1 <= i <= length(ims) || return nothing
        leaf_path isa EmptyReference &&
            return _path(FieldReferenceStep(String(w.coll_field)), ElementReferenceStep(i))
        inner = _map_child_backward(ims[i], leaf_path)
        inner === nothing && return nothing
        return _prepend(_strip_checkpoints(inner), FieldReferenceStep(String(w.coll_field)), ElementReferenceStep(i))
    end
end

# ── inline node (computed token leaves; one bound token, rest decorative) ───────
#
# Only the bound token is addressable: `.bound_field{k} ↔ .children[bound_index].
# <value_field>{k}`, whole `.bound_field ↔ .children[bound_index]`. Decorative tokens have
# no input pre-image, so a cursor on one is left to the consumer's flat-offset
# reader (returns nothing here).

function _map_forward(w::InlineWiring, iomap, reference; projection)
    reference === nothing && return nothing
    core = reference
    core isa EmptyReference && return _typed(w.outtype)
    if is_introduced_reference(core, projection)
        return reference
    end
    if core isa ConcreteReference && core.head isa FieldReferenceStep && Symbol(core.head.name) === w.bound_field
        inner = core.tail
        inner isa EmptyReference &&
            return _path(FieldReferenceStep(String(w.children_field)), ElementReferenceStep(w.bound_index))
        return _prepend(inner, FieldReferenceStep(String(w.children_field)),
                        ElementReferenceStep(w.bound_index), FieldReferenceStep(String(w.value_field)))
    end
    return nothing
end

function _map_backward(w::InlineWiring, iomap, reference; projection)
    reference === nothing && return nothing
    core = reference
    core isa EmptyReference && return _typed(w.intype)
    (core isa ConcreteReference && core.head isa FieldReferenceStep &&
     core.head.name == String(w.children_field)) || return nothing
    after = core.tail
    (after isa ConcreteReference && after.head isa RangeReferenceStep) || return nothing
    after.head.start + 1 == w.bound_index || return nothing       # decorative ⇒ flat fallback
    leaf_path = after.tail
    leaf_path isa EmptyReference &&
        return _path(FieldReferenceStep(String(w.bound_field)))
    lp = leaf_path
    if lp isa ConcreteReference && lp.head isa FieldReferenceStep &&
       lp.head.name == String(w.value_field)
        return _prepend(lp.tail, FieldReferenceStep(String(w.bound_field)))
    end
    return nothing
end

# ── section-grouped node ───────────────────────────────────────────────────────
#
# `.field[i].tail ↔ .children[sec].children[i].tail`, where `sec` is the field's
# index among the *non-empty* sections (from the stored section iomaps). Whole
# section `.field ↔ .children[sec]`, whole node ∅ ↔ ∅. The wrapper's children field
# is the same as the outer node's (both are the same output node type).

function _map_forward(w::SectionsWiring, iomap, reference; projection)
    reference === nothing && return nothing
    secs = iomap.child_iomaps
    core = reference
    core isa EmptyReference && return _typed(w.outtype)
    if is_introduced_reference(core, projection)
        return reference
    end
    (core isa ConcreteReference && core.head isa FieldReferenceStep) || return nothing
    field = Symbol(core.head.name)
    sec_i = findfirst(s -> s.field === field, secs)
    sec_i === nothing && return nothing
    cf = String(w.children_field)
    rest = core.tail
    rest isa EmptyReference && return _path(FieldReferenceStep(cf), ElementReferenceStep(sec_i))
    (rest isa ConcreteReference && rest.head isa RangeReferenceStep) || return nothing
    entry_i = rest.head.start + 1
    entries = secs[sec_i].entries
    1 <= entry_i <= length(entries) || return nothing
    entry_rest = rest.tail
    entry_rest isa EmptyReference &&
        return _path(FieldReferenceStep(cf), ElementReferenceStep(sec_i), FieldReferenceStep(cf), ElementReferenceStep(entry_i))
    inner = map_reference_forward(entries[entry_i].projection, entries[entry_i], entry_rest)
    inner === nothing && return nothing
    return _prepend(inner, FieldReferenceStep(cf), ElementReferenceStep(sec_i), FieldReferenceStep(cf), ElementReferenceStep(entry_i))
end

function _map_backward(w::SectionsWiring, iomap, reference; projection)
    reference === nothing && return nothing
    secs = iomap.child_iomaps
    cf = String(w.children_field)
    core = reference
    core isa EmptyReference && return _typed(w.intype)
    (core isa ConcreteReference && core.head isa FieldReferenceStep && core.head.name == cf) || return nothing
    after = core.tail
    (after isa ConcreteReference && after.head isa RangeReferenceStep) || return nothing
    sec_i = after.head.start + 1
    1 <= sec_i <= length(secs) || return nothing
    sec = secs[sec_i]
    rest = after.tail
    rest isa EmptyReference && return _path(FieldReferenceStep(String(sec.field)))
    rest2 = rest
    (rest2 isa ConcreteReference && rest2.head isa FieldReferenceStep && rest2.head.name == cf) || return nothing
    after2 = rest2.tail
    (after2 isa ConcreteReference && after2.head isa RangeReferenceStep) || return nothing
    entry_i = after2.head.start + 1
    1 <= entry_i <= length(sec.entries) || return nothing
    inner_path = after2.tail
    inner_path isa EmptyReference &&
        return _path(FieldReferenceStep(String(sec.field)), ElementReferenceStep(entry_i))
    translated = _map_child_backward(sec.entries[entry_i], inner_path)
    translated === nothing && return nothing
    return _prepend(_strip_checkpoints(translated), FieldReferenceStep(String(sec.field)), ElementReferenceStep(entry_i))
end

# ── readers ───────────────────────────────────────────────────────────────────

# ── Recursive gesture reader (delegate to the selected child, lift the op) ──────
#
# A raw authoring gesture (a `KeyPress`/`KeyDown` the upstream Text/Syntax layers
# declined) is delegated to the projection of the **selected child** element, and
# the child's operation is lifted back into this node's input domain by prepending
# the input step that leads to that child (`entries[i].value`, `elements[i]`, …).
# A node handles the gesture itself — via its document's `@gestures`
# (`read_gesture`) — only when the child declines: innermost-first, with bubbling
# to the nearest enclosing structural node. This is the reader-side mirror of the
# recursive printer (`collection`/`project`) and the recursive operation reader
# (`map_reference_backward` below), and reuses the same lift (`reroot_operation`)
# the container projections use. The general
# principle is documented in package/kernel/doc/projection-system.md.
#
# Each level reads its own `iomap.input.selection`: `set_selection!` propagates the
# selection down the document tree, so every focused node already holds its own
# subtree-relative path (the root the full path, a nested object its relative one).

# The input step(s) into the focused child plus that child's iomap, derived from
# this node's input selection. `nothing` ⇒ the selection does not descend into a
# recursable child projection (a leaf cursor, a key cursor, or no selection), so
# the caller falls back to this node's own `read_gesture`.
_focused_child(::Any, iomap, sel) = nothing

function _focused_child(w::NodeWiring, iomap, sel)
    core = sel
    (core isa ConcreteReference && core.head isa FieldReferenceStep &&
     core.head.name == String(w.coll_input_field)) || return nothing
    after = core.tail
    (after isa ConcreteReference && after.head isa RangeReferenceStep) || return nothing
    i = after.head.start + 1
    ims = iomap.child_iomaps
    1 <= i <= length(ims) || return nothing
    (ims[i], (FieldReferenceStep(String(w.coll_input_field)), ElementReferenceStep(i)))
end

function _focused_child(w::FixedNodeWiring, iomap, sel)
    core = sel
    (core isa ConcreteReference && core.head isa FieldReferenceStep) || return nothing
    fname = Symbol(core.head.name)
    for slot in w.slots
        if slot isa ProjectSlot && slot.in_field === fname
            return (iomap.child_iomaps[fname][], (FieldReferenceStep(String(fname)),))
        elseif slot isa SubNodeSlot
            # Recurse: the sub-node shares the parent input, so the steps it reports
            # are already parent-relative.
            fc = _focused_child(slot.iomap.wiring, slot.iomap, sel)
            fc === nothing || return fc
        end
    end
    nothing   # KeySlot/IntroSlot ⇒ leaf, no child projection to recurse into
end

function _focused_child(w::ConditionalNodeWiring, iomap, sel)
    st = iomap.child_iomaps
    core = sel
    (core isa ConcreteReference && core.head isa FieldReferenceStep) || return nothing
    fname = Symbol(core.head.name)
    for slot in st[1]
        if slot isa ProjectSlot && slot.in_field === fname
            return (st[2][fname][], (FieldReferenceStep(String(fname)),))
        elseif slot isa SubNodeSlot
            fc = _focused_child(slot.iomap.wiring, slot.iomap, sel)
            fc === nothing || return fc
        end
    end
    nothing
end

function _focused_child(w::MixedNodeWiring, iomap, sel)
    core = sel
    (core isa ConcreteReference && core.head isa FieldReferenceStep) || return nothing
    fname = Symbol(core.head.name)
    for slot in w.prefix_slots
        slot isa ProjectSlot && slot.in_field === fname &&
            return (iomap.child_iomaps.prefix[fname][], (FieldReferenceStep(String(fname)),))
    end
    if fname === w.coll_field
        after = core.tail
        (after isa ConcreteReference && after.head isa RangeReferenceStep) || return nothing
        i = after.head.start + 1
        ims = iomap.child_iomaps.coll[]
        1 <= i <= length(ims) || return nothing
        return (ims[i], (FieldReferenceStep(String(w.coll_field)), ElementReferenceStep(i)))
    end
    nothing
end

function _focused_child(w::SectionsWiring, iomap, sel)
    core = sel
    (core isa ConcreteReference && core.head isa FieldReferenceStep) || return nothing
    fname = Symbol(core.head.name)
    after = core.tail
    (after isa ConcreteReference && after.head isa RangeReferenceStep) || return nothing
    i = after.head.start + 1
    for s in iomap.child_iomaps
        if s.field === fname
            1 <= i <= length(s.entries) || return nothing
            return (s.entries[i], (FieldReferenceStep(String(fname)), ElementReferenceStep(i)))
        end
    end
    nothing
end

"""
    find_template_value_retype(iomap::RuleIoMap, reference) -> Type | Nothing

The operation type that the leaf rule under `reference` makes of a text edit of
its bound value: the `retype` of its `bound`, or `nothing` when it has none.
`reference` is in the input domain of `iomap`, with no type checkpoints. A leaf
answers for an edit of its own bound field. A node descends into the child that
`reference` enters, so a leaf in a container retypes an edit as it does when it
is the document.
"""
function find_template_value_retype(iomap::RuleIoMap, reference)
    w = iomap.wiring
    if w isa AtomicWiring
        return reference isa ConcreteReference && reference.head isa FieldReferenceStep &&
               Symbol(reference.head.name) === w.bound_field ? w.retype : nothing
    end
    focused = _focused_child(w, iomap, reference)
    focused === nothing && return nothing
    child, steps = focused
    child isa RuleIoMap || return nothing
    rest = reference
    for _ in steps
        rest isa ConcreteReference || return nothing
        rest = rest.tail
    end
    find_template_value_retype(child, rest)
end

# Innermost-first, bubbling to the nearest enclosing structural node: delegate to the
# selected child's projection (lifting its operation back into this node's input
# domain), and only when the child declines fall back to this node's own reified
# gestures.
read_intent(p::Projection, iomap::RuleIoMap, evt::Union{KeyPress, KeyDown}) =
    _read_template_gesture(iomap, evt; recursion = nothing)

# The child reads the gesture with its own 4-argument reader, and with the
# `recursion` that printed it.
function _read_template_gesture(iomap::RuleIoMap, evt; recursion)
    input = iomap.input
    input isa Document || return nothing
    sel = getfield(input, :selection)[]
    if sel !== nothing
        fc = _focused_child(iomap.wiring, iomap, sel)
        if fc !== nothing
            child, steps = fc
            child_op = read_intent(child.projection, recursion, Intent(evt), child).operation
            child_op === nothing || return reroot_operation(child_op, steps)
        end
    end
    # Own-level handling: the nearest enclosing node's reified gestures, and the
    # override seam (a node that must special-case a gesture does so here).
    return read_gesture(input, evt)
end

# A gesture an output layer already turned into an operation. Only `override` bindings
# fire (`fire_gesture_bindings` skips the rest once `claimed !== nothing`), so this is
# inert for every ordinary gesture and the caller goes on to translate the claimed
# operation.
#
# The descent is a private walk over `RuleIoMap` children rather than the `read_intent`
# recursion the unclaimed path uses, for two reasons. A hand-written reader takes an
# *untyped* payload argument and would mistake a `ClaimedGesture` for an event; and the
# claimed operation is expressed in the *enclosing* stage's output vocabulary, so a
# child that translated it rather than declining would map a reference it does not own.
# Nothing is lost: only a template node hosts gestures, and gestures are all this is
# looking for.
function read_intent(p::Projection, iomap::RuleIoMap, c::ClaimedGesture)
    c.gesture isa Union{KeyPress, KeyDown} || return nothing
    return _read_override_gesture(iomap, c.gesture, c.operation)
end

function _read_override_gesture(iomap::RuleIoMap, evt, claimed)
    input = iomap.input
    input isa Document || return nothing
    sel = getfield(input, :selection)[]
    if sel !== nothing
        fc = _focused_child(iomap.wiring, iomap, sel)
        if fc !== nothing && fc[1] isa RuleIoMap
            child, steps = fc
            child_op = _read_override_gesture(child, evt, claimed)
            child_op === nothing || return reroot_operation(child_op, steps)
        end
    end
    return read_gesture(input, evt; claimed)
end

# @positional: the arity of the reader of the projection protocol. The macro
# emits a method of that shape.
"""
    read_template_intent(p, recursion, change::Intent, iomap) -> Intent

The 4-arg reader [`@projection_template`](@ref) emits for each template projection. It
offers this node's input domain the gesture *before* translating an operation the output
layers already produced for it — the seam an `override` binding fires through — and
otherwise behaves like the generic bridge in `ProjectionModule`. A key goes to the
reader of the focused child with `recursion`. The answer keeps the description and
the domain of `change`. This reader follows no route, so a change whose route names
a place below the input answers no operation.

Keyed on the concrete projection type rather than on `RuleIoMap`: the transparent
recursive and type-dispatching wrappers hand a leaf its own iomap
and already carry 4-arg methods of their own, so a method keyed on the iomap would be
ambiguous with every one of them.
"""
function read_template_intent(p, recursion, change::Intent, iomap)
    change.route isa ConcreteReference && return Intent(change.gesture, nothing)
    is_key = iomap isa RuleIoMap && change.gesture isa Union{KeyPress, KeyDown}
    if is_key && change.operation !== nothing
        override = read_intent(p, iomap, ClaimedGesture(change.gesture, change.operation))
        override === nothing ||
            return Intent(change.gesture, override, change.description, change.domain)
    end
    operation = change.operation !== nothing ? read_intent(p, iomap, change.operation) :
                is_key ? _read_template_gesture(iomap, change.gesture; recursion) :
                read_intent(p, iomap, change.gesture)
    return Intent(change.gesture, operation, change.description, change.domain)
end

# The `KeyPress`/`KeyDown` and `ReplaceSelectionOperation` disambiguations for
# the transparent recursive wrapper over `RuleIoMap` — together with the
# value-edit retype method for text-range replaces — all live in a higher
# package beside the reader defaults. That wrapper projection and that operation
# type are defined there, neither of which the kernel can name; the higher
# package imports `RuleIoMap` + `AtomicWiring` from this module to preserve the
# same dispatch behaviour.

# Whole-element selection: map back, else (node) the position is a structural
# introduced one with no input pre-image ⇒ wrap into this projection's own step
# (the domain-neutral counterpart of the Syntax flat-offset fallback).
function read_intent(p::Projection, iomap::RuleIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    iomap.wiring isa _INTRODUCING_WIRINGS || return nothing
    return ReplaceSelectionOperation(make_introduced_reference(p, iomap.input, op.path))
end

# ── Sugar ─────────────────────────────────────────────────────────────────────

"""
    @projection_template ProjName InType (p, doc) -> <builder body>

Emit `print_document(p::ProjName, recursion, doc::InType, ctx)` that runs the
builder through `print_template_rule`, and the matching 4-arg
[`read_template_intent`](@ref) reader — the seam an `override` gesture fires
through.
"""
macro projection_template(projname, intype, builder)
    builder = make_template_builder(builder)
    quote
        # Define the method with a *module-qualified* name so it always extends
        # the canonical `ProjectionModule.print_document` the type-dispatcher
        # calls, whatever the calling module imported. The unescaped
        # `ProjectionModule` hygiene-resolves to this macro's defining module,
        # which binds it. A bare `esc(:print_document)` would resolve the name in
        # the caller's module and, if that module had not imported the generic,
        # silently define a dead local one.
        function ProjectionModule.print_document(p::$(esc(projname)), recursion, doc::$(esc(intype)), ctx)
            $(print_template_rule)(p, recursion, doc, ctx, $(esc(builder)))
        end

        # Without this the projection falls to the generic bridge, which collapses the
        # `Intent` to a single payload and so can only ever translate a claimed
        # operation — the input domain never sees the key that caused it.
        function ProjectionModule.read_intent(p::$(esc(projname)), recursion, change::Intent, iomap)
            $(read_template_intent)(p, recursion, change, iomap)
        end
    end
end
