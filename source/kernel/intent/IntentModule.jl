"""
    IntentModule

The backward-flowing unit of the reader pipeline — the reader-side protocol data
types `Intent` and `ClaimedGesture`, the `CollectIntents` payload, and the
`CollectedIntentsOperation` that carries a collection home. They are concrete data
vehicles, not interfaces to implement; readers import them from here directly.

They sit in the operation layer because an `Intent`'s second half *is* an
operation, and because the binding layer above has to build one.
"""
module IntentModule

using ..OperationModule
import ..OperationModule: reroot_operation

export Intent, ClaimedGesture, CollectIntents, CollectedIntentsOperation,
       with_intent_labels, merge_collected_intents

include("Intent.jl")

end # module
