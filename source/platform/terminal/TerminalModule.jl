"""
    TerminalModule

A terminal: a document that runs one program with pipes, shows what the program
writes, and sends a line that the person types to the program. It has no
terminal device and draws no screen: no colours of the program, no cursor
moves, no program with a full screen. A program that reads a line, such as
the sign-in of an agent that prints a URL and reads a code, works in it.

The program runs in a process group of its own. Two reader tasks post what it
writes to the editor; the editor task alone writes the document. The close of
the tab of a terminal ends its program.
"""
module TerminalModule

using ..AgentModule
using ..CellModule
using ..DocumentModule
using ..EventModule
using ..GestureModule
using ..IoMapModule
using ..LayoutModule
using ..NaturalModule
using ..OperationModule
using ..PrimitiveModule
using ..ProjectionAlgebraModule
using ..ProjectionModule
using ..ReferenceModule
using ..StyleModule
using ..WidgetModule

# Imported to extend: this module adds a method to each of these.
import ..DocumentModule: get_document_title
import ..DomainModule: release_document!
import ..OperationModule: evaluate_operation, make_inverse_operation
import ..ProjectionModule: print_document, read_intent, map_reference_forward, map_reference_backward

export TerminalLine, TerminalControl, TerminalDocument, format_terminal_command, is_terminal_running,
       is_terminal_stopped,
       add_terminal_text!, add_terminal_line!
export start_terminal!, send_terminal_input!, stop_terminal!
export TerminalTheme, ScaledTerminalTheme
export TerminalToWidget, make_terminal_projection, SendTerminalInputOperation

include("TerminalDocument.jl")
include("TerminalProcess.jl")
include("TerminalTheme.jl")
include("TerminalToWidget.jl")

end # module TerminalModule
