"""
    ProjectionTemplateModule

Builder-and-walk projection rules. A rule is an ordinary builder function
`(p, doc) -> output` that constructs the **real** output document with its real
constructor, except that at the positions needing special handling it drops in a
**marker** value:

- `bound(:field, T, render; retype=Op)` — a value bound to `doc.field::T`;
  `render` is the real renderable value placed there.
- `project(:field)` — delegate this child to its own projection (School A).
- `collection(:field[, element])` — a recursive children vector. *(node support
  is WIP; leaves are implemented first.)*

Because `@document` types store every field in a `Cell` with no type check, a
marker can sit in a real field (e.g. a `Bound` in a leaf's value slot). The engine
**walks the built value** by reflection (`fieldnames`), records the wiring, and
reconstructs a clean, marker-free output, so the projection API only ever sees a
real output document. Reference mapping is generic and data-driven from the
recorded wiring; nothing is generated per type.

The engine references **no output-domain type or field name**: fields are
classified by value (marker vs. not), and any non-`bound` output field is treated
as projection-introduced (a cursor on it wraps into this projection's own step).
An output domain is supported purely by writing builders that construct its
documents — no adapter or engine change.
"""
module ProjectionTemplateModule

import ..ReactiveModule: Cell
import ..CollectionModule: CellVector
import ..IoMapApiModule: IoMap
import ..ProjectionApiModule: map_reference_forward, map_reference_backward, projection_read, Projection,
                              projection_printer_recurse, as_change
import ..RecursiveProjectionModule: RecursiveProjection
import ..ReferenceModule: ConcreteReferencePath, EmptyReferencePath, FieldReference, RangeReference, ElementReference,
                          TypeReference, ProjectionReference, ReferencePath, Reference, skip_type_checkpoints
import ..PrinterContextModule: child_context
import ..OperationModule: ReplaceSelectionOperation
import ..PrimitiveModule: StringReplaceRangeOperation, NumberReplaceRangeOperation

export Bound, Project, Collection, bound, project, collection, RuleIoMap, var"@projection_template"

# ── Markers (build-time only; stripped before the output reaches the API) ─────

struct Bound;      input::Symbol; type::Any; render::Any; retype::Any; end
struct Project;    input::Symbol; end
struct Collection; input::Symbol; element::Any; end

bound(input::Symbol, T, render; retype=nothing) = Bound(input, T, render, retype)
project(input::Symbol) = Project(input)
collection(input::Symbol) = Collection(input, nothing)
collection(element, input::Symbol) = Collection(input, element)   # collection(:f) do x … end

# ── Wiring + IoMap ───────────────────────────────────────────────────────────

# What the walk recovers for a leaf: the (optional) bound field. Any *other*
# output field is projection-introduced, so the backward mapper proj-wraps a
# cursor on it without the engine needing to know the output domain's text type.
struct AtomicWiring
    intype::Any
    outtype::Any
    bound_field::Union{Symbol,Nothing}   # nothing ⇒ opaque (all-introduced) leaf
    bound_type::Any
    value_field::Union{Symbol,Nothing}   # output field carrying the bound value
    value_checkpoint::Any                # output field's element type (from the marker's render)
    retype::Any
end

# What the walk recovers for a node: which input field is the recursive
# collection and which output field holds the projected children. Per-child
# correspondence lives in the stored `child_iomaps` (School A).
struct NodeWiring
    intype::Any
    outtype::Any
    coll_input_field::Symbol             # input collection field, e.g. :elements
    children_field::Symbol               # output field holding the children, e.g. :children
end

# A fixed-children node (e.g. JsonObject's per-entry pair node): its children are
# a fixed list, each wired individually rather than a homogeneous collection.
# Such a node is produced by a `collection(:f) do x … end` element builder, walked
# per element, and delegated to by the enclosing collection mapper.
struct KeySlot;     in_field::Symbol; in_type::Any; checkpoint::Any; end  # child is a leaf: whole↔child, char↔child.value
struct ProjectSlot; in_field::Symbol; end                                 # child delegated (iomap in the store)
struct IntroSlot end                                                      # introduced child (keyword/delimiter)

