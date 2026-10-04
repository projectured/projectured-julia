"""
    MessageLogModule

A record of what the program said — a document that holds the last N log
messages a Julia logger captured.

The buffer has a fixed size. `record_message!` appends one entry and deletes
the oldest entry when the buffer is full. The entries live in a `CellVector`,
so an append invalidates every reader of the collection and the display
redraws.

[`MessageLogToSyntax`](MessageLogToSyntax.jl) projects the log onto the
Syntax → Text → Graphics path. [`MessageLogLogger`](MessageLogCapture.jl) is
the Julia logger that fills it.
"""
module MessageLogModule

using ..CellModule
using ..CollectionModule
using ..DocumentModule
using ..DomainModule
using ..IoMapModule
using ..NaturalModule
using ..ProjectionModule
using ..ReferenceModule
using ..SerializationModule
using ..StyleModule
using ..SyntaxModule
using ..TextModule

using ..FeedModule
using ..EditorModule

# Imported to extend: this module adds a method to each of these.
import ..DocumentModule: get_document_title
import ..DomainModule: get_insertion_aliases, make_insertion_document
import ..FeedModule: drain_changes!, attach_wake_callback!
import ..ProjectionModule: print_document
import ..SerializationModule: pred_arguments
import ..EditorModule: wrap_editor!, get_wrapper_layers

export MessageLogStore, get_session_message_log_store, take_message_lines!,
       attach_message_log_wake!, MessageLogFeed
export MessageLogEntry, MessageLog, get_session_message_log,
       record_message!, clear_message_log!
export MessageLogLogger, install_message_log_capture!, remove_message_log_capture!
export MessageLogTheme, ScaledMessageLogTheme
export MessageLogToSyntax, make_message_log_projection

include("MessageLogDocument.jl")
include("MessageLogStore.jl")
include("MessageLogCapture.jl")
include("MessageLogFeed.jl")
include("MessageLogTheme.jl")
include("MessageLogToSyntax.jl")

end # module
