"""
    FaultModule

How a failure is recorded, and how it is reported when the place it belongs
can not take it.

A fault is an exception that a barrier caught instead of letting it end the
editor. This module holds the record of one, the per-editor store that collects
them, the policy that says whether the barriers catch and which report tiers are
open, the barrier that catches, and the cascade that reports. It holds no
document and no projection. This module says what a fault is, and code above it
says what a fault looks like.

The layer imports nothing, so it can sit below every other layer, and every
layer above can report a fault.

Its open seams keep it that way. Each is a generic that code above answers, and
each default here names nothing above. For example, the default of
`append_fault!` does nothing, so this layer names no log document. The default
of `play_fault_sound!` writes the BEL character, so this layer names no backend.

The module lives in seven fragments that share this namespace:

- [`FaultInterface.jl`](FaultInterface.jl) — the open seams and the passthrough
  predicate.
- [`FaultDefaults.jl`](FaultDefaults.jl) — the answer each seam supplies itself.
- [`FaultRecord.jl`](FaultRecord.jl) — one fault as a value.
- [`FaultStore.jl`](FaultStore.jl) — the per-editor collection, outside the
  reactive graph.
- [`FaultPolicy.jl`](FaultPolicy.jl) — whether the barriers catch, and which
  tiers are open.
- [`FaultCascade.jl`](FaultCascade.jl) — `report_fault!` and its five tiers.
- [`FaultBarrier.jl`](FaultBarrier.jl) — `run_fault_barrier!`, the barrier around one
  stage of work.
"""
module FaultModule

export append_fault!, play_fault_sound!, get_fault_store, make_safe_mode_projection,
       is_passthrough_exception
export FaultRecord, make_fault_record
export FaultStore, record_fault!, drain_faults!, get_fault_records,
       attach_fault_target!, attach_fault_wake!,
       get_consecutive_fault_count, reset_consecutive_fault_count!
export FaultPolicy, make_strict_fault_policy
export report_fault!, run_fault_barrier!

include("FaultInterface.jl")
include("FaultDefaults.jl")
include("FaultRecord.jl")
include("FaultStore.jl")
include("FaultPolicy.jl")
include("FaultCascade.jl")
include("FaultBarrier.jl")

end # module