struct FixedNodeWiring
    intype::Any
    outtype::Any
    children_field::Symbol               # output field holding the fixed children
    slots::Vector{Any}                   # KeySlot|ProjectSlot|IntroSlot per child index
end

struct RuleIoMap <: IoMap
    projection::Any
    input::Any
    output::Any
    wiring::Any
    child_iomaps::Any                    # Cell or nothing (nodes; WIP)
end

# ── Path helpers (build the exact shapes @reference/@reference_case produce) ───

_typed(T) = ConcreteReferencePath(TypeReference(T), EmptyReferencePath())
_path(steps...) = begin
    p = EmptyReferencePath()
    for i in length(steps):-1:1
        p = ConcreteReferencePath(steps[i], p)
    end
    p
end
# prepend `steps...` in front of an existing path tail
_prepend(tail::ReferencePath, steps...) = begin
    p = tail
    for i in length(steps):-1:1
        p = ConcreteReferencePath(steps[i], p)
    end
    p
end
# Remove every TypeReference checkpoint from a path. The JSON input boundary wants
# clean, checkpoint-free reference paths (see test_json_content_clicks_clean); a
# delegated child's backward result carries the child's canonical checkpoints
# (e.g. `::JsonNumber.value::Real`), so the collection mapper strips them when it
# splices the child's tail under `.elements[i]` / `.entries[i]`.
_strip_checkpoints(p::EmptyReferencePath) = p
_strip_checkpoints(p::ConcreteReferencePath) =
    p.head isa TypeReference ? _strip_checkpoints(p.tail) :
                               ConcreteReferencePath(p.head, _strip_checkpoints(p.tail))
_strip_checkpoints(x) = x

# ── The builder/walk printer ─────────────────────────────────────────────────

"""
    rule_print(p, recursion, doc, ctx, builder)

Build the marked output via `builder(p, doc)`, walk it to record the wiring,
strip the markers **in place** (replacing each with its real value and wiring the
selection cell), and return a `RuleIoMap`. `@document` outputs are mutable structs
of `Cell` fields, so the bound value's cell content is overwritten and the
selection cell is swapped directly — no copy.
"""
function rule_print(p, recursion, doc, ctx, builder)
    out = builder(p, doc)
    coll_field, coll = _find_collection(out)
    coll !== nothing && return _node_print(p, recursion, doc, ctx, out, coll_field, coll)
    # A node built with a raw children Vector (markers/leaves) but no Collection
    # marker is a top-level fixed-children node (e.g. a record rendered as a row of
    # bound/delegated/introduced leaves). Leaves have no such field.
    _has_fixed_children(out) && return _fixed_print(p, recursion, doc, ctx, out)
    return _atomic_print(p, doc, out)
end

_has_fixed_children(out) = any(fname -> getfield(out, fname)[] isa Vector, fieldnames(typeof(out)))

# Selection cell for a bound child leaf of a fixed node: lens `doc.<in_field>{k}`
# onto the leaf's own `.value{k}` span (the only shape `_leaf_cursor` understands);
# pass a proj-wrapped structural cursor through unchanged.
function _key_leaf_sel(doc, in_field::Symbol)
    fname = String(in_field)
    Cell(() -> begin
        sel = doc.selection
        sel isa ConcreteReferencePath && sel.head isa ProjectionReference && return sel
        core = skip_type_checkpoints(sel)
        if core isa ConcreteReferencePath && core.head isa FieldReference && core.head.name == fname
            return ConcreteReferencePath(FieldReference("value"), core.tail)
        end
        return nothing
    end)
end

# Locate a `Collection` marker among the built output's fields, if any.
function _find_collection(out)
    for fname in fieldnames(typeof(out))
        val = getfield(out, fname)[]
        val isa Collection && return (fname, val)
    end
    (nothing, nothing)
end

