# FES-speed spike: does making the simulator an @document cost anything on the
# hot path? Compares the native @document variant (SimStateMut) against a
# hand-written plain `mutable struct` (PlainSim) with the SAME fields, running the
# simulator's inner-loop shape: advance time, bump a per-module counter, and
# push!/pop! the future-event set. Measures allocation and wall time for both.
#
# Run: julia --project=<worktree> fes_speed_spike.jl   (after the suites finish)
using ProjecturedKernel.CellModule
using ProjecturedKernel.DocumentModule
using ProjecturedKernel.ReferenceModule: Reference

# A minimal immutable event, like SequentialEvent (isbits-ish; Function excluded so
# the two structs are byte-identical and the loop measures field access, not the heap).
struct Ev
    timestamp::Int64
    uid::UInt128
    module_id::Int
end

# ---- The @document form: sim mutates the NATIVE variant SimStateMut ----
@document struct SimState
    time::Int64
    root_count::Int
    global_event_count::Int
    stopped::Bool
    event_counts::Vector{Int}
    queue::Vector{Ev}          # stand-in for the FES heap; push!/pop! is the hot op
end

# ---- The hand-written baseline: identical fields, plain mutable struct ----
mutable struct PlainSim
    time::Int64
    root_count::Int
    global_event_count::Int
    stopped::Bool
    event_counts::Vector{Int}
    queue::Vector{Ev}
    selection::Union{Nothing,Reference}   # match @document's injected field for parity
end

# The inner loop, written generically so the SAME code runs on both types — this is
# exactly what dispatch would do if `sim::AbstractSequentialSimulator`.
function hot_loop!(sim, n::Int)
    for i in 1:n
        sim.time += 1
        m = (i & 7) + 1
        ec = sim.event_counts
        @inbounds ec[m] += 1
        sim.global_event_count += 1
        push!(sim.queue, Ev(sim.time, UInt128(i), m))
        # keep the queue bounded: pop every other step (mimics schedule/execute balance)
        if isodd(i) && !isempty(sim.queue)
            pop!(sim.queue)
        end
    end
    sim.time
end

make_native() = SimStateMut(0, 0, 0, false, zeros(Int, 8), Ev[])
make_plain()  = PlainSim(0, 0, 0, false, zeros(Int, 8), Ev[], nothing)

# Sanity: native accessors are getfield/setfield (plain-struct semantics)
let s = make_native()
    @assert s isa SimStateMut
    @assert getfield(s, :time) == 0            # raw field, not a cell
    s.time = 7; @assert s.time == 7
    @assert SimStateMut <: AbstractSimState
end

println("== FES hot-loop: native @document (SimStateMut) vs plain mutable struct ==")
const N = 2_000_000

# Warm up (JIT both paths)
hot_loop!(make_native(), 1000)
hot_loop!(make_plain(), 1000)

# Allocation: the key isbits/heap-parity signal. Both should allocate the same
# (only the queue's Vector growth), proving @document adds no per-access boxing.
GC.gc()
a_native = @allocated hot_loop!(make_native(), N)
GC.gc()
a_plain  = @allocated hot_loop!(make_plain(), N)

# Time: best of several runs each (reduce noise).
best(f) = minimum(( (GC.gc(); @elapsed f()) for _ in 1:5 ))
t_native = best(() -> hot_loop!(make_native(), N))
t_plain  = best(() -> hot_loop!(make_plain(),  N))

println("  allocated  native=$(a_native)  plain=$(a_plain)  ratio=$(round(a_native/max(a_plain,1); digits=3))")
println("  time (s)   native=$(round(t_native; digits=4))  plain=$(round(t_plain; digits=4))  ratio=$(round(t_native/t_plain; digits=3))")

ok_alloc = a_native <= a_plain * 1.02 + 64        # essentially identical allocation
ok_time  = t_native <= t_plain * 1.15             # within noise (15%)
println(ok_alloc ? "  ALLOC: native == plain (no per-access boxing)" : "  ALLOC REGRESSION: native allocates more!")
println(ok_time  ? "  TIME:  native ~ plain (within noise)"          : "  TIME REGRESSION: native slower!")
exit((ok_alloc && ok_time) ? 0 : 1)
