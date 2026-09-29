"""
    IntentModule

The backward-flowing unit of the reader pipeline — the reader-side protocol data
types `Intent` and `ClaimedGesture`, the `CollectIntents` payload, and the
`CollectedIntentsOperation` that carries a collection home. They are concrete data
vehicles, not interfaces to implement; readers import them from here directly.

They sit in layer 14, above the operation layer, because an `Intent`'s second
half *is* an operation.
"""
module IntentModule

using ..OperationModule
using ..ReferenceModule
import ..OperationModule: make_inverse_operation, reroot_operation

export Intent, ClaimedGesture, CollectIntents, CollectedIntentsOperation,
       merge_collected_intents, follow_intent_route

include("Intent.jl")

end # module