function _atomic_print(p, doc, out)
    wiring = _scan_atomic!(p, doc, out)
    iomap = RuleIoMap(p, doc, out, wiring, nothing)
    # Wire the output leaf's selection cell:
    #   opaque (no bound field) ⇒ forward-map (∅↔∅, else unmapped).
    #   bound on :value         ⇒ share doc's cell raw — the leaf's value span is
    #                             literally `.value`, so the input cursor already
    #                             reads as a leaf cursor (JSON/SQL fast path).
    #   bound on another field  ⇒ value-lens: forward-map `.field{k}` to the leaf's
    #                             `.value{k}` so `SyntaxToText._leaf_cursor` (which
    #                             only knows `.value`/`.open`/`.close`) renders it.
    setfield!(out, :selection,
        wiring.bound_field === nothing ? Cell(() -> map_reference_forward(p, nothing, doc.selection)) :
        wiring.bound_field === :value  ? getfield(doc, :selection) :
                                         Cell(() -> map_reference_forward(p, iomap, doc.selection)))
    iomap
end

# A node-shaped output: recurse over `doc.<input>` (School A), reconstruct the
# node with the projected children and a deferred selection cell, and store the
# child iomaps so the mappers can delegate each child's tail.
function _node_print(p, recursion, doc, ctx, out, children_field, coll)
    input_field = coll.input
    child_iomaps = if coll.element === nothing
        # homogeneous: each element projected by its own projection
        Cell(() -> [
            projection_printer_recurse(recursion, x,
                child_context(ctx, FieldReference(String(input_field)), ElementReference(i)))
            for (i, x) in enumerate(getproperty(doc, input_field))])
    else
        # templated: build a fixed-children node per element via the element builder
        Cell(() -> [
            _fixed_print(p, recursion, x,
                child_context(ctx, FieldReference(String(input_field)), ElementReference(i)),
                coll.element(x))
            for (i, x) in enumerate(getproperty(doc, input_field))])
    end
    iomap_cell = Cell(nothing)
    sel = Cell(() -> begin
        im = iomap_cell[]
        im === nothing && return nothing
        path = doc.selection
        path === nothing && return nothing
        map_reference_forward(p, im, path)
    end)
    children = CellVector(() -> [im.output for im in child_iomaps[]])
    setproperty!(out, children_field, children)   # replace the Collection marker with the real children
    setfield!(out, :selection, sel)
    wiring = NodeWiring(typeof(doc), typeof(out), input_field, children_field)
    iomap = RuleIoMap(p, doc, out, wiring, child_iomaps)
    iomap_cell[] = iomap
    return iomap
end

# Scan a leaf-shaped output for the (optional) `bound` marker and strip it in
# place to its real value. Fields are classified by *value*, so no output-domain
# field names are referenced: a non-marker field is left alone (and treated as
# introduced by the mapper).
function _scan_atomic!(p, doc, out)
    intype = typeof(doc); outtype = typeof(out)
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

# A fixed-children node built per element (e.g. JsonObject's pair node). Each child
# of its `children` vector is classified: a `project(:f)` marker → delegated child;
# a built leaf carrying a `bound` marker → key slot (its value holds a doc field);
# anything else → introduced. The element's own selection cells (set by the
# element builder, e.g. the entry selection and key→value remap) are left intact.
function _fixed_print(p, recursion, doc, ctx, out)
    children_field = _find_fixed_children(out)
    raw = getproperty(out, children_field)
    slots = Any[]; store = Dict{Symbol,Any}(); outputs = Any[]
    for child in raw
        if child isa Project
            im = projection_printer_recurse(recursion, getproperty(doc, child.input),
                                            child_context(ctx, FieldReference(String(child.input))))
            store[child.input] = im
            push!(slots, ProjectSlot(child.input))
            push!(outputs, im.output)
        elseif child isa Collection
            error("ProjectionTemplate: nested collection inside a fixed-children node is not supported")
        else
            w = _scan_atomic!(p, doc, child)   # strips a `bound` marker if present
            if w.bound_field === nothing
                push!(slots, IntroSlot())
            else
                # A bound child leaf renders its own cursor from its own selection
                # cell, which `_leaf_cursor` reads as `.value{k}`. Lens the element's
                # `.<bound_field>{k}` onto the leaf's `.value{k}` generically, so the
                # builder needn't hand-wire it (this replaces JSON's `_entry_key_sel`).
                setfield!(child, :selection, _key_leaf_sel(doc, w.bound_field))
                push!(slots, KeySlot(w.bound_field, w.bound_type, w.value_checkpoint))
            end
            push!(outputs, child)
        end
    end
    setproperty!(out, children_field, CellVector(Cell[Cell(o) for o in outputs]))
    # The fixed node is a real output node, so its selection cell must hold an
    # *output* path: forward-map the element's input selection through this node's
    # own wiring (deferred-iomap trick, as the top node does).
    iomap_cell = Cell(nothing)
    setfield!(out, :selection, Cell(() -> begin
        im = iomap_cell[]
        im === nothing && return nothing
        sel = doc.selection
        sel === nothing && return nothing
        map_reference_forward(p, im, sel)
    end))
    im = RuleIoMap(p, doc, out, FixedNodeWiring(typeof(doc), typeof(out), children_field, slots), store)
    iomap_cell[] = im
    return im
