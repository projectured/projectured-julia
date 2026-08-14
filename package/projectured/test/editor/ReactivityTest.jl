# ═══════════════════════════════════════════════════════════════════════════
# test/editor/ReactivityTest.jl
#
# The under-invalidation property: touch any field of a projection's input, and
# at least one cell of that projection's output must go invalid.
#
# The bug this catches does not make the output WRONG, it makes it STALE. No
# assertion trips and nothing errors; the pixels are simply from a document that
# no longer exists. Every existing printer test re-prints from scratch, and a
# re-print always looks correct, so no suite can see it.
#
# The companion property — touching one field must NOT invalidate everything —
# is `PrinterLocalityTest.jl`. That file owns the over-invalidation bound, the
# cell collector (`_collect_locality!`), and the object-identity diff. This file
# owns the other bound and reuses all three. The two together are the plan in
# plan/pending/reactivity-property-testing.md.
#
# The unit is an IoMap node, not a document leaf, because an IoMap is exactly
# `(projection, input, output)`: a failure then names the projection that froze
# instead of saying "something in this example went stale".
# ═══════════════════════════════════════════════════════════════════════════

# ── Phase 1: the IoMap tree ──────────────────────────────────────────────────

"""
    IoMapNode

One node of an IoMap tree: the IoMap itself, the projection responsible for it,
its input and its output, plus how the walk reached it.

`path` is the chain of field names taken from the root (`output.child_iomaps[3]`
style), so a failure message can name the node without the reader having to
re-run the walk.
"""
struct IoMapNode
    iomap::IoMap
    projection::Any
    input::Any
    output::Any
    path::String
    depth::Int
end

Base.show(io::IO, n::IoMapNode) =
    print(io, "IoMapNode(", nameof(typeof(n.projection)), " at ", n.path, ")")

# A child IoMap is held in a FIELD of its parent — directly, or inside a Vector,
# and in either case possibly behind a Cell. The search covers the parent's own
# fields and one level into a Vector. It never walks the output document: an
# IoMap found inside a rendered tree is not a child of this node in the
# projection sense, and the output of a whole example is large.
#
# The field names are NOT enumerated, and that is the point. The loaded set holds
# more than forty IoMap types using at least twelve different names for the same
# relation — `child_iomaps`, `inner_iomap`, `step_iomaps`, `content_iomap`,
# `content_iomaps`, `element_iomaps`, `child_iomap`, `root_iomap`,
# `window_iomaps`, `palette_iomap`, `log_iomap`, `slice_iomap`. A name list would
# be wrong the day a projection declares its own IoMap, and it would fail
# silently: the walk would report a tree one node deep and the property would
# pass everywhere by measuring nothing.
function _iomap_children(iomap::IoMap)
    children = Tuple{IoMap,String}[]
    for fname in fieldnames(typeof(iomap))
        fname in (:projection, :input, :output) && continue
        value = try
            getproperty(iomap, fname)
        catch
            continue
        end
        value = _unwrap(value)
        if value isa IoMap
            push!(children, (value, "." * string(fname)))
        elseif value isa AbstractVector
            for (i, element) in enumerate(value)
                element = _unwrap(element)
                element isa IoMap || continue
                push!(children, (element, "." * string(fname) * "[$i]"))
            end
        end
    end
    children
end

# A field or a vector slot may hold the IoMap behind a Cell —
# `ChainingProjectionIoMap.step_iomaps` is a `Vector{Cell}`. Reading the cell
# forces it, which is what the walk wants: an unforced child is not yet a node.
_unwrap(x) = x isa Cell ? x[] : x

"""
    iomap_nodes(root::IoMap) -> Vector{IoMapNode}

Every node of the IoMap tree under `root`, in tree order, the root first.

Reads through the IoMap's cells, so a node whose children are a computed cell is
forced. An IoMap reached twice is reported once: a projection may hand the same
child IoMap to two parents, and the property would then be measured twice on one
object for no gain.
"""
function iomap_nodes(root::IoMap; maxdepth::Int=_WALK_MAX_DEPTH)
    nodes = IoMapNode[]
    seen = Set{UInt64}()
    _iomap_nodes!(nodes, seen, root, "root", 0, maxdepth)
    nodes
end

function _iomap_nodes!(nodes, seen, iomap::IoMap, path::String, depth::Int, maxdepth::Int)
    depth > maxdepth && return
    id = objectid(iomap)
    id in seen && return
    push!(seen, id)
    push!(nodes, IoMapNode(iomap,
                           get_iomap_projection(iomap),
                           get_iomap_input(iomap),
                           get_iomap_output(iomap),
                           path, depth))
    for (child, step) in _iomap_children(iomap)
        _iomap_nodes!(nodes, seen, child, path * step, depth + 1, maxdepth)
    end
