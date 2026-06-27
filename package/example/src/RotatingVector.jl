# Rotating vector animation example.
#
# A point rotates forever on a circle while two line charts trace its
# coordinates: the sine of the angle (the y-coordinate) aligned to the vertical
# axis, and the cosine (the x-coordinate) aligned to the horizontal axis. Every
# animated value is a computed cell that *subscribes* to the global editor time
# via `reactive_editor_time()`; the editor's main loop advances that time once
# per frame (see `Editor.run!`), so the cells re-evaluate and the canvas
# redraws. The phase origin is *sampled* once at construction via `editor_time()`
# so the angle starts at zero without the constructor itself becoming reactive.
#
# It is perpetual — nothing settles. The projection is the identity
# `PreservingProjection`: the document already *is* the animated `GraphicsCanvas`,
# so it passes straight through to the backend / `write_image`.

const _RV_W   = 600          # canvas size
const _RV_H   = 600
const _RV_CX  = 170          # circle centre
const _RV_CY  = 170
const _RV_R   = 110          # radius
const _RV_OMEGA = 2.0        # angular velocity (rad / s)
const _RV_N   = 260          # samples per chart window
const _RV_DT  = 0.02         # angle between adjacent samples
const _RV_GAP = 20           # gap between circle and charts

# Solarized-ish palette
const _RV_AXIS = (0x93, 0xa1, 0xa1, 0xff)  # grey
const _RV_DOT  = (0xd3, 0x36, 0x82, 0xff)  # magenta
const _RV_SIN  = (0x26, 0x8b, 0xd2, 0xff)  # blue   (y-coordinate)
const _RV_COS  = (0x85, 0x99, 0x00, 0xff)  # green  (x-coordinate)

function make_rotating_vector_document()
    phase0 = editor_time()                     # SAMPLE: no subscription
    angle(t) = _RV_OMEGA * (t - phase0)

    # static circle outline marking the path (transparent fill + grey border)
    ring = GraphicsCircle(_RV_CX, _RV_CY, _RV_R, 0, 0, 0, 0;
                          border_width = 1, border_color = _RV_AXIS)

    # the rotating dot — SUBSCRIBE to time
    dot = GraphicsCircle(_RV_CX, _RV_CY, 7, _RV_DOT...)
    setfn!(getfield(dot, :cx), () -> round(Int32, _RV_CX + _RV_R * cos(angle(reactive_editor_time()))))
    setfn!(getfield(dot, :cy), () -> round(Int32, _RV_CY - _RV_R * sin(angle(reactive_editor_time()))))

    # sine chart — aligned to the Y axis, scrolling right.
    # newest sample (i = 0) sits at the chart's left edge at the dot's exact cy.
    sin_chart = GraphicsPolyline([(0, 0), (0, 0)], _RV_SIN...; width = 2)
    setfn!(getfield(sin_chart, :points), () -> begin
        t = reactive_editor_time()             # SUBSCRIBE
        Tuple{Int,Int}[(_RV_CX + _RV_R + _RV_GAP + i,
                        round(Int, _RV_CY - _RV_R * sin(angle(t) - i * _RV_DT))) for i in 0:_RV_N]
    end)

    # cosine chart — aligned to the X axis, scrolling down.
    # newest sample (i = 0) sits at the chart's top edge at the dot's exact cx.
    cos_chart = GraphicsPolyline([(0, 0), (0, 0)], _RV_COS...; width = 2)
    setfn!(getfield(cos_chart, :points), () -> begin
        t = reactive_editor_time()             # SUBSCRIBE
        Tuple{Int,Int}[(round(Int, _RV_CX + _RV_R * cos(angle(t) - i * _RV_DT)),
                        _RV_CY + _RV_R + _RV_GAP + i) for i in 0:_RV_N]
    end)

    # link lines from the dot to the newest sample of each chart. They read the
    # dot's animated cells, so they animate transitively (no extra time read).
    sin_link = GraphicsLine(0, 0, 0, 0, _RV_AXIS...; width = 1)
    setfn!(getfield(sin_link, :x1), () -> Int32(dot.cx))
    setfn!(getfield(sin_link, :y1), () -> Int32(dot.cy))
    setfn!(getfield(sin_link, :x2), () -> Int32(_RV_CX + _RV_R + _RV_GAP))
    setfn!(getfield(sin_link, :y2), () -> Int32(dot.cy))

    cos_link = GraphicsLine(0, 0, 0, 0, _RV_AXIS...; width = 1)
    setfn!(getfield(cos_link, :x1), () -> Int32(dot.cx))
    setfn!(getfield(cos_link, :y1), () -> Int32(dot.cy))
    setfn!(getfield(cos_link, :x2), () -> Int32(dot.cx))
    setfn!(getfield(cos_link, :y2), () -> Int32(_RV_CY + _RV_R + _RV_GAP))

    canvas = GraphicsCanvas([ring, sin_link, cos_link, sin_chart, cos_chart, dot])
    canvas.w = Int32(_RV_W)
    canvas.h = Int32(_RV_H)
    canvas
end

# The document is already a GraphicsCanvas; pass it through unchanged.
make_rotating_vector_projection() = PreservingProjection()
