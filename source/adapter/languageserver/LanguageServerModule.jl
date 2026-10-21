"""
    LanguageServerModule

The language server adapter: a connection to a language server, such as
`clangd`, that speaks the Language Server Protocol over the pipes of its
process. Depends on `ProjecturedKernel`, `ProjecturedPlatform` and JSON3.

**Every piece of the wire format of the protocol lives here and nowhere else.**
A message is a JSON-RPC 2.0 object with a `Content-Length` header before it. The
connection writes the requests and the notifications, a task of its own reads
the answers, and the rest of the editor sees only the values that the
connection gives back.
"""
module LanguageServerModule

using ..KernelModule
using ..PlatformModule
using JSON3

export LanguageServerException, LanguageServerConnection, is_language_server_running,
       start_language_server!, send_language_server_request!,
       send_language_server_notification!, make_file_uri, stop_language_server!

include("LanguageServerConnection.jl")

end # module LanguageServerModule