end

function _find_fixed_children(out)
    for fname in fieldnames(typeof(out))
        getfield(out, fname)[] isa Vector && return fname
    end
    error("ProjectionTemplate: fixed-children node has no children vector")
end

# ── Generic, data-driven mappers (one method, all template projections) ───────

function map_reference_forward(p::Projection, iomap::RuleIoMap, reference)
    w = iomap.wiring
    w isa AtomicWiring    && return _atomic_forward(p, w, reference)
    w isa NodeWiring      && return _node_forward(p, w, iomap, reference)
    w isa FixedNodeWiring && return _fixed_forward(p, w, iomap, reference)
    return nothing
end

function map_reference_backward(p::Projection, iomap::RuleIoMap, reference)
    w = iomap.wiring
    w isa AtomicWiring    && return _atomic_backward(p, w, reference)
    w isa NodeWiring      && return _node_backward(p, w, iomap, reference)
    w isa FixedNodeWiring && return _fixed_backward(p, w, iomap, reference)
    return nothing
end

# ── atomic (leaf) ─────────────────────────────────────────────────────────────

function _atomic_forward(p, w, reference)
    reference === nothing && return nothing
    core = skip_type_checkpoints(reference)
    # unwrap this projection's own introduced step (both opaque & transparent)
    if core isa ConcreteReferencePath && core.head isa ProjectionReference && core.head.projection === p
        return core.head.output_path
    end
    if w.bound_field === nothing
        # opaque ⇒ mirror the default mapper: ∅ ⇒ ∅, otherwise unmapped
        core isa EmptyReferencePath && return EmptyReferencePath()
        return nothing
    end
    core isa EmptyReferencePath && return _typed(w.outtype)                 # whole ⇒ ::Out
    if core isa ConcreteReferencePath && core.head isa FieldReference && core.head.name == String(w.bound_field)
        rest = skip_type_checkpoints(core.tail)
        if rest isa ConcreteReferencePath && rest.head isa RangeReference
            return _prepend(rest, TypeReference(w.outtype),
                            FieldReference(String(w.value_field)), TypeReference(w.value_checkpoint))
        end
    end
    return nothing
end

function _atomic_backward(p, w, reference)
    reference === nothing && return nothing
    if w.bound_field === nothing
        # opaque ⇒ mirror the default mapper exactly
        reference isa EmptyReferencePath && return EmptyReferencePath()
        return _path(ProjectionReference(p, reference))
    end
    core = skip_type_checkpoints(reference)
    core isa EmptyReferencePath && return _typed(w.intype)                  # whole ⇒ ::In
    if core isa ConcreteReferencePath && core.head isa FieldReference
        fname = Symbol(core.head.name)
        if fname == w.value_field
            rest = skip_type_checkpoints(core.tail)
            if rest isa ConcreteReferencePath && rest.head isa RangeReference
                return _prepend(rest, TypeReference(w.intype),
                                FieldReference(String(w.bound_field)), TypeReference(w.bound_type))
            end
            return nothing
        end
        # any other output field is projection-introduced ⇒ wrap in our own step
        return _path(TypeReference(w.intype), ProjectionReference(p, reference))
    end
    return nothing
