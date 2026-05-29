"""
    ApplicationModule

Top-level application entry point. Constructs a backend, initialises it,
wires up an `Editor` with the given projection and document, and enters
the run! loop. Tears everything down cleanly on exit via the backend.

Native windows are no longer pre-allocated here — they are opened on
demand by the backend's `ScreenDocument` reconciler the first time
`write_to_devices` sees a projection output containing
`WindowDocument`s. `application` only ensures the editor has the
input/output device kinds it needs: `Screen` (the display target),
`Keyboard`, and `Mouse`.
"""
module ApplicationModule

import ..BackendModule: Backend, init!, quit!
import ..DeviceModule: Device
import ..EditorModule: Editor, run!
import ..KeyboardModule: Keyboard
import ..MouseModule: Mouse
import ..ScreenModule: Screen

export application

"""
    application(backend, projection, document)

Initialise the backend, wire up an `Editor` with the given projection
and document, and run the read-eval-print loop. The pipeline is
expected to produce a `ScreenDocument` so the backend can reconcile
native windows against it; pipelines whose output is a bare
`GraphicsCanvas` go unrendered (use `write_image` for offscreen).
"""
function application(backend::Backend, projection, document)
    init!(backend)
    try
        devices = Device[Screen(), Keyboard(), Mouse()]
        editor = Editor(backend, document, projection, devices)
        run!(editor)
    finally
        quit!(backend)
    end
end

end # module
