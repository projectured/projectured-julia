"""
    ScreenModule

The screen domain: the projection-output side of the multi-window pipeline.

A `ScreenDocument` holds a list of `WindowDocument`s. Each `WindowDocument`
carries window metadata (id, title, x/y, width/height, bg, style) and a
`content::Document` of any type. The backend reconciles live native windows
against a `ScreenDocument` — one native window per `WindowDocument.id`.

`ScreenDocument` and `WindowDocument` are ordinary projectional documents:
the existing `CopyingProjection` handles them via its `CellVector` and
struct paths, so no new projection type is needed to project them — only
the example's projection at the `content` leaf.

The window *events* (`WindowClose`, `WindowResize`, `WindowDefocus`) are input
vocabulary and live with the other events in the kernel; a reader here
translates one into a document mutation — typically removing the matching
`WindowDocument` from `windows`, or writing its new size.
"""
module ScreenModule

using ..BackendModule
using ..CellModule
using ..CollectionModule
using ..DocumentModule
using ..EditorModule
using ..EventModule
using ..FaultModule
using ..FeedModule
using ..GestureModule
using ..GestureTrackingModule
using ..GraphicsModule
using ..IntentModule
using ..IoMapModule
using ..MouseTargetTrackingModule
using ..OperationModule
using ..PrimitiveModule
using ..ProjectionModule
using ..ReferenceModule
using ..SelectionModule

# Imported to extend: this module adds a method to each of these.
import ..DocumentModule: get_document_title
import ..EditorModule: wrap_editor!, get_wrapper_layers, is_wrapper_default
import ..OperationModule: evaluate_operation
import ..GraphicsModule: map_operation_position
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward

export OpenWindowOperation, OpenPopupOperation, CloseWindowOperation,
       ResizeWindowOperation
export WindowManagingProjection, WindowManagingIoMap
export ScreenToScreen, ScreenToScreenIoMap, ScreenWindowIoMap
export make_window_scene, make_window_scene_projection, make_tracking_screen,
       show_document!
export ScreenDocument, WindowDocument
export find_part_place


include("ScreenDocument.jl")
include("WindowManaging.jl")
include("ScreenToScreen.jl")
include("WindowScene.jl")
include("PartPlace.jl")
include("DocumentShow.jl")


end # module
