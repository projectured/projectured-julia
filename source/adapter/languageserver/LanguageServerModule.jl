"""
    LanguageServerModule

The language server adapter: a connection to a language server, such as
`clangd`, that speaks the Language Server Protocol over the pipes of its
process, and `SourceFile`, a C or C++ file whose names take the colours of
their kinds from the server. Depends on `ProjecturedKernel`,
`ProjecturedPlatform` and JSON3.

**Every piece of the wire format of the protocol lives here and nowhere else.**
A message is a JSON-RPC 2.0 object with a `Content-Length` header before it. The
connection writes the requests and the notifications, a task of its own reads
the answers, and the rest of the editor sees only the values that the
connection gives back.

**The print never waits for a server.** The marks of a source file are a
background cell: a read gives the last answer, moved to the text of now, and
the work that asks the server runs after the print, off the loop.
"""
module LanguageServerModule

using ..KernelModule
using ..PlatformModule
using JSON3

# Imported to extend: this module adds a method to each of these.
import ..DomainModule: acquire_document!, release_document!
import ..EditorModule: wrap_editor!, get_wrapper_layers, is_wrapper_default
import ..SerializationModule: parse_file_content, emit_text, get_file_domain
import ..WidgetModule: make_graphics_projection

export LanguageServerException, LanguageServerConnection, is_language_server_running,
       start_language_server!, send_language_server_request!,
       send_language_server_notification!, make_file_uri, stop_language_server!
export SEMANTIC_TOKEN_ROLES, compute_semantic_text_marks, close_language_server_document!,
       convert_semantic_tokens
export LanguageServers, get_language_server!, stop_language_servers!
export SOURCE_FILE_LANGUAGES, find_source_file_language, SourceFile, make_source_file_code_projection

include("LanguageServerConnection.jl")
include("SemanticTokens.jl")
include("LanguageServerSession.jl")
include("LanguageServerDocument.jl")

# Each extension of `SOURCE_FILE_LANGUAGES` opens as a `SourceFile`.
function __init__()
    for extension in keys(SOURCE_FILE_LANGUAGES)
        register_file_document_type!(extension, SourceFile)
    end
end

end # module LanguageServerModule