end

"""
    test_iomap_walk(label, document, projection) -> Vector{String}

Check the walk itself on one example, and return what is wrong with it.

The walk is the foundation of the property, so it is tested before anything is
asserted with it: every node must carry a projection, the root must be the first
node, and a nested projection must produce more than one node. A one-node tree
for a compound projection means the walk stopped at the root, which would make
the property pass everywhere by measuring nothing.
"""
function test_iomap_walk(label, document, projection)
    errors = String[]
    iomap = try
        print_document(projection, document)
    catch e
        push!(errors, "$label: print_document threw: $e")
        return errors
    end
    nodes = try
        iomap_nodes(iomap)
    catch e
        push!(errors, "$label: iomap_nodes threw: $e")
        return errors
    end
    isempty(nodes) && push!(errors, "$label: the walk found no node at all")
    for node in nodes
        node.projection === nothing &&
            push!(errors, "$label: the node at $(node.path) carries no projection")
    end
    errors
end

# ── Phase 2: the observation primitives ──────────────────────────────────────

"""
    ReactiveSurface

The cells a node is allowed to answer with, and their validity at the moment the
surface was taken.

`own` holds the node's **own** field cells — its `output` cell, its child-IoMap
cells, and whatever else the projection declared. `reachable` holds the cells
inside the output document as it stands now. Both are needed, and §2.1 of the
plan says why: a projection whose `output` is a computed cell answers by
invalidating `own`, and every cell of the old output tree stays untouched. A
harness that watched only the output tree would call that projection frozen.
"""
struct ReactiveSurface
    node::IoMapNode
    own::Vector{LocalityCell}
    reachable::Vector{LocalityCell}
    valid_before::Set{UInt64}
    errors::Vector{String}
end

cell_count(s::ReactiveSurface) = length(s.own) + length(s.reachable)

# The node's own field cells. `@iomap` stores every field in a Cell, so
# `getfield` reaches the raw Cell where property access would read through it.
#
# `input` and `projection` are excluded. The parent writes those; they say
# nothing about whether THIS projection followed its input.
function _own_cells(iomap::IoMap)
    cells = LocalityCell[]
    for fname in fieldnames(typeof(iomap))
        fname in (:input, :projection) && continue
        raw = try
            getfield(iomap, fname)
        catch
            continue
        end
        raw isa Cell && push!(cells, LocalityCell(raw, typeof(iomap), fname))
    end
    cells
end

"""
    reactive_surface(node::IoMapNode) -> ReactiveSurface

Force the node's output and take its whole reactive surface, recording which
cells are valid now.

Forcing first is what makes the measurement mean anything: an unforced cell is
already invalid, so it could not go invalid again and every projection would
look frozen.
"""
function reactive_surface(node::IoMapNode)
    errors = String[]
    own = _own_cells(node.iomap)
    reachable = LocalityCell[]
    _collect_locality!(node.output, nothing, :_, Set{UInt64}(), reachable,
                       Set{UInt64}(), errors, 0)
    valid = Set{UInt64}()
    for lc in Iterators.flatten((own, reachable))
        try
            lc.cell[]                       # force, so validity means something
            is_cell_up_to_date(lc.cell) && push!(valid, objectid(lc.cell))
        catch e
            push!(errors, "forcing $(lc.owner).$(lc.field) threw: $e")
        end
    end
    ReactiveSurface(node, own, reachable, valid, errors)
end

"""
    invalidated(surface::ReactiveSurface) -> Vector{LocalityCell}

The cells of the surface that were valid when it was taken and are not valid
now. Read validity only — recomputing first would repair exactly what is being
measured.
"""
function invalidated(surface::ReactiveSurface)
    out = LocalityCell[]
    for lc in Iterators.flatten((surface.own, surface.reachable))
        objectid(lc.cell) in surface.valid_before || continue
        is_cell_up_to_date(lc.cell) || push!(out, lc)
    end
    out
end

"""
    followed(surface::ReactiveSurface) -> Bool

`true` when at least one cell of the surface went invalid: the node followed its
input. This is the under-invalidation property of §1, stated per node.
"""
followed(surface::ReactiveSurface) = !isempty(invalidated(surface))

# ── Phase 2 acceptance ───────────────────────────────────────────────────────

