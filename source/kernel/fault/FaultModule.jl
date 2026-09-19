"""
    FaultModule

How a failure is recorded, and how it is reported when the place it belongs
can not take it.

A fault is an exception that a barrier caught instead of letting it end the
editor. This module holds the record of one, the per-editor store that collects
them, the policy that says which report tiers are open, the barrier that catches,
and the cascade that reports. It holds no document and no projection: what a
fault *looks like* belongs to `ProjecturedFault`, and what a fault *is* belongs
here.

The layer is the first of the kernel and it imports nothing. That is deliberate.
Every layer above can report a fault, the cell engine and the backend seam
included, and none of them could if this sat higher.

The two seams keep it that way. `append_fault!` hands a record to something that
shows it, and its default does nothing, so the kernel never names a log
document. `play_fault_sound!` makes the last audible tier, and its default writes
the BEL character, so the kernel never names a backend.

The module lives in seven fragments that share this namespace:

- [`FaultInterface.jl`](FaultInterface.jl) — the two open seams and the
  passthrough predicate.
- [`FaultDefaults.jl`](FaultDefaults.jl) — the answer each seam supplies itself.
- [`FaultRecord.jl`](FaultRecord.jl) — one fault as a value.
- [`FaultStore.jl`](FaultStore.jl) — the per-editor collection, outside the
  reactive graph.
- [`FaultPolicy.jl`](FaultPolicy.jl) — which tiers are open, and the limits.
- [`FaultCascade.jl`](FaultCascade.jl) — `report_fault!` and its five tiers.
- [`FaultBarrier.jl`](FaultBarrier.jl) — `run_fault_barrier`, the one catch.
"""
module FaultModule

export FaultRecord, FaultStore, FaultPolicy,
       make_fault_record, compute_fault_key, format_fault_message,
       format_fault_traceback,
       record_fault!, drain_faults!, attach_fault_target!, attach_fault_wake!,
       get_consecutive_fault_count, reset_consecutive_fault_count!,
       clear_fault_store!, get_fault_records,
       append_fault!, play_fault_sound!, is_passthrough_exception,
       get_fault_store, get_fault_policy, make_safe_mode_projection,
       get_fault_origin_name, get_fault_exception_name,
       report_fault!, run_fault_barrier,
       make_strict_fault_policy

include("FaultInterface.jl")   # the open seams (declaration-only)
include("FaultDefaults.jl")    # what each seam answers on its own
include("FaultRecord.jl")      # one fault as a value
include("FaultStore.jl")       # the per-editor collection
include("FaultPolicy.jl")      # which tiers are open
include("FaultCascade.jl")     # report_fault! and the tiers
include("FaultBarrier.jl")     # run_fault_barrier

end # module
