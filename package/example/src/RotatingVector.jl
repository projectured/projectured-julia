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
# The scene is painted in the Solarized palette (https://ethanschoonover.com/solarized/)
# on a light base3 background: the rotation path is an *unfilled* ring, only the
# small rotating dot is a filled disc, and dashed grey links project the dot onto
# each chart. Both charts carry their own x/y axes (a zero baseline + an
# amplitude axis). Geometry/timing are keyword arguments; colours are inlined as
# `(r, g, b, a)` literals with the Solarized name in a comment.
#
# It is perpetual — nothing settles. The projection is the identity
# `PreservingProjection`: the document already *is* the animated `GraphicsCanvas`,
# so it passes straight through to the backend / `write_image`.

function make_rotating_vector_document(; w = 600, h = 600,   # canvas size
                                       cx = 170, cy = 170,    # circle centre
                                       r = 110,               # radius
                                       omega = -0.5,          # angular velocity (rad/s); sign sets direction
                                       n = 260,               # samples per chart window
                                       dt = 0.02,             # angle between adjacent samples
                                       gap = 20)              # gap between circle and charts
    phase0 = editor_time()                     # SAMPLE: no subscription
    angle(t) = omega * (t - phase0)

    x_left = cx + r + gap                      # sine chart's left edge
    y_top  = cy + r + gap                      # cosine chart's top edge

    # solarized-light backdrop (base3) behind everything
    background = GraphicsRect(0, 0, w, h, 0xfd, 0xf6, 0xe3, 0xff)

    # static circle outline marking the path: an *unfilled* ring (transparent
    # fill + base01 grey outline). Only the dot below is a filled disc.
    ring = GraphicsCircle(cx, cy, r, 0, 0, 0, 0; border_width = 2, border_color = (0x58, 0x6e, 0x75, 0xff))

    # chart axes — static, base01 grey. Each wave gets a zero baseline (the time
    # axis) and an amplitude axis spanning ±R, so the oscillation is read against
    # a frame.
    sin_baseline = GraphicsLine(x_left, cy, x_left + n, cy, 0x58, 0x6e, 0x75, 0xff; width = 1)
    sin_axis     = GraphicsLine(x_left, cy - r, x_left, cy + r, 0x58, 0x6e, 0x75, 0xff; width = 1)
    cos_baseline = GraphicsLine(cx, y_top, cx, y_top + n, 0x58, 0x6e, 0x75, 0xff; width = 1)
    cos_axis     = GraphicsLine(cx - r, y_top, cx + r, y_top, 0x58, 0x6e, 0x75, 0xff; width = 1)

    # The animated elements use the cell-level positional constructor, which
    # wraps each argument in a `Cell` automatically: a function argument becomes
    # a *computed* cell, a plain value a static one (see Reactive.jl). So the
    # reactive fields are just thunks passed in place — no `setfn!` — and they
    # re-evaluate each frame because they read `reactive_editor_time()`.

    # the rotating dot — its centre (cx, cy) SUBSCRIBES to time.
    dot = GraphicsCircle(
        () -> round(Int32, cx + r * cos(angle(reactive_editor_time()))),  # cx
        () -> round(Int32, cy - r * sin(angle(reactive_editor_time()))),  # cy
        7,                          # radius
        0xd3, 0x36, 0x82, 0xff,     # fill rgba (magenta)
        0, 0, 0, 0, 0,              # border_width + rgba — filled, no outline
        nothing)                    # selection

    # sine chart — aligned to the Y axis, scrolling right. Newest sample (i = 0)
    # sits at the chart's left edge at the dot's exact cy. `points` is the only
    # computed field.
    sin_chart = GraphicsPolyline(
        () -> begin
            t = reactive_editor_time()             # SUBSCRIBE
            Tuple{Int,Int}[(x_left + i,
                            round(Int, cy - r * sin(angle(t) - i * dt))) for i in 0:n]
        end,
        0x26, 0x8b, 0xd2, 0xff,     # rgba (blue)
        2,                          # width
        false, false, 8,            # start_arrow, end_arrow, arrow_size
        nothing)                    # selection

    # cosine chart — aligned to the X axis, scrolling down. Newest sample (i = 0)
    # sits at the chart's top edge at the dot's exact cx.
    cos_chart = GraphicsPolyline(
        () -> begin
            t = reactive_editor_time()             # SUBSCRIBE
            Tuple{Int,Int}[(round(Int, cx + r * cos(angle(t) - i * dt)),
                            y_top + i) for i in 0:n]
        end,
        0x85, 0x99, 0x00, 0xff,     # rgba (green)
        2,                          # width
        false, false, 8,            # start_arrow, end_arrow, arrow_size
        nothing)                    # selection

    # dashed link lines from the dot to the newest sample of each chart, base1
    # grey. The moving endpoints are thunks reading the dot's animated cells, so
    # they animate transitively (no extra time read). The fixed chart-edge
    # endpoint is `(x1, y1)`, so the dash pattern is anchored there and the
    # dashes don't crawl as the dot moves.
    sin_link = GraphicsLine(
        x_left,                     # x1 — fixed chart edge
        () -> dot.cy,               # y1
        () -> dot.cx,               # x2
        () -> dot.cy,               # y2
        0x93, 0xa1, 0xa1, 0xff,     # rgba (base1)
        1,                          # width
        (5, 5),                     # dash (on, off)
        nothing)                    # selection

    cos_link = GraphicsLine(
        () -> dot.cx,               # x1
        y_top,                      # y1 — fixed chart edge
        () -> dot.cx,               # x2
        () -> dot.cy,               # y2
        0x93, 0xa1, 0xa1, 0xff,     # rgba (base1)
        1,                          # width
        (5, 5),                     # dash (on, off)
        nothing)                    # selection

    GraphicsCanvas([background,
                    sin_baseline, sin_axis, cos_baseline, cos_axis,
                    ring, sin_link, cos_link, sin_chart, cos_chart, dot];
                   w = w, h = h)
end
