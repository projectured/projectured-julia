"""
    PlaybackModule

Scripted live playback: drive the editor's read-eval-print loop while firing a
predefined timeline on a wall-clock schedule, so a scripted session unfolds in a
real window. Builds on the editor-loop primitives
(`read!`/`evaluate!`/`print!`).
"""
module PlaybackModule

using ..EditorModule
using ..ProjectionModule
using ..IntentModule
using ..EventModule
using ..OperationModule
using ..ReferenceModule
using ..BackendModule
using ..DeviceModule

export play_live!

include("Playback.jl")

end # module
