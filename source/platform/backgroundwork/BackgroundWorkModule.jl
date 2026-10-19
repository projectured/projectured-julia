"""
    BackgroundWorkModule

The work that the editor does in the background, as a document a person opens
like any other. The kernel keeps a plain record of each work of a background cell
in the `BackgroundWorkStore` of the editor. The
[`BackgroundWorkFeed`](BackgroundWorkFeed.jl) copies the records on its own
deadline, and only while a view shows them, into the `BackgroundWorkLog` of the
session ([`BackgroundWorkDocument.jl`](BackgroundWorkDocument.jl)): one row for
each work, newest first. [`BackgroundWorkLogToWidget`](BackgroundWorkLogToWidget.jl)
draws the log as a line that counts the works and a table of its rows, which a
person filters and sorts.
"""
module BackgroundWorkModule

using ..ArrangementModule
using ..CellModule
using ..CollectionModule
using ..DocumentModule
using ..DomainModule
using ..EditorModule
using ..FeedModule
using ..IntentModule
using ..IoMapModule
using ..LayoutModule
using ..OperationModule
using ..ProjectionAlgebraModule
using ..ProjectionModule
using ..ReferenceModule
using ..RosterModule
using ..SerializationModule
using ..StyleModule
using ..ToolModule
using ..WidgetModule

# Imported to extend: this module adds a method to each of these.
import ..DocumentModule: get_document_title
import ..DomainModule: get_insertion_aliases, make_insertion_document, get_document_decoration
import ..FeedModule: drain_changes!, compute_wake_deadline
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward
import ..SerializationModule: pred_arguments, make_pred_document
import ..EditorModule: wrap_editor!, get_wrapper_layers
import ..WidgetModule: make_graphics_projection

export BackgroundWorkRow, BackgroundWorkLog, get_session_background_work_log, flush_background_work_log!
export BackgroundWorkFeed
export BackgroundWorkLogToWidget

include("BackgroundWorkDocument.jl")
include("BackgroundWorkFeed.jl")
include("BackgroundWorkLogToWidget.jl")

end # module BackgroundWorkModule
