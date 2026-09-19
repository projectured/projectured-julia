"""
    ClipboardModule

The clipboard domain: a slice that holds one sub-document, a collection that
holds many, the two projections that show them, and access to the host
operating system's clipboard.

This file holds the OS access, because both projections mirror through it. It
also holds `WriteOsClipboardOperation` and the helpers the two readers share.
[ClipboardSliceToAny.jl](ClipboardSliceToAny.jl) and
[ClipboardCollectionToAny.jl](ClipboardCollectionToAny.jl) hold one projection
each.

The OS access sits behind a stubbable indirection. A projection uses it to
mirror a copy or a cut out to the OS clipboard, and to fall back to the OS
clipboard when nothing is on the ProjecturEd one.

The default backend shells out to the first available command-line tool
(`xclip` / `xsel` on X11, `wl-paste`/`wl-copy` on Wayland, `pbpaste`/`pbcopy` on
macOS). All reads/writes are wrapped so a missing tool or a failed invocation
degrades gracefully — `read_os_clipboard` returns `nothing` and `write_os_clipboard!`
returns `false` rather than throwing. Headless CI has none of these tools (so the OS
path is inert there); tests install an in-memory fake via
[`set_os_clipboard_backend!`](@ref).
"""
module ClipboardModule

using ..CellModule
using ..CollectionModule
using ..DocumentModule
using ..DomainModule
using ..EventModule
using ..GestureBindingModule
using ..IntentModule
using ..IoMapModule
using ..OperationModule
using ..PrimitiveModule
using ..ProjectionModule
using ..ReferenceModule
using ..SerializationModule
using ..SelectionModule
using ..TextModule

# Imported to extend: this module adds a method to each of these.
import ..DocumentModule: is_descendable_for_copy, make_copy_placeholder, get_copy_memo,
                         get_wrapped_document
import ..OperationModule: evaluate_operation, make_inverse_operation
import ..ProjectionModule: get_projection_gesture_bindings
import ..SerializationModule: pred_arguments
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward

export read_os_clipboard, write_os_clipboard!, set_os_clipboard_backend!, reset_os_clipboard_backend!
export ClipboardDocument
export ClipboardSliceToAnyProjection, ClipboardCollectionToAnyProjection,
       ClipboardSliceToAnyIoMap, ClipboardCollectionToAnyIoMap,
       ToggleClipboardSliceOperation, ToggleClipboardCollectionOperation,
       WriteOsClipboardOperation
export ClipboardSlice, ClipboardCollection
export CLIPBOARD_GESTURES
export make_clipboard_document, make_clipboard_projection
export find_clipboard_document, ClipboardCopyPolicy


include("Clipboard.jl")
include("ClipboardDocument.jl")
include("ClipboardSliceToAny.jl")
include("ClipboardCollectionToAny.jl")
include("ClipboardWrapper.jl")

end # module
