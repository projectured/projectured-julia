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
# The scene is painted in the Solarized palette on a dark base03 background: the
# rotation path is an *unfilled* ring, only the small rotating dot is a filled
# disc, and dashed grey links project the dot onto each chart. Both charts carry
# their own x/y axes (a zero baseline + an amplitude axis).
#
# It is perpetual — nothing settles. The projection is the identity
# `PreservingProjection`: the document already *is* the animated `GraphicsCanvas`,
# so it passes straight through to the backend / `write_image`.

const _RV_W   = 600          # canvas size
const _RV_H   = 600
const _RV_CX  = 170          # circle centre
const _RV_CY  = 170
const _RV_R   = 110          # radius
const _RV_OMEGA = 0.5        # angular velocity (rad / s) — a slow, calm rotation
const _RV_N   = 260          # samples per chart window
const _RV_DT  = 0.02         # angle between adjacent samples
const _RV_GAP = 20           # gap between circle and charts

# Solarized palette — https://ethanschoonover.com/solarized/
const _RV_BG   = (0x00, 0x2b, 0x36, 0xff)  # base03  — dark background
const _RV_AXIS = (0x58, 0x6e, 0x75, 0xff)  # base01  — ring outline + chart axes
const _RV_LINK = (0x83, 0x94, 0x96, 0xff)  # base0   — dashed projection links
const _RV_DOT  = (0xd3, 0x36, 0x82, 0xff)  # magenta — the rotating dot
const _RV_SIN  = (0x26, 0x8b, 0xd2, 0xff)  # blue    — sine   (y-coordinate)
const _RV_COS  = (0x85, 0x99, 0x00, 0xff)  # green    — cosine (x-coordinate)

function make_rotating_vector_document()
    phase0 = editor_time()                     # SAMPLE: no subscription
    angle(t) = _RV_OMEGA * (t - phase0)

    x_left = _RV_CX + _RV_R + _RV_GAP          # sine chart's left edge
    y_top  = _RV_CY + _RV_R + _RV_GAP          # cosine chart's top edge

    # solarized-dark backdrop behind everything
    background = GraphicsRect(0, 0, _RV_W, _RV_H, _RV_BG...)

    # static circle outline marking the path: an *unfilled* ring (transparent
    # fill + grey outline). Only the dot below is a filled disc.
    ring = GraphicsCircle(_RV_CX, _RV_CY, _RV_R, 0, 0, 0, 0;
                          border_width = 2, border_color = _RV_AXIS)

    # chart axes — static. Each wave gets a zero baseline (the time axis) and an
    # amplitude axis spanning ±R, so the oscillation is read against a frame.
    sin_baseline = GraphicsLine(x_left, _RV_CY, x_left + _RV_N, _RV_CY, _RV_AXIS...; width = 1)
    sin_axis     = GraphicsLine(x_left, _RV_CY - _RV_R, x_left, _RV_CY + _RV_R, _RV_AXIS...; width = 1)
    cos_baseline = GraphicsLine(_RV_CX, y_top, _RV_CX, y_top + _RV_N, _RV_AXIS...; width = 1)
    cos_axis     = GraphicsLine(_RV_CX - _RV_R, y_top, _RV_CX + _RV_R, y_top, _RV_AXIS...; width = 1)

    # The animated elements use the cell-level positional constructor, which
    # wraps each argument in a `Cell` automatically: a function argument becomes
    # a *computed* cell, a plain value a static one (see Reactive.jl). So the
    # reactive fields are just thunks passed in place — no `setfn!` — and they
    # re-evaluate each frame because they read `reactive_editor_time()`.

    # the rotating dot — its centre (cx, cy) SUBSCRIBES to time.
    dot = GraphicsCircle(
        () -> round(Int32, _RV_CX + _RV_R * cos(angle(reactive_editor_time()))),  # cx
        () -> round(Int32, _RV_CY - _RV_R * sin(angle(reactive_editor_time()))),  # cy
        7,                  # radius
        _RV_DOT...,         # fill rgba (magenta)
        0, 0, 0, 0, 0,      # border_width + rgba — filled, no outline
        nothing)            # selection

    # sine chart — aligned to the Y axis, scrolling right. Newest sample (i = 0)
    # sits at the chart's left edge at the dot's exact cy. `points` is the only
    # computed field.
    sin_chart = GraphicsPolyline(
        () -> begin
            t = reactive_editor_time()             # SUBSCRIBE
            Tuple{Int,Int}[(x_left + i,
                            round(Int, _RV_CY - _RV_R * sin(angle(t) - i * _RV_DT))) for i in 0:_RV_N]
        end,
        _RV_SIN...,         # rgba (blue)
        2,                  # width
        false, false, 8,    # start_arrow, end_arrow, arrow_size
        nothing)            # selection

    # cosine chart — aligned to the X axis, scrolling down. Newest sample (i = 0)
    # sits at the chart's top edge at the dot's exact cx.
    cos_chart = GraphicsPolyline(
        () -> begin
            t = reactive_editor_time()             # SUBSCRIBE
            Tuple{Int,Int}[(round(Int, _RV_CX + _RV_R * cos(angle(t) - i * _RV_DT)),
                            y_top + i) for i in 0:_RV_N]
        end,
        _RV_COS...,         # rgba (green)
        2,                  # width
        false, false, 8,    # start_arrow, end_arrow, arrow_size
        nothing)            # selection

    # dashed link lines from the dot to the newest sample of each chart. The
    # moving endpoints are thunks reading the dot's animated cells, so they
    # animate transitively (no extra time read). The fixed chart-edge endpoint
    # is `(x1, y1)`, so the dash pattern is anchored there and the dashes don't
    # crawl as the dot moves.
    sin_link = GraphicsLine(
        x_left,             # x1 — fixed chart edge
        () -> dot.cy,       # y1
        () -> dot.cx,       # x2
        () -> dot.cy,       # y2
        _RV_LINK...,        # rgba
        1,                  # width
        (5, 5),             # dash (on, off)
        nothing)            # selection

    cos_link = GraphicsLine(
        () -> dot.cx,       # x1
        y_top,              # y1 — fixed chart edge
        () -> dot.cx,       # x2
        () -> dot.cy,       # y2
        _RV_LINK...,        # rgba
        1,                  # width
        (5, 5),             # dash (on, off)
        nothing)            # selection

    canvas = GraphicsCanvas([background,
                             sin_baseline, sin_axis, cos_baseline, cos_axis,
                             ring, sin_link, cos_link, sin_chart, cos_chart, dot])
    canvas.w = Int32(_RV_W)
    canvas.h = Int32(_RV_H)
    canvas
end

# The document is already a GraphicsCanvas, so the example uses the identity
# `PreservingProjection` directly (see `Examples.jl`): it passes the canvas
# straight through to the backend / `write_image`.
