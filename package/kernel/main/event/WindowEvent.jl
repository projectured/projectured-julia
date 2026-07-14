# Fragment of `EventModule` — the window events.

"""
    WindowQuit

Event signalling that the user requested to quit the entire application. It is a
*request* the application may refuse. A close request aimed at one window is a
different event, and is identified by the window id its `EventEnvelope` carries.
"""
struct WindowQuit end
