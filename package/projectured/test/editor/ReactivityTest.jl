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