# The orphaning case of §2.1, as a fixture rather than an example: an IoMap whose
# `output` is a computed cell over a source outside it.
#
# When the source moves, the output cell invalidates and yields a NEW value. No
# cell of the old output is touched — there is no old output tree here at all —
# so a harness that watched only the cells reachable from the output would see
# nothing move and would report this correct projection as frozen. The node's own
# `output` field cell is the only witness, which is why `reactive_surface`
# collects it.
function _orphaning_fixture()
    source = ReactiveCell(1)
    iomap = SimpleIoMap(nothing, source, nothing)
    set_cell_function!(getfield(iomap, :output), () -> source[] * 2)
    node = IoMapNode(iomap, nothing, source, iomap.output, "fixture", 0)
    (source, node)
end

"""
    test_reactive_surface() -> Vector{String}

Check the observation primitives before anything is asserted with them, and
return what is wrong. Four properties, each of which would silently disable the
harness if it broke.
"""
function test_reactive_surface()
    errors = String[]

    # 1. No edit, no invalidation. If this fails, every projection looks
    #    reactive and the harness proves nothing.
    example = examples[findfirst(e -> e.name == "json", examples)]
    root = print_document(example.projection, example.document)
    nodes = iomap_nodes(root)
    surface = reactive_surface(nodes[1])
    moved = invalidated(surface)
    isempty(moved) ||
        push!(errors, "a surface with no edit reports $(length(moved)) invalidated cells")
    cell_count(surface) > 0 ||
        push!(errors, "the root surface of json is empty")

    # 2. One write to the INPUT, at least one invalidation in the output.
    #    Writing an output cell would prove nothing: a write makes the written
    #    cell valid again and invalidates only its dependents, and a terminal
    #    output cell has none. The property is that the input moves the output,
    #    so the write goes where the property says it goes.
    input_cells = LocalityCell[]
    _collect_locality!(example.document, nothing, :_, Set{UInt64}(), input_cells,
                       Set{UInt64}(), String[], 0)
    writable = nothing
    for lc in input_cells
        lc.cell isa ReactiveCell || continue
        lc.cell[] isa AbstractString || continue
        writable = lc.cell
        break
    end
    if writable === nothing
        push!(errors, "found no writable string cell in the json input to test with")
    else
        before = writable[]
        surface2 = reactive_surface(nodes[1])
        writable[] = before * "'"
        isempty(invalidated(surface2)) &&
            push!(errors, "writing a leaf of the input invalidated nothing in the output")
        writable[] = before
    end

    # 3. A node measures its OWN output, not the whole example.
    #
    #    The plan asked for a nested surface strictly inside the root's. That is
    #    false here, and measuring says so plainly: on json every nested node
    #    shares ZERO cells with the root. The root of an example is a chaining
    #    projection, its steps are SIBLINGS in different domains — Json, Syntax,
    #    Text, Graphics — and step k's output is step k+1's input, not a part of
    #    the chaining IoMap's output. An intermediate step therefore has a
    #    surface disjoint from the final canvas, not one inside it.
    #
    #    So the property to hold is the one that was actually wanted: a nested
    #    surface must DIFFER from the root's. If every node reported the same
    #    cells, each node would be measuring the whole example and a failure
    #    could never be localised.
    root_ids = Set(objectid(lc.cell) for lc in reactive_surface(nodes[1]).reachable)
    distinct = 0
    for node in nodes[2:min(end, 12)]
        ids = Set(objectid(lc.cell) for lc in reactive_surface(node).reachable)
        (!isempty(ids) && ids != root_ids) && (distinct += 1)
    end
    distinct > 0 ||
        push!(errors, "every nested node reported the root's own surface")

    # 4. The orphaning case. This is the one that matters: a harness that fails
    #    it reports correct projections as frozen forever.
    source, node = _orphaning_fixture()
    fixture = reactive_surface(node)
    isempty(fixture.reachable) ||
        push!(errors, "the orphaning fixture was expected to have no reachable output cells")
    source[] = 2
    isempty(invalidated(fixture)) &&
        push!(errors, "a re-derived output was not seen: the node's own output cell was missed")

    errors
end

# ── Phase 3: the property ────────────────────────────────────────────────────

# §2.4's type-directed mutator. `nothing` means "no next value", and the caller
# counts the skip: a harness that silently skips most of a tree looks green while
# it tests nothing.
#
# The new value must differ from the old one under the cell's own equality, or
# the write is a no-op and the graph is right not to move.
_next_value(x::Bool)           = !x
_next_value(x::Integer)        = x + oneunit(x)
_next_value(x::AbstractFloat)  = x + one(x)
_next_value(x::AbstractString) = x * "'"
_next_value(x::Symbol)         = Symbol(string(x), "_")
_next_value(x::Char)           = x + 1
_next_value(::Any)             = nothing