end

# ── node ──────────────────────────────────────────────────────────────────────
#
# Peel the one step this projection owns (.input[i] ↔ .children[i]) and delegate
# the tail to child i's own mapper through the stored child iomap (School A). A
# `proj(^(p), …)` head is this projection's own introduced output (a delimiter /
# structural position) — kept wrapped forward, produced by the reader fallback.

function _node_forward(p, w, iomap, reference)
    reference === nothing && return nothing
    core = skip_type_checkpoints(reference)
    core isa EmptyReferencePath && return _typed(w.outtype)                 # whole ⇒ ::Out
    if core isa ConcreteReferencePath && core.head isa ProjectionReference && core.head.projection === p
        return reference                                                   # keep wrapped
    end
    if core isa ConcreteReferencePath && core.head isa FieldReference && core.head.name == String(w.coll_input_field)
        after = skip_type_checkpoints(core.tail)
        if after isa ConcreteReferencePath && after.head isa RangeReference
            child_i = after.head.start + 1
            ims = iomap.child_iomaps[]
            1 <= child_i <= length(ims) || return nothing
            child = ims[child_i]
            inner = map_reference_forward(child.projection, child, after.tail)
            inner === nothing && return nothing
            return _prepend(inner, TypeReference(w.outtype), FieldReference(String(w.children_field)),
                            TypeReference(CellVector), ElementReference(child_i))
        end
    end
    return nothing
end

function _node_backward(p, w, iomap, reference)
    reference === nothing && return nothing
    core = skip_type_checkpoints(reference)
    core isa EmptyReferencePath && return _typed(w.intype)                  # whole ⇒ ::In
    if core isa ConcreteReferencePath && core.head isa FieldReference && core.head.name == String(w.children_field)
        after = skip_type_checkpoints(core.tail)
        if after isa ConcreteReferencePath && after.head isa RangeReference
            child_i = after.head.start + 1
            ims = iomap.child_iomaps[]
            1 <= child_i <= length(ims) || return nothing
            child = ims[child_i]
            inner = map_reference_backward(child.projection, child, after.tail)
            inner === nothing && return nothing
            # JSON boundary: emit a clean, checkpoint-free input path (matches the
            # canonical walk and what clicks produce), so navigation reaches every
            # caret. The child's tail is stripped of its checkpoints before splicing.
            return _prepend(_strip_checkpoints(inner), FieldReference(String(w.coll_input_field)), ElementReference(child_i))
        end
    end
    return nothing
end

# ── fixed-children node (e.g. a JsonObject pair node) ──────────────────────────
#
# References here are relative to the element (input = the entry, output = the pair
# node). The enclosing collection mapper prepends `.children[i]`. A KeySlot's child
# is a leaf whose value carries the bound field: a whole-key reference maps to the
# whole child leaf, a char reference to `.children[k].value`. A ProjectSlot's child
# is delegated through the per-slot stored iomap.

function _fixed_forward(p, w, iomap, reference)
    reference === nothing && return nothing
    core = skip_type_checkpoints(reference)
    core isa EmptyReferencePath && return _typed(w.outtype)                 # whole entry ⇒ ::Out
    if core isa ConcreteReferencePath && core.head isa FieldReference
        fname = Symbol(core.head.name)
        for (k, slot) in enumerate(w.slots)
            if slot isa KeySlot && slot.in_field === fname
                inner = core.tail
                skip_type_checkpoints(inner) isa EmptyReferencePath &&
                    return _path(FieldReference(String(w.children_field)), ElementReference(k))
                return _prepend(inner, FieldReference(String(w.children_field)),
                                ElementReference(k), FieldReference("value"))
            elseif slot isa ProjectSlot && slot.in_field === fname
                child = iomap.child_iomaps[fname]
                inner = map_reference_forward(child.projection, child, core.tail)
                inner === nothing && return nothing
                return _prepend(inner, FieldReference(String(w.children_field)), ElementReference(k))
            end
        end
    end
    return nothing
