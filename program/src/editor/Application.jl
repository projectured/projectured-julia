"""
    ApplicationModule

Top-level application entry point. Constructs a backend, initialises it,
creates a window and devices, constructs the Editor, and enters the run!
loop. Tears everything down cleanly on exit via the backend.
"""
module ApplicationModule

import ..BackendModule: Backend, init!, quit!, open_window!, close_window!
import ..DeviceModule: Device
import ..EditorModule: Editor, run!
import ..KeyboardModule: Keyboard
import ..MouseModule: Mouse
import ..WindowModule: Window

export application

# ═══════════════════════════════════════════════════════════════════════════
# Configuration defaults
# ═══════════════════════════════════════════════════════════════════════════

const DEFAULT_TITLE     = "ProjecturEd"
const DEFAULT_WIDTH     = 2400
const DEFAULT_HEIGHT    = 1600

"""
    application(backend, projection, document; title, width, height)

Initialise the backend, open a window, wire up an `Editor` with the
given projection and document, and run the read-eval-print loop.
"""
function application(backend::Backend, projection, document;
                     title::AbstractString,
                     width::Integer,
                     height::Integer)
    init!(backend)
    try
        window = Window(title, width, height)
        open_window!(backend, window)
        devices = Device[window, Keyboard(), Mouse()]
        editor = Editor(backend, document, projection, devices)
        run!(editor)
        close_window!(backend, window)
    finally
        quit!(backend)
    end
end

end # module