"""
    input_leaf_targets(node::IoMapNode) -> Vector{Tuple{Any,Any,Cell}}

Every writable leaf of this node's input, paired with a `Reference` that
addresses it.

The reference is what makes the oracle possible: `map_reference_forward` decides
whether a location is shown in the output at all, and it needs a path, not a
cell. `search_references(...; raw=true)` supplies the paths, already annotated
with the type checkpoints the reference layer expects — building them by hand
here would get those wrong.

Only a leaf held in a named field is returned. A field is what gives a cell to
write to: strip the type checkpoints, drop the last step to address the parent,
evaluate that, and `getfield` the raw cell out of it.

Two references come back per leaf, and the difference matters. The **leaf** path
ends at the scalar (`…JsonString.value`) and names the field for a message. The
**parent** path addresses the enclosing document, and that is the one the oracle
is asked, because a projection maps document-scoped locations — a selection lands
on a `JsonString`, never on its `value` field. Asking with the leaf path made
`map_reference_forward` answer `nothing` for almost everything, which read as
"this projection shows nothing" when it shows all of it. The parent path is
re-annotated with type checkpoints, because an under-typed path is what several
mappers reject outright.
"""
function input_leaf_targets(node::IoMapNode)
    references = try
        search_references(node.input, v -> _next_value(v) !== nothing; raw=true)
    catch
        return Tuple{Any,Any,Cell}[]
    end
    targets = Tuple{Any,Any,Cell}[]
    for reference in references
        steps = try
            get_reference_steps(strip_reference_types(reference))
        catch
            continue
        end
        isempty(steps) && continue
        last_step = steps[end]
        last_step isa FieldReferenceStep || continue
        parent_reference = foldl(extend_reference, steps[1:end-1];
                                 init=EmptyReference())
        parent = try
            evaluate_reference(node.input, parent_reference)
        catch
            continue
        end
        question = try
            annotate_reference_types(node.input, parent_reference)
        catch
            parent_reference
        end
        cell = try
            getfield(parent, Symbol(last_step.name))
        catch
            continue
        end
        cell isa Cell && push!(targets, (question, reference, cell))
    end
    targets
end

"""
    is_obliged(node::IoMapNode, reference) -> Union{Bool,Nothing}

Does this node owe the output an answer when `reference` moves?

`true` when `map_reference_forward` maps the location into the output, `false`
when it answers `nothing` — a projection that filters, searches or focuses
deliberately drops part of its input and owes nothing for what it dropped.
`nothing` here means the question could not be asked: the mapper threw, or the
node has no projection to ask. An unanswerable question is never a finding.
"""
function is_obliged(node::IoMapNode, reference)
    node.projection === nothing && return nothing
    try
        return map_reference_forward(node.projection, node.iomap, reference) !== nothing
    catch
        return nothing
    end
end

"""
    input_leaves(node::IoMapNode) -> Vector{LocalityCell}

The cells of this node's input that hold a leaf value the mutator can move.

A `MutableCell` is included on purpose. It always answers "up to date", so it can
never register a change downstream — which is precisely the third bug of §1.1,
where a stage built with a mutable constructor left a button label frozen. Skip
it here and the harness would be blind to that whole shape.
"""
function input_leaves(node::IoMapNode)
    cells = LocalityCell[]
    _collect_locality!(node.input, nothing, :_, Set{UInt64}(), cells,
                       Set{UInt64}(), String[], 0)
    filter(cells) do lc
        value = try lc.cell[] catch; nothing end
        _next_value(value) !== nothing
    end
end

"""
    NodeVerdict

What one node did when a leaf of its input moved. `frozen` is the finding: the
leaf moved, the node owed an answer, and nothing in its surface went invalid.
"""
struct NodeVerdict
    node::IoMapNode
    tested::Int          # leaves the node was obliged to answer for, and did
    followed::Int
    frozen::Int          # obliged, written, and nothing moved — the finding
    frozen_fields::Vector{Symbol}
    not_shown::Int       # the oracle said the location is not in the output
    unanswerable::Int    # the oracle could not be asked
    skipped::Int         # over the leaf limit
end

is_frozen(v::NodeVerdict) = v.frozen > 0