end

function _fixed_backward(p, w, iomap, reference)
    reference === nothing && return nothing
    core = skip_type_checkpoints(reference)
    core isa EmptyReferencePath && return _typed(w.intype)                  # whole pair ⇒ ::In
    if core isa ConcreteReferencePath && core.head isa FieldReference && core.head.name == String(w.children_field)
        after = skip_type_checkpoints(core.tail)
        if after isa ConcreteReferencePath && after.head isa RangeReference
            k = after.head.start + 1
            1 <= k <= length(w.slots) || return nothing
            slot = w.slots[k]
            leaf_path = after.tail
            if slot isa KeySlot
                skip_type_checkpoints(leaf_path) isa EmptyReferencePath &&
                    return _path(FieldReference(String(slot.in_field)))     # whole key leaf ⇒ .key
                lp = skip_type_checkpoints(leaf_path)
                if lp isa ConcreteReferencePath && lp.head isa FieldReference && lp.head.name == "value"
                    return _prepend(lp.tail, FieldReference(String(slot.in_field)))   # .value char ⇒ .key char
                end
                return nothing
            elseif slot isa ProjectSlot
                child = iomap.child_iomaps[slot.in_field]
                inner = map_reference_backward(child.projection, child, leaf_path)
                inner === nothing && return nothing
                return _prepend(inner, FieldReference(String(slot.in_field)))
            else
                return nothing                                             # introduced
            end
        end
    end
    return nothing
end

# ── readers ───────────────────────────────────────────────────────────────────

# Value-edit retype (atomic) + plain String/Number retargeting (both shapes).
function projection_read(p::Projection, iomap::RuleIoMap, op::StringReplaceRangeOperation)
    w = iomap.wiring
    new_ref = map_reference_backward(p, iomap, op.reference)
    new_ref === nothing && return nothing
    if w isa AtomicWiring && w.retype !== nothing
        return w.retype(new_ref, op.replacement)
    end
    return StringReplaceRangeOperation(new_ref, op.replacement)
end

# Whole-element selection: map back, else (node) the position is a structural
# introduced one with no input pre-image ⇒ wrap into this projection's own step
# (the domain-neutral counterpart of the Syntax flat-offset fallback).
function projection_read(p::Projection, iomap::RuleIoMap, op::ReplaceSelectionOperation)
    result = map_reference_backward(p, iomap, op.path)
    result !== nothing && return ReplaceSelectionOperation(result)
    iomap.wiring isa NodeWiring || return nothing
    return ReplaceSelectionOperation(_path(ProjectionReference(p, op.path)))
end

# Disambiguation: the two generic RuleIoMap readers above (`Projection`) and the
# transparent RecursiveProjection wrapper's `projection_read(rp, iomap, payload)`
# both match `(RecursiveProjection, RuleIoMap, op)`, neither more specific. One
# concrete-typed method per op (not a Union, which would still tie with the
# `Projection`/exact-op reader on arg 3) defers to the wrapper, which threads the
# read into its child projection.
projection_read(rp::RecursiveProjection, iomap::RuleIoMap, op::StringReplaceRangeOperation) =
    projection_read(rp, nothing, as_change(op), iomap).operation
projection_read(rp::RecursiveProjection, iomap::RuleIoMap, op::ReplaceSelectionOperation) =
    projection_read(rp, nothing, as_change(op), iomap).operation

# ── Sugar ─────────────────────────────────────────────────────────────────────

"""
    @projection_template ProjName InType (p, doc) -> <builder body>

Emit `projection_print(p::ProjName, recursion, doc::InType, ctx)` that runs the
builder through `rule_print`.
"""
macro projection_template(projname, intype, builder)
    quote
        function $(esc(:projection_print))(p::$(esc(projname)), recursion, doc::$(esc(intype)), ctx)
            $(rule_print)(p, recursion, doc, ctx, $(esc(builder)))
        end
    end
end

end # module
