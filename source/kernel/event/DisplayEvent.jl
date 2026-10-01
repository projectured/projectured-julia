# Fragment of `EventModule` — the event of a display.

"""
    DisplayUpdate(; time)
    DisplayUpdate(time)

The display shows a new frame of a window, and the frame differs from the one
before. A backend reports it in a `WindowInput` with the id of that window, after
it shows the frame; `time` is when it showed it. Only the backend knows what the
display shows, so no other code makes it.

The loop of the editor reads it like any other input, so a frame that changed
the display is followed by one more read, and the loop sleeps only after a frame
that changed nothing. A reader that keeps a part of the view as its state can
find that part again when it reads the event, because the view can change under
a pointer that does not move.
"""
struct DisplayUpdate <: Event
    time::Float64
end

DisplayUpdate(; time::Real) = DisplayUpdate(Float64(time))
