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
using ..DomainModule
using ..EventModule
using ..EventModule
using ..GestureModule
using ..GraphicsModule
using ..IntentModule
using ..IoMapModule
using ..NaturalModule
using ..OperationModule
using ..ProjectionAlgebraModule
using ..ProjectionModule
using ..ReferenceModule
using ..SerializationModule
using ..StyleModule
using ..SyntaxModule
using ..TextModule
using ..EditorModule

# Imported to extend: this module adds a method to each of these.
import ..DocumentModule: get_document_title
import ..DomainModule: get_insertion_aliases, make_insertion_document
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward
import ..SerializationModule: pred_arguments
import ..EditorModule: wrap_editor!, get_wrapper_layers
import ..StyleModule: get_theme_presets

export GestureLogEntry, GestureLog, get_session_gesture_log,
       record_gesture!, clear_gesture_log!,
       describe_gesture, describe_operation, default_gesture_log_filter
export GestureLogTheme, ScaledGestureLogTheme
export GestureLogToSyntax, make_gesture_log_projection
export GestureLogRecordingProjection, GestureLogRecordingIoMap
export GestureLogOverlayProjection, GestureLogOverlayIoMap,
       make_gesture_log_content_projection, make_gesture_log_panel_theme


include("GestureLogDocument.jl")
include("GestureLogTheme.jl")
include("GestureLogToSyntax.jl")
include("GestureLogRecording.jl")
include("GestureLogOverlay.jl")

end # module
