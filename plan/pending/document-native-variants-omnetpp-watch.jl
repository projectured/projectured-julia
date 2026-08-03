# End-to-end prototype: projectured "watches" a running omnetpp-style simulation.
#
# Shape mirrors the REAL SequentialSimulator's observable state (flat scalars +
# struct-of-arrays primitive vectors — NO nested documents, exactly as the real sim
# stores per-module state). Demonstrates the full pipeline:
#
#   sim mutates the NATIVE variant (SimSnapshotMut) at plain-mutable-struct speed
#     -> at a pause point, sync_document!(reactive shadow, native) copies changes
#        into the reactive shadow, writing a cell only when its value changed
#          -> "view" cells (standing in for projectured's incremental projections)
#             recompute ONLY where their inputs changed  == partial invalidation.
#
# Run: julia --project=<worktree> omnetpp_watch_prototype.jl
using ProjecturedKernel.CellModule
using ProjecturedKernel.DocumentModule
using ProjecturedKernel.ReferenceModule: Reference

# The watchable sim state — one @document schema, used in two layouts.
@document struct SimSnapshot
    time::Int64
    global_event_count::Int
    stopped::Bool
    event_counts::Vector{Int}      # SoA: per-module counters (as the real sim stores them)
    module_hashes::Vector{UInt128} # SoA: per-module rolling hash
end

const NMOD = 8

# --- The simulator: mutates the native variant directly (full speed) ---
make_sim() = SimSnapshotMut(0, 0, false, zeros(Int, NMOD), zeros(UInt128, NMOD))

# One "event": advance time, pick a module, bump its counter + hash, count globally.
function step!(sim, i)
    sim.time += 1
    m = (i % NMOD) + 1
    @inbounds sim.event_counts[m] += 1
    @inbounds sim.module_hashes[m] = hash((sim.module_hashes[m], sim.time)) % UInt128
    sim.global_event_count += 1
    return sim
end

# --- The UI: a reactive shadow + view cells that recompute incrementally ---
shadow = SimSnapshot(0, 0, false, zeros(Int, NMOD), zeros(UInt128, NMOD))  # reactive stem

# Instrument recomputation: each view cell bumps a counter when it actually runs.
recompute = Dict(:clock=>Ref(0), :status=>Ref(0), :counts=>Ref(0), :total=>Ref(0))
view_clock  = ComputedCell(() -> (recompute[:clock][]  += 1; "t=$(shadow.time)"))
view_status = ComputedCell(() -> (recompute[:status][] += 1; shadow.stopped ? "STOPPED" : "running"))
view_counts = ComputedCell(() -> (recompute[:counts][] += 1; copy(shadow.event_counts)))
view_total  = ComputedCell(() -> (recompute[:total][]  += 1; shadow.global_event_count))
force_all() = (view_clock[]; view_status[]; view_counts[]; view_total[])

pass = Ref(0); fail = Ref(0)
chk(name, c) = (c ? pass[]+=1 : (fail[]+=1; println("  FAIL: $name")); nothing)

println("== 1. sim runs natively, then a sync refreshes the reactive shadow ==")
sim = make_sim()
for i in 1:1000; step!(sim, i); end          # native-speed burst, shadow untouched
chk("shadow untouched during burst", shadow.time == 0 && shadow.global_event_count == 0)
sync_document!(shadow, sim)                    # pause point: refresh the UI
chk("scalar synced (time)",  shadow.time == 1000)
chk("scalar synced (total)", shadow.global_event_count == 1000)
chk("SoA vector synced",     sum(shadow.event_counts) == 1000)

println("== 2. first render forces all view cells ==")
force_all()
base = Dict(k => v[] for (k,v) in recompute)
chk("all views computed once", all(v[] >= 1 for v in values(recompute)))

println("== 3. advance the sim, resync, re-render: only CHANGED scalar views recompute ==")
# Run more events but touch ONLY the counters/time/total — never `stopped`.
for i in 1001:2000; step!(sim, i); end
sync_document!(shadow, sim)                    # stopped unchanged -> its cell not rewritten
force_all()
chk("clock view recomputed (time changed)",   recompute[:clock][]  > base[:clock])
chk("total view recomputed (total changed)",  recompute[:total][]  > base[:total])
chk("STATUS view did NOT recompute (stopped unchanged) == partial invalidation",
    recompute[:status][] == base[:status])

println("== 3b. FINDING: a plain mutable-collection leaf field ALIASES under sync ==")
# sync stores the source's vector object directly, so shadow.event_counts becomes the
# SAME object as sim.event_counts. Consequences: (a) sim mutations are visible in the
# shadow with no sync, but (b) they never invalidate the cell (cur === sv), so the
# reactive counts view does NOT refresh. This is the mutable-leaf gap, not per-field
# reactivity failing — scalars above work perfectly.
chk("[finding] shadow aliases the sim's vector after sync", shadow.event_counts === sim.event_counts)
chk("[finding] aliased => counts view did NOT recompute (needs copy-on-sync)",
    recompute[:counts][] == base[:counts])

println("== 4. a sync that changes NOTHING invalidates NOTHING ==")
b2 = Dict(k => v[] for (k,v) in recompute)
sync_document!(shadow, sim)                    # sim not advanced since last sync
force_all()
chk("no view recomputed on a no-op sync",
    all(recompute[k][] == b2[k] for k in keys(recompute)))

println("== 5. changing one scalar invalidates only its view ==")
b3 = Dict(k => v[] for (k,v) in recompute)
sim.stopped = true
sync_document!(shadow, sim)
force_all()
chk("status view recomputed (stopped flipped)", recompute[:status][] > b3[:status])
chk("clock view did NOT recompute (time unchanged since last sync)",
    recompute[:clock][] == b3[:clock])

println("\n--- granularity note ---")
println("event_counts is ONE cell holding a Vector -> any per-module bump rewrites the")
println("whole vector cell (coarse). Per-MODULE partial invalidation would need the")
println("modules as array-of-documents (reactive nesting in the shadow; native nesting")
println("on the sim side == the deferred layout unit).")

println("\nPASS=$(pass[]) FAIL=$(fail[])")
exit(fail[] == 0 ? 0 : 1)
