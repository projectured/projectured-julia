"""
    McpLogModule

The MCP log: one entry for each call that a client made over MCP and the server
answered — the time, the method, the tool or the URI, the arguments, the answer,
how long the call held the editor, and whether it was a fault.

The server task writes a [`McpLogStore`](@ref) with no cell; a
[`McpLogFeed`](@ref) moves the calls into the [`McpLog`](@ref) document of the
session on the editor task, as the message log is filled. The wrapper
`mcp_log = true` of `build_editor` adds the feed, and [`make_mcp_log_tool`](@ref)
is the button of the toolbar that opens the log. The MCP adapter writes the
store; this slice names no part of the adapter.
"""
module McpLogModule

using ..CellModule
using ..CollectionModule
using ..DocumentModule
using ..DomainModule
using ..EditorModule
using ..FeedModule
using ..IoMapModule
using ..LayoutModule
using ..NaturalModule
using ..PrimitiveModule
using ..ProjectionAlgebraModule
using ..ProjectionModule
using ..ReferenceModule
using ..SerializationModule
using ..ShellModule
using ..StyleModule
using ..WidgetModule

# Imported to extend: this module adds a method to each of these.
import ..DocumentModule: get_document_title
import ..DomainModule: get_insertion_aliases, make_insertion_document
import ..FeedModule: drain_changes!, attach_wake_callback!
import ..ProjectionModule: print_document
import ..SerializationModule: pred_arguments
import ..EditorModule: wrap_editor!, get_wrapper_layers

export McpCallEntry, McpLog, get_session_mcp_log, record_mcp_call!
export McpLogStore, get_session_mcp_log_store, take_mcp_calls!, McpLogFeed, make_mcp_log_tool
export McpLogTheme, ScaledMcpLogTheme, McpLogToWidget, make_mcp_log_projection

include("McpLogDocument.jl")
include("McpLogStore.jl")
include("McpLogFeed.jl")
include("McpLogTheme.jl")
include("McpLogToWidget.jl")

end # module McpLogModule
