# Capability test for the native mutable @document variant + cross-layout sync.
# Run: julia --project=. this_file.jl   (from the worktree root)
using Test
using ProjecturedKernel.CellModule
using ProjecturedKernel.DocumentModule
using ProjecturedKernel.DocumentModule: is_same_document_type
using ProjecturedKernel.ReferenceModule: Reference

@document struct Node
    label::String
    count::Int
    child::Union{Node, Nothing}
end

passed = Ref(0); failed = Ref(0)
chk(name, cond) = (cond ? (passed[]+=1) : (failed[]+=1; println("  FAIL: ", name)); nothing)

println("== A. family + native variant are emitted ==")
chk("AbstractNode exists & abstract", (@isdefined AbstractNode) && isabstracttype(AbstractNode))
chk("NodeMut exists & mutable",       (@isdefined NodeMut) && ismutabletype(NodeMut))
chk("stem <: family",   Node <: AbstractNode)
chk("native <: family", NodeMut <: AbstractNode)
chk("document_family(stem)   == family", document_family(Node)    === AbstractNode)
chk("document_family(native) == family", document_family(NodeMut) === AbstractNode)

println("== B. native mutable is a plain mutable struct ==")
m = NodeMut("root", 1, nothing)          # Rule Y: selection defaults
chk("native constructs",          m isa NodeMut)
chk("native field is raw value",  getfield(m, :label) == "root")   # NOT a cell
chk("native getproperty == getfield", m.label == "root" && m.count == 1)
m.count = 5                                                          # plain setfield
chk("native setproperty! mutates in place", m.count == 5)
chk("native selection defaulted", m.selection === nothing)

println("== C. native -> reactive sync copies values ==")
shadow = Node("root", 1, nothing)         # bare ctor => reactive stem
chk("shadow is reactive stem", shadow isa Node)
chk("same document type across layouts", is_same_document_type(shadow, m))
sync_document!(shadow, m)
chk("scalar field synced (String)", shadow.label == "root")
chk("scalar field synced (Int)",    shadow.count == 5)

println("== D. sync drives reactivity with MINIMAL invalidation ==")
watch_label = Cell(() -> shadow.label)
watch_count = Cell(() -> shadow.count)
watch_label[]; watch_count[]                       # force -> up to date
chk("watchers up to date after force", is_cell_up_to_date(watch_label) && is_cell_up_to_date(watch_count))
# change only count in the source, resync
m.count = 42
sync_document!(shadow, m)
chk("changed field invalidates its watcher",   !is_cell_up_to_date(watch_count))
chk("unchanged field watcher stays valid",      is_cell_up_to_date(watch_label))   # minimal invalidation
chk("watcher recomputes new value", watch_count[] == 42)

println("== E. nested native? (characterize the layout limitation) ==")
# Can a native parent hold a native child? child field value-type is Union{Node,Nothing};
# NodeMut <: AbstractNode but NOT <: Node(stem). Expect this to FAIL to construct.
nested_native_ok = try
    NodeMut("p", 0, NodeMut("c", 0, nothing)); true
catch e
    println("  (native cannot nest native: ", typeof(e), ")"); false
end
chk("[info] native parent holds native child", nested_native_ok)
# But a native parent CAN hold a reactive/stem child (child field accepts the stem):
mixed_ok = try
    NodeMut("p", 0, Node("c", 0, nothing)); true
catch e
    println("  (native+stem child failed: ", typeof(e), ")"); false
end
chk("[info] native parent holds stem child", mixed_ok)

println("\n== F. nested sync: reactive shadow tree <- source with a nested child ==")
# Source: native parent with a stem child (the only nesting the current layout allows).
src = NodeMut("p", 1, Node("c", 2, nothing))
dst = Node("p", 0, Node("c", 0, nothing))       # reactive shadow with matching shape
sync_document!(dst, src)
chk("nested child synced in place", dst.child !== nothing && dst.child.label == "c" && dst.child.count == 2)
chk("nested shadow child stays reactive", dst.child isa Node)

println("\nPASS=", passed[], " FAIL=", failed[])
exit(failed[] == 0 ? 0 : 1)
