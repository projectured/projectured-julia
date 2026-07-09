# M→R shadow sync — Phase 7 of plan/pending/cell-kind-documents.md, the simulation
# payoff. A toy discrete-event queue simulation owns a MutableCell-kind document and
# mutates it freely (no reactive overhead per event, no observable intermediate
# states). At each pause point `sync_document!` diff-copies it into a reactive shadow
# that a computed "view" cell observes — updated consistently, minimally.
#
# Run standalone (light path, kernel + domain):
#
#     julia --project=. package/example/demo/CellKindSimDemo.jl

using Projectured
using Test
using Printf

# ── The simulation state as documents (one @document declaration, three kinds) ──

@document struct SimJob
    id::Int
    remaining::Float64
end

@document struct SimState
    clock::Float64 = 0.0
    served::Int = 0
    queue::CellVector = CellVector()   # of SimJob
end

# ── The simulator: mutates MutableCell-kind state directly, no reactivity ──────

# Advance the simulation by one event: serve `dt` of work off the front job; when a
# job finishes, drop it and count it; occasionally enqueue a fresh job. Every write
# here is a plain MutableCell store — zero dependency bookkeeping, and the reactive
# view sees NONE of these intermediate states.
function step!(sim, dt::Float64, arrival::Union{Nothing,SimJob})
    sim.clock = sim.clock + dt
    q = sim.queue
    if !isempty(q)
        job = q[1]
        job.remaining = job.remaining - dt
        if job.remaining <= 0.0
            popfirst_job!(q)
            sim.served = sim.served + 1
        end
    end
    arrival === nothing || push!(q, arrival)
    sim
end

# The M-kind CellVector stores plain values; drop the front element.
popfirst_job!(q) = deleteat!(q, 1)

# ── Demo ──────────────────────────────────────────────────────────────────────

@testset "M→R shadow sync" begin
    # Build the initial reactive state, then fork a mutable simulation copy and a
    # reactive shadow. The simulator owns `sim`; the UI owns `shadow`.
    initial = SimState(0.0, 0, CellVector([SimJob(1, 3.0), SimJob(2, 2.0)]))
    sim    = rekind(MutableCell, initial)      # simulation-owned, mutable, non-reactive
    shadow = hydrate(initial)                  # UI-owned, reactive
    @test cell_kind(sim) === MutableCell
    @test cell_kind(shadow) === ReactiveCell

    # A reactive "view": total remaining work across the queue + a recompute counter.
    recomputes = Ref(0)
    total_work = Cell(() -> begin
        recomputes[] += 1
        sum(Float64[j.remaining for j in shadow.queue]; init = 0.0)
    end)
    @test total_work[] == 5.0
    @test recomputes[] == 1

    # Reading the mutable sim inside a reactive thunk registers NOTHING, so mutating
    # the sim does not (and must not) disturb the view — the whole point of M-kind.
    step!(sim, 1.0, nothing)                   # front job 1: 3.0 → 2.0
    @test is_up_to_date(total_work)               # view unaware of the simulation
    @test total_work[] == 5.0                  # still the pre-sync value

    # Pause point: sync. Only the cells that actually changed are written — job 1's
    # remaining (3.0→2.0) and the clock (0.0→1.0) — so exactly the view recomputes.
    w1 = with_performance_counters() do
        sync_document!(shadow, sim)
        get(get_performance_counters(), :writes, 0)
    end
    @test !is_up_to_date(total_work)              # the changed job invalidated the view
    @test total_work[] == 4.0                  # 2.0 + 2.0
    @test recomputes[] == 2
    # Write counts are only meaningful with the counters compiled in (run with
    # PROJECTURED_PERFORMANCE_COUNTERS=true); otherwise `w1` is 0.
    PERFORMANCE_COUNTERS_ENABLED && @test w1 == 2   # exactly the 2 changed cells (clock + remaining)

    # A step that finishes the front job (dequeue) + enqueues a new one.
    step!(sim, 2.0, SimJob(3, 4.0))            # job1 remaining 2.0→0 ⇒ served; push job3
    @test sim.served == 1 && length(sim.queue) == 2   # [job2(2.0), job3(4.0)]
    sync_document!(shadow, sim)
    @test total_work[] == 6.0                  # 2.0 + 4.0
    @test [j.id for j in shadow.queue] == [2, 3]
    @test shadow.served == 1

    # Idempotence: a sync with no changes writes nothing and recomputes nothing.
    recomputes_before = recomputes[]
    idle_writes = with_performance_counters() do
        sync_document!(shadow, sim)
        get(get_performance_counters(), :writes, 0)
    end
    @test idle_writes == 0
    total_work[]                               # force
    @test recomputes[] == recomputes_before    # stayed valid ⇒ no recompute

    # ── minimal-invalidation measurement: leaf-level updates ──
    # 200 jobs, of which only a handful change per step (in-place `remaining`
    # updates — a protocol-module-state-style workload). Each sync writes ONLY the
    # cells that changed, not the whole tree — the core "only updated if different"
    # property. (Structural front-dequeue is the separate case below.)
    big = SimState(0.0, 0, CellVector([SimJob(i, 100.0) for i in 1:200]))
    bsim = rekind(MutableCell, big)
    bshadow = hydrate(big)
    total_writes = 0
    for _ in 1:100
        bsim.clock = bsim.clock + 1.0
        for j in rand(1:200, 3)                # 3 random jobs tick down in place
            bsim.queue[j].remaining -= 1.0
        end
        total_writes += with_performance_counters() do
            sync_document!(bshadow, bsim)
            get(get_performance_counters(), :writes, 0)
        end
    end
    per_sync = total_writes / 100
    @printf("200-job queue, 100 steps, ≤3 in-place changes/step: %.1f shadow writes/sync\n",
            per_sync)
    @test per_sync <= 5.0                       # ~clock + ≤3 jobs, NOT ~200
    @test length(bshadow.queue) == 200

    # Structural note: a front dequeue shifts every element, so the *positional*
    # reconciler rewrites the whole tail (O(n) writes) — the known non-minimal case
    # (identity-keyed matching via a persisted IdDict is the refinement). Measured
    # here so the cost is explicit, not hidden.
    fq = rekind(MutableCell, SimState(0.0, 0, CellVector([SimJob(i, 1.0) for i in 1:50])))
    fsh = hydrate(SimState(0.0, 0, CellVector([SimJob(i, 1.0) for i in 1:50])))
    sync_document!(fsh, fq)
    deleteat!(fq.queue, 1)                       # dequeue the front
    front_writes = with_performance_counters() do
        sync_document!(fsh, fq)
        get(get_performance_counters(), :writes, 0)
    end
    @printf("front dequeue of a 50-job queue: %d writes (positional = O(n))\n",
            front_writes)
    @test length(fsh.queue) == 49
end
println("CELL KIND SIM DEMO OK")
