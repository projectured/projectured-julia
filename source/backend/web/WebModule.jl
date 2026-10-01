"""
    WebModule

The web backend: the editor in a browser. An HTTP server serves the page, and a
WebSocket carries the drawing of each window as JSON, a whole picture first and
then the parts that changed, and brings the input of the browser back. It needs
no SDL: the text metrics come from the font files.
"""
module WebModule

using ..KernelModule
using ..PlatformModule
using HTTP
using JSON3
using Base64: base64encode

# Imported to extend: this module adds a method to each of these. The backend
# contract is extended by qualification instead, `BackendModule.write_to_devices`.
import ..EditorModule: get_backend_name, get_backend_output

export WebBackend, get_web_asset_directory, convert_web_key_to_symbol

include("WebBackend.jl")

end # module WebModule
