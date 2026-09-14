"""
    GestureLogModule

A record of what the user did — a document that holds the last N gestures and
the operation that the projection pipeline made from each one.

The buffer has a fixed size. `record_gesture!` appends one entry and deletes the
oldest entry when the buffer is full. The entries live in a `CellVector`, so an
append invalidates every reader of the collection and the overlay redraws.

An entry holds **strings**, not the live gesture and the live operation. An
operation holds a reference into the document, and the document changes as soon
as the operation runs, so a live operation renders differently one second later.
A string is a record of the moment.

[`GestureLogToSyntax`](GestureLogToSyntax.jl) projects the log onto the
Syntax → Text → Graphics path. [`GestureLogRecordingProjection`](GestureLogRecording.jl)
fills it and [`GestureLogOverlayProjection`](GestureLogOverlay.jl) shows it.
"""
module GestureLogModule

using ..CellModule
using ..CollectionModule
using ..DocumentModule
using ..EventModule
using ..EventPatternModule
using ..GraphicsModule
using ..IntentModule
using ..IoMapModule
using ..OperationModule
using ..ProjectionAlgebraModule
using ..ProjectionModule
using ..ReferenceModule
using ..StyleModule
using ..SyntaxModule
using ..TextModule

# Imported to extend: this module adds a method to each of these.
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward

export GestureLogEntry, GestureLog, record_gesture!, clear_gesture_log!,
       describe_gesture, describe_operation, default_gesture_log_filter
export GestureLogToSyntax
export GestureLogRecordingProjection, GestureLogRecordingIoMap
export GestureLogOverlayProjection, GestureLogOverlayIoMap,
       make_gesture_log_content_projection, GESTURE_LOG_BACKGROUND


include("GestureLogDocument.jl")
include("GestureLogToSyntax.jl")
include("GestureLogRecording.jl")
include("GestureLogOverlay.jl")

end # module