"""
    check_reactivity(node::IoMapNode; leaf_limit=4) -> NodeVerdict

Write to leaves of this node's input, one at a time, and record whether the
node's own reactive surface followed. Each write is undone before the next.

The surface is re-taken for every leaf, because the previous write left cells
invalid and an invalid cell cannot go invalid again.

**A node is compared against its own output, never against the root's.** Under a
chaining projection the steps are siblings in different domains, so an
intermediate step shares no cell with the final canvas — measuring against the
root would report every step frozen.

`leaf_limit` bounds the work per node. What it drops is counted, not hidden.
"""
function check_reactivity(node::IoMapNode; leaf_limit::Int=4, oracle::Bool=true)
    targets = input_leaf_targets(node)
    skipped = max(0, length(targets) - leaf_limit)
    tested = 0; followed_count = 0; frozen = 0; not_shown = 0; unanswerable = 0
    frozen_fields = Symbol[]
    for (question, reference, cell) in Iterators.take(targets, leaf_limit)
        obliged = oracle ? is_obliged(node, question) : true
        if obliged === nothing
            unanswerable += 1
            continue
        elseif obliged === false
            not_shown += 1
            continue
        end
        before = try cell[] catch; continue end
        after = _next_value(before)
        after === nothing && continue
        surface = reactive_surface(node)
        cell_count(surface) == 0 && continue
        tested += 1
        field = _reference_field(reference)
        try
            cell[] = after
            if followed(surface)
                followed_count += 1
            else
                frozen += 1
                field in frozen_fields || push!(frozen_fields, field)
            end
        finally
            try cell[] = before catch end   # restore: the examples are shared
        end
    end
    NodeVerdict(node, tested, followed_count, frozen, frozen_fields,
                not_shown, unanswerable, skipped)
end

# The field name a leaf reference ends in, for the failure message.
function _reference_field(reference)
    steps = try
        get_reference_steps(strip_reference_types(reference))
    catch
        return :_
    end
    (!isempty(steps) && steps[end] isa FieldReferenceStep) ?
        Symbol(steps[end].name) : :_
end

"""
    check_reactivity(example; leaf_limit=4, node_limit=40) -> Vector{NodeVerdict}

Run the property over every node of one example's IoMap tree.

Each leaf is put to the oracle first, so the three outcomes stay apart: a
location the projection shows and must answer for, a location it deliberately
drops and owes nothing for, and a question that could not be asked at all. Only
the first can produce a frozen verdict.
"""
function check_reactivity(example; leaf_limit::Int=4, node_limit::Int=40)
    root = print_document(example.projection, example.document)
    nodes = iomap_nodes(root)
    [check_reactivity(node; leaf_limit=leaf_limit)
     for node in Iterators.take(nodes, node_limit)]
end

# ── Phase 3 acceptance ───────────────────────────────────────────────────────

# The first bug shape of §1.1, as a fixture: a value captured where a thunk was
# needed. The output is built ONCE from the input and stored in a constant cell,
# so a later write to the input reaches nothing. This is what
# `WidgetScrollPane(content)` did when it wrapped its argument in `Cell(content)`.
#
# The harness must call this frozen. If it does not, it can not catch the bug it
# exists for.
function _frozen_fixture()
    input = PrimitiveString("a")
    captured = input.value                   # the mistake, in one line
    iomap = SimpleIoMap(nothing, input, captured)
    (input, IoMapNode(iomap, nothing, input, captured, "frozen-fixture", 0))
end

# The same shape, done right: the output re-derives from the input.
function _reactive_fixture()
    input = PrimitiveString("a")
    iomap = SimpleIoMap(nothing, input, nothing)
    set_cell_function!(getfield(iomap, :output), () -> input.value * "!")
    (input, IoMapNode(iomap, nothing, input, iomap.output, "reactive-fixture", 0))
end

"""
    test_reactivity_property() -> Vector{String}

The acceptance test of the property: it must call a frozen projection frozen and
a reactive one reactive. A harness that cannot separate those two is worthless
however green it looks.
"""
function test_reactivity_property()
    errors = String[]

    _, frozen_node = _frozen_fixture()
    # The fixtures bypass the oracle. They ARE the ground truth: the location is
    # shown by construction, and these two nodes carry no projection for a mapper
    # to be asked about. The oracle is a filter for real projections; what is under
    # test here is the mechanism it filters for.
    verdict = check_reactivity(frozen_node; oracle=false)
    verdict.tested == 0 &&
        push!(errors, "the frozen fixture offered no leaf to write")
    is_frozen(verdict) ||
        push!(errors, "a captured value was not reported frozen: $(verdict.tested) tested, " *
                      "$(verdict.followed) followed")

    _, live_node = _reactive_fixture()
    live = check_reactivity(live_node; oracle=false)
    live.tested == 0 &&
        push!(errors, "the reactive fixture offered no leaf to write")
    is_frozen(live) &&
        push!(errors, "a re-deriving output was wrongly reported frozen")

    errors
end
